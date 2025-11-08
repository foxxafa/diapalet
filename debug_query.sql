-- Telefondaki inventory_stock kontrol sorguları
-- Bu sorguları Flutter app içinden debug olarak çalıştırın

-- 1. deneme000a12 paletinin kaydını bulalım
SELECT
    id,
    stock_uuid,
    urun_key,
    receipt_operation_uuid,
    pallet_barcode,
    quantity,
    stock_status,
    location_id1	29645	ef2edb62-7f65-4f69-bb1c-1fd3a575a4d8	606685	606686	43623		10.0	deneme000a10	2025-12-12	available				2025-11-07T23:55:58.610739Z	2025-11-07T23:55:58.610815Z
FROM inventory_stock
WHERE pallet_barcode = 'deneme000a12';

-- 2. Receiving durumundaki tüm kayıtlara bakalım
SELECT
    COUNT(*) as total,
    SUM(CASE WHEN receipt_operation_uuid IS NULL THEN 1 ELSE 0 END) as null_uuid_count,
    SUM(CASE WHEN receipt_operation_uuid IS NOT NULL THEN 1 ELSE 0 END) as has_uuid_count
FROM inventory_stock
WHERE stock_status = 'receiving';

-- 3. Bu paletin goods_receipts kaydını bulalım
SELECT
    gr.goods_receipt_id,
    gr.operation_unique_id,
    gr.delivery_note_number,
    gr.siparis_id
FROM goods_receipts gr
INNER JOIN inventory_stock ist ON ist.receipt_operation_uuid = gr.operation_unique_id
WHERE ist.pallet_barcode = 'deneme000a12'
LIMIT 1;
