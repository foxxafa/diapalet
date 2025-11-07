-- ==========================================
-- UUID Migration Öncesi Kontrol Sorguları
-- ==========================================

-- 1. inventory_stock tablosundaki mevcut durumu gör
-- Kaç kayıt etkilenecek ve hangi değerler atanacak?
SELECT
    ist.id as stock_id,
    ist.goods_receipt_id as old_goods_receipt_id,
    ist.receipt_operation_uuid as current_uuid,
    gr.goods_receipt_id as matched_receipt_id,
    gr.operation_unique_id as new_uuid_to_assign,
    CASE
        WHEN gr.operation_unique_id IS NULL THEN '⚠️ UUID BULUNAMADI!'
        WHEN ist.receipt_operation_uuid IS NOT NULL THEN '✅ ZATEN DOLU'
        ELSE '🔄 GÜNCELLENECEK'
    END as status
FROM inventory_stock ist
LEFT JOIN goods_receipts gr ON ist.goods_receipt_id = gr.goods_receipt_id
WHERE ist.goods_receipt_id IS NOT NULL
ORDER BY ist.id
LIMIT 50;

-- 2. Özet istatistikler
SELECT
    '📊 inventory_stock Özet' as info,
    COUNT(*) as total_with_goods_receipt_id,
    SUM(CASE WHEN gr.operation_unique_id IS NOT NULL THEN 1 ELSE 0 END) as will_be_updated,
    SUM(CASE WHEN gr.operation_unique_id IS NULL THEN 1 ELSE 0 END) as orphaned_records,
    SUM(CASE WHEN ist.receipt_operation_uuid IS NOT NULL THEN 1 ELSE 0 END) as already_has_uuid
FROM inventory_stock ist
LEFT JOIN goods_receipts gr ON ist.goods_receipt_id = gr.goods_receipt_id
WHERE ist.goods_receipt_id IS NOT NULL;

-- 3. Orphaned records - goods_receipt_id var ama goods_receipts'te yok
-- Bu kayıtlar PROBLEMLİ!
SELECT
    '⚠️ Orphaned Records (goods_receipt bulunamadı)' as warning,
    ist.id,
    ist.goods_receipt_id,
    ist.urun_key,
    ist.quantity,
    ist.stock_status
FROM inventory_stock ist
LEFT JOIN goods_receipts gr ON ist.goods_receipt_id = gr.goods_receipt_id
WHERE ist.goods_receipt_id IS NOT NULL
  AND gr.goods_receipt_id IS NULL;

-- 4. inventory_transfers için aynı kontroller
SELECT
    '📊 inventory_transfers Kontrol' as info,
    it.id as transfer_id,
    it.goods_receipt_id as old_goods_receipt_id,
    it.receipt_operation_uuid as current_uuid,
    gr.operation_unique_id as new_uuid_to_assign,
    CASE
        WHEN gr.operation_unique_id IS NULL THEN '⚠️ UUID BULUNAMADI!'
        WHEN it.receipt_operation_uuid IS NOT NULL THEN '✅ ZATEN DOLU'
        ELSE '🔄 GÜNCELLENECEK'
    END as status
FROM inventory_transfers it
LEFT JOIN goods_receipts gr ON it.goods_receipt_id = gr.goods_receipt_id
WHERE it.goods_receipt_id IS NOT NULL
ORDER BY it.id
LIMIT 50;

-- 5. inventory_transfers özet
SELECT
    '📊 inventory_transfers Özet' as info,
    COUNT(*) as total_with_goods_receipt_id,
    SUM(CASE WHEN gr.operation_unique_id IS NOT NULL THEN 1 ELSE 0 END) as will_be_updated,
    SUM(CASE WHEN gr.operation_unique_id IS NULL THEN 1 ELSE 0 END) as orphaned_records,
    SUM(CASE WHEN it.receipt_operation_uuid IS NOT NULL THEN 1 ELSE 0 END) as already_has_uuid
FROM inventory_transfers it
LEFT JOIN goods_receipts gr ON it.goods_receipt_id = gr.goods_receipt_id
WHERE it.goods_receipt_id IS NOT NULL;

-- 6. goods_receipts UUID kontrolü
-- Her goods_receipt'in UUID'si var mı?
SELECT
    '📊 goods_receipts UUID Durumu' as info,
    COUNT(*) as total_receipts,
    SUM(CASE WHEN operation_unique_id IS NOT NULL THEN 1 ELSE 0 END) as has_uuid,
    SUM(CASE WHEN operation_unique_id IS NULL THEN 1 ELSE 0 END) as missing_uuid
FROM goods_receipts;

-- 7. UUID eksik olan goods_receipts kayıtları (VARSA PROBLEM!)
SELECT
    '⚠️ UUID Eksik goods_receipts' as warning,
    goods_receipt_id,
    siparis_id,
    delivery_note_number,
    receipt_date
FROM goods_receipts
WHERE operation_unique_id IS NULL
LIMIT 20;
