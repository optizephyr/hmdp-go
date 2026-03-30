-- Baseline reset template for seckill benchmarks.
-- Pass `@fixture_voucher_id` and `@fixture_stock` with mysql --init-command when needed.

SET @fixture_voucher_id = COALESCE(@fixture_voucher_id, 1);
SET @fixture_stock = COALESCE(@fixture_stock, 200);

START TRANSACTION;

-- Restore the fixture voucher stock and ensure the row exists.
INSERT INTO tb_seckill_voucher (voucher_id, stock, begin_time, end_time)
VALUES (@fixture_voucher_id, @fixture_stock, NOW() - INTERVAL 1 DAY, NOW() + INTERVAL 1 DAY)
ON DUPLICATE KEY UPDATE
  stock = VALUES(stock),
  begin_time = VALUES(begin_time),
  end_time = VALUES(end_time),
  update_time = NOW();

-- Remove historical orders for the same voucher so each run starts clean.
DELETE FROM tb_voucher_order
WHERE voucher_id = @fixture_voucher_id;

COMMIT;
