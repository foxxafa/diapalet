-- Bu dosya, nihai veritabanı şeması oluşturulduktan sonra çalıştırılmalıdır.

USE `diapalet_test`; -- Veritabanı adını doğrulayın

-- 1. Depoları ekle (branch_id ile birlikte)
-- branch_id, ana sistemdeki şube kimliğidir ve siparişlerle eşleşmek için kullanılır.
INSERT INTO `warehouses` (`id`, `name`, `warehouse_code`, `branch_id`) VALUES
(1, 'SOUTHALL WAREHOUSE', 'WHS-SLL', 10),
(2, 'MANCHESTER WAREHOUSE', 'WHS-MNC', 20);

-- 2. Rafları ekle (Artık warehouses_shelfs değil, 'shelfs' tablosuna)
-- Sanal Mal Kabul Alanı (shelf_id=NULL) için buraya bir kayıt eklenmez.
INSERT INTO `shelfs` (`warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, 'Koridor A, Raf 01', 'A-01', 1),
(1, 'Koridor A, Raf 02', 'A-02', 1),
(1, 'Koridor B, Raf 01', 'B-01', 1),
(2, 'Koridor X, Raf 01', 'X-01', 1);

-- 3. Çalışanları ekle (warehouse_id ile depolara atanır)
INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `warehouse_id`, `branch_id`) VALUES
(1, 'Yusuf', 'KAHRAMAN', 'foxxafa', '123', 1, 10),
(2, 'Mehmet', 'Kaya', 'mehmet', '123', 1, 10),
(3, 'Zeynep', 'Celik', 'zeynep.celik', 'zeynep123', 2, 20);

-- 4. Ürünleri ekle (sadece temel alanlar)
INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Barcode1`, `aktif`) VALUES
(1, 'KOL-001', 'Kola 2.5 LT', '8690001123456', 1),
(2, 'SUT-001', 'Sut 1 LT', '8690002123457', 1),
(3, 'SU-001', 'Su 5 LT', '8690003123458', 1),
(4, 'CKL-007', 'Cikolata 100g', '8690004123459', 1),
(5, 'MKN-001', 'Makarna 500g', '8690005123450', 1);

-- 5. Satın Alma Siparişlerini ekle
-- DİKKAT: Artık lokasyon_id/shelf_id yerine 'branch_id' kullanılıyor.
-- Bu branch_id, siparişin hangi depoya ait olduğunu belirtir.
INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `po_id`, `status`, `branch_id`) VALUES
(101, '2025-06-22', 'PO-25B001', 1, 10), -- Depo 1'in (branch_id=10) siparişi
(102, '2025-06-23', 'PO-25B002', 1, 10), -- Depo 1'in (branch_id=10) siparişi
(201, '2025-06-22', 'PO-25I001', 1, 20); -- Depo 2'nin (branch_id=20) siparişi

-- 6. Sipariş Satırlarını ekle
INSERT INTO `satin_alma_siparis_fis_satir` (`id`, `siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(1, 101, 1, 50.00, 'BOX'),
(2, 101, 2, 100.00, 'BOX'),
(3, 102, 5, 250.00, 'BOX'),
(4, 201, 3, 300.00, 'BOX'),
(5, 201, 4, 150.00, 'BOX');