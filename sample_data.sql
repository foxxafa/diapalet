-- Örnek veritabanı kayıtları
-- Bu betik, test için temel verileri oluşturur.

-- çalışan ekle
INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `role`, `is_active`) VALUES
(1, 'Ahmet', 'Yılmaz', 'ahmet', 'password123', 'Depo Sorumlusu', 1),
(2, 'Ayşe', 'Kaya', 'ayse', 'password456', 'Satın Alma', 1);

-- yeni ürün ekle
INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Birim1`, `aktif`) VALUES
(102, 'PEPSI-1L', 'Pepsi 1L Kutu', 'KUTU', 1);

-- yeni satın alma siparişi
INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `notlar`, `user`, `po_id`, `status`) VALUES
(5002, '2025-06-10', 'Haftalık içecek siparişi', 'merkez_depo', 'PO-2025-002', 0);

-- yeni siparişin kalemleri
INSERT INTO `satin_alma_siparis_fis_satir` (`siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(5002, 101, 100.00, 'KUTU'),
(5002, 102, 75.00, 'KUTU'); 