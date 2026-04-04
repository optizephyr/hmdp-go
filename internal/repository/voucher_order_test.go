package repository

import (
	"context"
	"testing"

	_ "github.com/amemiya02/hmdp-go/config"
	"github.com/amemiya02/hmdp-go/internal/global"
	"github.com/amemiya02/hmdp-go/internal/model/entity"
)

func TestCreateVoucherOrderPersistsOrder(t *testing.T) {
	ctx := context.Background()
	repo := NewVoucherOrderRepository()

	order := &entity.VoucherOrder{
		ID:        998877665544,
		UserID:    998877,
		VoucherID: 998878,
	}

	if err := global.Db.WithContext(ctx).Where("id = ?", order.ID).Delete(&entity.VoucherOrder{}).Error; err != nil {
		t.Fatalf("cleanup before insert failed: %v", err)
	}
	t.Cleanup(func() {
		_ = global.Db.WithContext(ctx).Where("id = ?", order.ID).Delete(&entity.VoucherOrder{}).Error
	})

	tx := global.Db.WithContext(ctx).Begin()
	if tx.Error != nil {
		t.Fatalf("begin transaction failed: %v", tx.Error)
	}
	if err := repo.CreateVoucherOrder(tx, order); err != nil {
		_ = tx.Rollback().Error
		t.Fatalf("create voucher order failed: %v", err)
	}
	if err := tx.Commit().Error; err != nil {
		t.Fatalf("commit transaction failed: %v", err)
	}

	var count int64
	if err := global.Db.WithContext(ctx).Model(&entity.VoucherOrder{}).Where("id = ?", order.ID).Count(&count).Error; err != nil {
		t.Fatalf("count inserted order failed: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected 1 persisted order, got %d", count)
	}
}
