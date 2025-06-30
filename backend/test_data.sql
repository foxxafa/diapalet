-- Bu dosya, temel veritabanı yapısı ve Dia senkronizasyonu tamamlandıktan sonra çalıştırılacaktır.
-- Test verilerini, artık var olan depolara atar.

USE `diapalet_test`; -- Veritabanı adını doğrulayın

-- 1. Depoları ekle
-- DIA'dan gelmesini beklemek yerine manuel ekliyoruz.
INSERT INTO `warehouses` (`id`, `dia_id`, `name`, `warehouse_code`) VALUES
(1, 3882, 'SOUTHALL - SOUTHALL', 'DEPO-3882'),
(2, 5322839, 'SOUTHALL - SOUTHALL-2', 'DEPO-5322839');

-- 2. Rafları ekle (Dia'dan gelenler + bizim özel Mal Kabul raflarımız)
-- Önce her depo için Mal Kabul Rafını ekleyelim.
INSERT INTO `warehouses_shelfs` (`warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, 'Mal Kabul Alanı', 'MAL_KABUL', 1),
(2, 'Mal Kabul Alanı', 'MAL_KABUL', 1);

-- Şimdi test için diğer rafları ekleyelim (ekran görüntüsündeki gibi)
INSERT INTO `warehouses_shelfs` (`warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, 'aaa', '9D15', 1),
(1, '42B01', '42B01', 1),
(1, '42A01', '42A01', 1),
(1, 'F62', 'F62', 1),
(1, '10B03', '10B03', 1),
(1, '10C02', '10C02', 1),
(1, '10C03', '10C03', 1);
-- (İsterseniz Depo 2 için de raf ekleyebilirsiniz)


-- 3. Çalışanları, ürünleri ve siparişleri ekle (mevcut verileriniz iyi görünüyor)
INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `warehouse_id`) VALUES
(1, 'Yusuf', 'KAHRAMAN', 'foxxafa', '123', 1),
(2, 'Mehmet', 'Kaya', 'mehmet', '123', 1),
(3, 'Zeynep', 'Celik', 'zeynep.celik', 'zeynep123', 2);

INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Barcode1`) VALUES
(1, 'KOL-001', 'Kola 2.5 LT', '8690001123456'),
(2, 'SUT-001', 'Sut 1 LT', '8690002123457'),
(3, 'SU-001', 'Su 5 LT', '8690003123458'),
(4, 'CKL-007', 'Cikolata 100g', '8690004123459'),
(5, 'MKN-001', 'Makarna 500g', '8690005123450');

-- lokasyon_id'nin doğru warehouse.id'ye işaret ettiğinden emin olun
INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `po_id`, `status`, `lokasyon_id`) VALUES
(101, '2025-06-22', 'PO-25B001', 1, 1), -- Depo 1'in siparişi
(102, '2025-06-23', 'PO-25B002', 1, 1), -- Depo 1'in siparişi
(201, '2025-06-22', 'PO-25I001', 1, 2); -- Depo 2'nin siparişi

INSERT INTO `satin_alma_siparis_fis_satir` (`id`, `siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(1, 101, 1, 50.00, 'BOX'),
(2, 101, 2, 100.00, 'BOX'),
(3, 102, 5, 250.00, 'BOX'),
(4, 201, 3, 300.00, 'BOX'),
(5, 201, 4, 150.00, 'BOX');
