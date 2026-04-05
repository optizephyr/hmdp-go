//go:build k6data

package test

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	_ "github.com/amemiya02/hmdp-go/config"
	"github.com/amemiya02/hmdp-go/internal/global"

	"github.com/amemiya02/hmdp-go/internal/constant"

	"github.com/amemiya02/hmdp-go/internal/model/entity"
	"github.com/google/uuid"
)

func TestGenerate1000Tokens(t *testing.T) {
	ctx := context.Background()
	count := resolveTokenExportCount()
	if err := ensureTokenUsers(ctx, count); err != nil {
		t.Fatalf("准备 token 用户失败: %v", err)
	}

	// 1. 从数据库查出指定数量的用户
	var users []entity.User
	err := global.Db.WithContext(ctx).Order("id").Limit(count).Find(&users).Error
	if err != nil {
		t.Fatalf("查询用户失败: %v", err)
	}
	if len(users) != count {
		t.Fatalf("期望导出 %d 个用户，但实际只有 %d 个", count, len(users))
	}

	outputPath, err := resolveTokenExportPath()
	if err != nil {
		t.Fatalf("解析 token 导出路径失败: %v", err)
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		t.Fatalf("创建 token 导出目录失败: %v", err)
	}

	// 2. 创建一个 CSV 文件，准备给 k6 用
	file, err := os.Create(outputPath)
	if err != nil {
		t.Fatalf("创建文件失败: %v", err)
	}
	defer file.Close()

	if _, err := file.WriteString("userId,token\n"); err != nil {
		t.Fatalf("写入 CSV 表头失败: %v", err)
	}

	// 3. 开启 Redis Pipeline，极速批量写入，拒绝频繁的网络 IO！
	pipe := global.RedisClient.Pipeline()

	for _, user := range users {
		// 生成去划线的 UUID 作为 Token
		token := uuid.New().String()
		tokenKey := constant.LoginUserKey + token

		// 组装要存入 Redis 的用户信息 (根据你实际的 UserDTO 字段调整)
		userMap := map[string]interface{}{
			"id":       strconv.FormatUint(user.ID, 10),
			"nickName": user.NickName,
			// "icon": user.Icon,
		}

		// 将用户信息存入 Redis Hash 结构
		pipe.HSet(ctx, tokenKey, userMap)
		// 设置 Token 过期时间（比如 24 小时，足够压测用了）
		pipe.Expire(ctx, tokenKey, 24*time.Hour)

		// 将 Token 写入 CSV 文件，每行一个 userId/token 组合
		if _, err := file.WriteString(fmt.Sprintf("%d,%s\n", user.ID, token)); err != nil {
			t.Fatalf("写入 CSV 行失败: %v", err)
		}
	}

	// 4. 一次性将命令发送给 Redis 执行
	_, err = pipe.Exec(ctx)
	if err != nil {
		t.Fatalf("批量写入 Redis 失败: %v", err)
	}

	fmt.Printf("成功生成 %d 个用户的 Token，并已导出到 %s！\n", len(users), outputPath)
}

func ensureTokenUsers(ctx context.Context, count int) error {
	var existingCount int64
	if err := global.Db.WithContext(ctx).Model(&entity.User{}).Count(&existingCount).Error; err != nil {
		return err
	}
	if existingCount >= int64(count) {
		return nil
	}

	missing := count - int(existingCount)
	users := make([]entity.User, 0, missing)
	for i := 0; i < missing; i++ {
		seq := int(existingCount) + i + 1
		users = append(users, entity.User{
			Phone:    fmt.Sprintf("199%08d", seq),
			NickName: fmt.Sprintf("k6_user_%d", seq),
		})
	}

	return global.Db.WithContext(ctx).CreateInBatches(users, 500).Error
}

func resolveTokenExportPath() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}

	root := wd
	for {
		goModPath := filepath.Join(root, "go.mod")
		if _, statErr := os.Stat(goModPath); statErr == nil {
			return filepath.Join(root, "loadtest", "k6", "data", "token-users.csv"), nil
		} else if !os.IsNotExist(statErr) {
			return "", statErr
		}

		parent := filepath.Dir(root)
		if parent == root {
			break
		}
		root = parent
	}

	return "", fs.ErrNotExist
}
