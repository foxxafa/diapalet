-- Bu dosya, temel veritabanı yapısı ve Dia senkronizasyonu tamamlandıktan sonra çalıştırılacaktır.
-- Test verilerini, artık var olan depolara atar.

USE `diapalet_test`; -- Lütfen veritabanı adının doğru olduğunu kontrol et!

INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `warehouse_id`, `is_active`) VALUES
(1, 'Yusuf', 'KAHRAMAN', 'foxxafa', '123', 1, 1),
(2, 'Mehmet', 'Kaya', 'mehmet', '123', 1, 1),
(3, 'Zeynep', 'Celik', 'zeynep.celik', '123', 2, 1);

INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Barcode1`, `aktif`) VALUES
(1, 'KOL-001', 'Kola 2.5 LT', '8690001123456', 1),
(2, 'SUT-001', 'Sut 1 LT', '8690002123457', 1),
(3, 'SU-001', 'Su 5 LT', '8690003123458', 1),
(4, 'CKL-007', 'Cikolata 100g', '8690004123459', 1),
(5, 'MKN-001', 'Makarna 500g', '8690005123450', 1);

INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `user`, `lokasyon_id`, `po_id`, `status`) VALUES
(101, '2025-06-22', 'sistem', 1, 'PO-25B001', 1),
(102, '2025-06-23', 'sistem', 1, 'PO-25B002', 1),
(201, '2025-06-22', 'sistem', 2, 'PO-25I001', 0);

INSERT INTO `satin_alma_siparis_fis_satir` (`id`, `siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(1, 101, 1, 50.00, 'BOX'),
(2, 101, 2, 100.00, 'BOX'),
(3, 102, 5, 250.00, 'BOX'),
(4, 201, 3, 300.00, 'BOX'),
(5, 201, 4, 150.00, 'BOX');
