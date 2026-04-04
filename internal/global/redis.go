package global

import (
	"context"
	"os"

	"github.com/amemiya02/hmdp-go/config"
	"github.com/redis/go-redis/v9"
)

var RedisClient *redis.Client

// 初始化redis客户端
func init() {
	if os.Getenv("HMDP_SKIP_REDIS_INIT") == "1" {
		return
	}

	cfg := config.GlobalConfig.Redis
	RedisClient = redis.NewClient(&redis.Options{
		Addr:     joinHostPort(cfg.Host, cfg.Port),
		Password: cfg.Password,
		DB:       cfg.Db,
	})

	ctx := context.Background()
	if err := RedisClient.Ping(ctx).Err(); err != nil {
		panic("redis connect failed: " + err.Error())
	}

	Logger.Info("Connected to Redis...")
}
