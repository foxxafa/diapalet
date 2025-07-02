-- Bu dosya, nihai veritabanı şeması oluşturulduktan sonra çalıştırılmalıdır.

USE `enzo`; -- Veritabanı adını doğrulayın

-- 1. Depoları ekle (branch_id ile birlikte)
-- branch_id, ana sistemdeki şube kimliğidir ve siparişlerle eşleşmek için kullanılır.
INSERT INTO `warehouses` (`id`, `name`, `warehouse_code`, `branch_id`) VALUES
(1, 'SOUTHALL WAREHOUSE', 'WHS-SLL', 1),
(2, 'MANCHESTER WAREHOUSE', 'WHS-MNC', 2);

-- 2. Rafları ekle (Artık warehouses_shelfs değil, 'shelfs' tablosuna)
-- Sanal Mal Kabul Alanı (shelf_id=NULL) için buraya bir kayıt eklenmez.
INSERT INTO `shelfs` (`warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, '10A21', '10A21', 1),
(1, '10A22', '10A22', 1),
(1, '10B21', '10B21', 1),
(2, '10B22', '10B22', 1);

-- 3. Çalışanları ekle (warehouse_id ile depolara atanır)
INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `warehouse_id`, `branch_id`) VALUES
(1, 'Yusuf', 'KAHRAMAN', 'foxxafa', '123', 1, 1),
(2, 'Mehmet', 'Kaya', 'mehmet', '123', 1, 1),
(3, 'Zeynep', 'Celik', 'zeynep.celik', 'zeynep123', 2, 2);

-- 4. Ürünleri ekle (sadece temel alanlar)
INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Barcode1`, `aktif`) VALUES
(1, 'KOL-001', 'Kola 2.5 LT', '8690001123456', 1),
(2, 'SUT-001', 'Sut 1 LT', '8690002123457', 1),
(3, 'SU-001', 'Su 5 LT', '8690003123458', 1),
(4, 'CKL-007', 'Cikolata 100g', '8690004123459', 1),
(5, 'MKN-001', 'Makarna 500g', '8690005123450', 1);

-- 5. Satın Alma Siparişlerini ekle
-- DİKKAT: branch_id değerleri warehouse_id ile uyumlu hale getirildi
-- Bu branch_id, siparişin hangi depoya ait olduğunu belirtir.
INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `po_id`, `status`, `branch_id`) VALUES
(101, '2025-06-22', 'PO-25B001', 1, 1), -- Depo 1'in (branch_id=1) siparişi
(102, '2025-06-23', 'PO-25B002', 1, 1), -- Depo 1'in (branch_id=1) siparişi
(201, '2025-06-22', 'PO-25I001', 1, 2); -- Depo 2'nin (branch_id=2) siparişi

