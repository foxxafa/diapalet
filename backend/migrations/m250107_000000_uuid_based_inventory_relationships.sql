-- Migration: UUID-based Inventory Relationships
-- Date: 2025-01-07
-- Description: Replace siparis_id and goods_receipt_id with receipt_operation_uuid
--              in inventory_stock and inventory_transfers tables

-- ============================================================================
-- BACKUP CRITICAL: Bu migration öncesi veritabanı yedek alınmalıdır!
-- ============================================================================

-- Step 1: Add new column receipt_operation_uuid to inventory_stock
ALTER TABLE `inventory_stock`
ADD COLUMN `receipt_operation_uuid` VARCHAR(36) DEFAULT NULL COMMENT 'UUID of the goods receipt (goods_receipts.operation_unique_id)'
AFTER `location_id`;

-- Step 2: Populate receipt_operation_uuid from existing goods_receipt_id
UPDATE `inventory_stock` ist
LEFT JOIN `goods_receipts` gr ON ist.goods_receipt_id = gr.goods_receipt_id
SET ist.receipt_operation_uuid = gr.operation_unique_id
WHERE ist.goods_receipt_id IS NOT NULL;

-- Step 3: Add index for performance
CREATE INDEX `idx_inventory_stock_receipt_uuid` ON `inventory_stock` (`receipt_operation_uuid`);

-- Step 4: Drop old columns (after data migration is verified)
-- IMPORTANT: Verify data migration before running these commands
-- ALTER TABLE `inventory_stock` DROP COLUMN `siparis_id`;
-- ALTER TABLE `inventory_stock` DROP COLUMN `goods_receipt_id`;

-- Step 5: Add new column receipt_operation_uuid to inventory_transfers
ALTER TABLE `inventory_transfers`
ADD COLUMN `receipt_operation_uuid` VARCHAR(36) DEFAULT NULL COMMENT 'UUID of the goods receipt (for putaway operations)'
AFTER `pallet_barcode`;

-- Step 6: Populate receipt_operation_uuid from existing goods_receipt_id
UPDATE `inventory_transfers` it
LEFT JOIN `goods_receipts` gr ON it.goods_receipt_id = gr.goods_receipt_id
SET it.receipt_operation_uuid = gr.operation_unique_id
WHERE it.goods_receipt_id IS NOT NULL;

-- Step 7: Add index for performance
CREATE INDEX `idx_inventory_transfers_receipt_uuid` ON `inventory_transfers` (`receipt_operation_uuid`);

-- Step 8: Drop old columns from inventory_transfers (after verification)
-- IMPORTANT: Verify data migration before running these commands
-- ALTER TABLE `inventory_transfers` DROP COLUMN `siparis_id`;
-- ALTER TABLE `inventory_transfers` DROP COLUMN `goods_receipt_id`;

-- ============================================================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================================================
-- DROP INDEX `idx_inventory_stock_receipt_uuid` ON `inventory_stock`;
-- ALTER TABLE `inventory_stock` DROP COLUMN `receipt_operation_uuid`;
-- DROP INDEX `idx_inventory_transfers_receipt_uuid` ON `inventory_transfers`;
-- ALTER TABLE `inventory_transfers` DROP COLUMN `receipt_operation_uuid`;
