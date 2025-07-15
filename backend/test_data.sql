-- Bu dosya, nihai veritabanı şeması oluşturulduktan sonra çalıştırılmalıdır.

USE `enzo`; -- Veritabanı adını doğrulayın

-- 1. Branches Ekle
INSERT INTO `branches` (`id`, `name`, `branch_code`, `address`) VALUES
(1, 'London Central', 'LON-C', '123 Oxford Street, London'),
(2, 'Manchester North', 'MAN-N', '456 Deansgate, Manchester');

-- 2. Depoları Güncelle (branch_id ile)
INSERT INTO `warehouses` (`id`, `name`, `warehouse_code`, `branch_id`) VALUES
(1, 'SOUTHALL WAREHOUSE', 'WHS-SLL', 1),
(2, 'MANCHESTER WAREHOUSE', 'WHS-MNC', 2)
ON DUPLICATE KEY UPDATE `name`=VALUES(`name`), `warehouse_code`=VALUES(`warehouse_code`), `branch_id`=VALUES(`branch_id`);

-- 3. Rafları ekle
INSERT INTO `shelfs` (`warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, '10A21', '10A21', 1),
(1, '10A22', '10A22', 1),
(1, '10B21', '10B21', 1),
(2, '10B22', '10B22', 1);

-- 4. Çalışanları ekle (warehouse_id ile depolara atanır)
INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `warehouse_id`, `branch_id`) VALUES
(1, 'Yusuf', 'KAHRAMAN', 'foxxafa', '123', 1, 1),
(2, 'Mehmet', 'Kaya', 'mehmet', '123', 1, 1),
(3, 'Zeynep', 'Celik', 'zeynep.celik', 'zeynep123', 2, 2);

-- 5. Ürünleri ekle
INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Barcode1`, `aktif`) VALUES
(1, 'KOL-001', 'Kola 2.5 LT', '8690001123456', 1),
(2, 'SUT-001', 'Sut 1 LT', '8690002123457', 1),
(3, 'SU-001', 'Su 5 LT', '8690003123458', 1),
(4, 'CKL-007', 'Cikolata 100g', '8690004123459', 1),
(5, 'MKN-001', 'Makarna 500g', '8690005123450', 1);

-- 6. Satın Alma Siparişlerini ekle
INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `po_id`, `status`, `branch_id`) VALUES
(101, '2025-06-22', 'PO-25B001', 1, 1), -- Depo 1'in (branch_id=1) siparişi
(102, '2025-06-23', 'PO-25B002', 1, 1), -- Depo 1'in (branch_id=1) siparişi
(201, '2025-06-22', 'PO-25I001', 1, 2); -- Depo 2'nin (branch_id=2) siparişi

-- 7. Sipariş Satırlarını ekle
INSERT INTO `satin_alma_siparis_fis_satir` (`id`, `siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(1, 101, 1, 50.00, 'BOX'),
(2, 101, 2, 100.00, 'BOX'),
(3, 102, 5, 250.00, 'BOX'),
(4, 201, 3, 300.00, 'BOX'),
(5, 201, 4, 150.00, 'BOX');