-- 6. Sipariş Satırlarını ekle
INSERT INTO `satin_alma_siparis_fis_satir` (`id`, `siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(1, 101, 1, 50.00, 'BOX'),
(2, 101, 2, 100.00, 'BOX'),
(3, 102, 5, 250.00, 'BOX'),
(4, 201, 3, 300.00, 'BOX'),
(5, 201, 4, 150.00, 'BOX');

-- Test Data for Inventory Transfer System

-- Insert test employees
INSERT INTO employees (id, first_name, last_name, username, password, warehouse_id, is_active) VALUES 
(1, 'Test', 'Employee', 'test', 'test123', 1, 1)
ON DUPLICATE KEY UPDATE 
first_name = VALUES(first_name), 
last_name = VALUES(last_name), 
warehouse_id = VALUES(warehouse_id);

-- Insert test warehouse and shelfs
INSERT INTO warehouses (id, name, warehouse_code, branch_id) VALUES 
(1, 'Ana Depo', 'WH001', 1)
ON DUPLICATE KEY UPDATE 
name = VALUES(name), 
warehouse_code = VALUES(warehouse_code);

INSERT INTO shelfs (id, warehouse_id, name, code, is_active) VALUES 
(1, 1, '10A21', '10A21', 1),
(2, 1, '10A22', '10A22', 1),
(3, 1, '10B21', '10B21', 1),
(4, 1, '10B22', '10B22', 1)
ON DUPLICATE KEY UPDATE 
name = VALUES(name), 
code = VALUES(code), 
is_active = VALUES(is_active);

-- Insert test products
INSERT INTO urunler (UrunId, StokKodu, UrunAdi, Barcode1, aktif) VALUES 
(1001, 'PROD001', 'Test Ürün 1', '1234567890123', 1),
(1002, 'PROD002', 'Test Ürün 2', '2345678901234', 1),
(1003, 'PROD003', 'Test Ürün 3', '3456789012345', 1),
(1004, 'PROD004', 'Test Ürün 4', '4567890123456', 1)
ON DUPLICATE KEY UPDATE 
UrunAdi = VALUES(UrunAdi), 
Barcode1 = VALUES(Barcode1), 
aktif = VALUES(aktif);

-- Insert test purchase order
INSERT INTO satin_alma_siparis_fis (id, po_id, tarih, branch_id, status) VALUES 
(101, 'PO-2024-001', '2024-01-15', 1, 2)
ON DUPLICATE KEY UPDATE 
po_id = VALUES(po_id), 
tarih = VALUES(tarih), 
status = VALUES(status);

-- Insert purchase order lines
INSERT INTO satin_alma_siparis_fis_satir (id, siparis_id, urun_id, miktar) VALUES 
(201, 101, 1001, 100.00),
(202, 101, 1002, 50.00),
(203, 101, 1003, 75.00)
ON DUPLICATE KEY UPDATE 
miktar = VALUES(miktar);

-- Insert inventory stock in goods receiving area (NULL location_id)
-- These represent items that have been received but not yet placed on shelves
INSERT INTO inventory_stock (id, urun_id, location_id, quantity, pallet_barcode, stock_status, siparis_id) VALUES 
(1, 1001, NULL, 80.00, 'PLT001', 'receiving', 101),
(2, 1002, NULL, 30.00, 'PLT002', 'receiving', 101),
(3, 1003, NULL, 60.00, NULL, 'receiving', 101)
ON DUPLICATE KEY UPDATE 
quantity = VALUES(quantity), 
stock_status = VALUES(stock_status), 
siparis_id = VALUES(siparis_id);

-- Insert inventory stock on shelves (available for transfer)
INSERT INTO inventory_stock (id, urun_id, location_id, quantity, pallet_barcode, stock_status, siparis_id) VALUES 
(4, 1001, 1, 50.00, 'PLT003', 'available', NULL),
(5, 1002, 2, 25.00, NULL, 'available', NULL),
(6, 1004, 3, 100.00, 'PLT004', 'available', NULL),
(7, 1004, 4, 75.00, NULL, 'available', NULL)
ON DUPLICATE KEY UPDATE 
quantity = VALUES(quantity), 
stock_status = VALUES(stock_status);

-- Insert goods receipt for the test order
INSERT INTO goods_receipts (id, siparis_id, employee_id, receipt_date) VALUES 
(1, 101, 1, '2024-01-15 10:00:00')
ON DUPLICATE KEY UPDATE 
employee_id = VALUES(employee_id), 
receipt_date = VALUES(receipt_date);

-- Insert goods receipt items
INSERT INTO goods_receipt_items (id, receipt_id, urun_id, quantity_received, pallet_barcode) VALUES 
(1, 1, 1001, 80.00, 'PLT001'),
(2, 1, 1002, 30.00, 'PLT002'),
(3, 1, 1003, 60.00, NULL)
ON DUPLICATE KEY UPDATE 
quantity_received = VALUES(quantity_received), 
pallet_barcode = VALUES(pallet_barcode);

-- Note: wms_putaway_status table will be populated automatically as transfers are made from receiving area to shelves