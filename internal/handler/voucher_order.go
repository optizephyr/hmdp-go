package handler

import (
	"net/http"

	"github.com/amemiya02/hmdp-go/internal/service"
	"github.com/gin-gonic/gin"
)

type VoucherOrderHandler struct {
	VoucherOrderService *service.VoucherOrderService
}

func NewVoucherOrderHandler() *VoucherOrderHandler {
	return &VoucherOrderHandler{
		VoucherOrderService: service.NewVoucherOrderService(),
	}
}

func (vo *VoucherOrderHandler) SeckillVoucher(c *gin.Context) {
	var req struct {
		ID uint64 `uri:"id"`
	}
	if err := c.ShouldBindUri(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, vo.VoucherOrderService.SeckillVoucherByRedisAndRocketMQ(c, req.ID))
}

// SeckillVoucherTxBaseline A/B 压测基线：同步事务内完成校验库存、扣减库存、创建订单。
func (vo *VoucherOrderHandler) SeckillVoucherTxBaseline(c *gin.Context) {
	var req struct {
		ID uint64 `uri:"id"`
	}
	if err := c.ShouldBindUri(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, vo.VoucherOrderService.SeckillVoucherByTxBaseline(c, req.ID))
}
