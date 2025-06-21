-- VTYS Mobil Depo Yönetim Sistemi için Veritabanı Şeması
-- UYGULAMA MANTIĞI İLE TAM UYUMLU, GÜNCELLENMİŞ VERSİYON

-- -----------------------------------------------------
-- Veritabanını kullan
-- -----------------------------------------------------
SET NAMES utf8mb4 COLLATE utf8mb4_turkish_ci;
USE diapalet_test;

-- -----------------------------------------------------
-- BÖLÜM 1: MEVCUT TABLOLARI GÜVENLİ BİR ŞEKİLDE KALDIRMA
-- Not: Bu bölüm, şemayı sıfırdan kurarken hataları önlemek içindir.
-- -----------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `inventory_transfers`;
DROP TABLE IF EXISTS `inventory_stock`;
DROP TABLE IF EXISTS `goods_receipt_items`;
DROP TABLE IF EXISTS `goods_receipts`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis_satir`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis`;
DROP TABLE IF EXISTS `urunler`;
DROP TABLE IF EXISTS `employees`;
DROP TABLE IF EXISTS `warehouses_shelfs`;
DROP TABLE IF EXISTS `warehouses`;
SET FOREIGN_KEY_CHECKS = 1;


-- -----------------------------------------------------
-- BÖLÜM 2: TABLOLARI OLUŞTURMA
-- -----------------------------------------------------

-- Tablo `warehouses` (Depolar)
CREATE TABLE IF NOT EXISTS `warehouses` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `warehouse_code` VARCHAR(15) NOT NULL UNIQUE,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Tablo `warehouses_shelfs` (Depo Lokasyonları/Rafları)
-- NOT: PHP kodunuz bu tabloyu genel olarak "location" olarak kullanır.
CREATE TABLE IF NOT EXISTS `warehouses_shelfs` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `warehouse_id` INT NOT NULL COMMENT 'Rafın ait olduğu depo',
  `name` VARCHAR(255) NOT NULL COMMENT 'Rafın tam adı (Örn: Mal Kabul Alanı)',
  `code` VARCHAR(20) NOT NULL COMMENT 'Depo içindeki benzersiz raf kodu (Örn: A-101, MK-01)',
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_warehouse_shelf` (`warehouse_id`, `code`),
  FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;


-- Tablo `employees` (Çalışanlar)
CREATE TABLE IF NOT EXISTS `employees` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `first_name` VARCHAR(100) NOT NULL,
  `last_name` VARCHAR(100) NOT NULL,
  `username` VARCHAR(50) NOT NULL UNIQUE,
  `password` VARCHAR(255) NOT NULL COMMENT 'Her zaman hashlenmiş olarak saklanmalıdır.',
  `warehouse_id` INT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Tablo `urunler` (Ürün Ana Verisi)
CREATE TABLE IF NOT EXISTS `urunler` (
  `UrunId` INT NOT NULL AUTO_INCREMENT,
  `StokKodu` VARCHAR(50) NOT NULL UNIQUE,
  `UrunAdi` VARCHAR(255) NOT NULL,
  `Barcode1` VARCHAR(255) NULL,
  `aktif` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`UrunId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Tablo: `satin_alma_siparis_fis`
CREATE TABLE IF NOT EXISTS `satin_alma_siparis_fis` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tarih` date DEFAULT NULL,
  `notlar` text COLLATE utf8mb4_turkish_ci,
  `user` varchar(255) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `gun` int DEFAULT '0',
  `lokasyon_id` int DEFAULT NULL COMMENT 'Siparişin geleceği depo (warehouses.id).',
  `invoice` varchar(45) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `delivery` int DEFAULT NULL,
  `po_id` varchar(20) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `status` int DEFAULT '0' COMMENT '0:Beklemede, 1:Onaylandı, 2:Kısmi Kabul, 3:Tamamlandı',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_satin_alma_lokasyon_idx` (`lokasyon_id`),
  CONSTRAINT `fk_satin_alma_warehouse` FOREIGN KEY (`lokasyon_id`) REFERENCES `warehouses` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Tablo: `satin_alma_siparis_fis_satir`
CREATE TABLE IF NOT EXISTS `satin_alma_siparis_fis_satir` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `urun_id` int DEFAULT NULL,
  `miktar` decimal(10,2) DEFAULT NULL,
  `birim` varchar(10) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `notes` varchar(255) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `status` int DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `siparis_id` (`siparis_id`),
  KEY `fk_satin_alma_urun_idx` (`urun_id`),
  CONSTRAINT `satin_alma_siparis_fis_satir_ibfk_1` FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_satin_alma_urun` FOREIGN KEY (`urun_id`) REFERENCES `urunler` (`UrunId`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Tablo `goods_receipts` (Mal Kabul Fişleri)
CREATE TABLE IF NOT EXISTS `goods_receipts` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `siparis_id` INT NULL COMMENT 'İlişkili satınalma siparişi. Serbest kabulde NULL olabilir.',
  `invoice_number` VARCHAR(255) NULL,
  `employee_id` INT NOT NULL,
  `receipt_date` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis`(`id`),
  FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Tablo `goods_receipt_items` (Mal Kabul Kalemleri)
CREATE TABLE IF NOT EXISTS `goods_receipt_items` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `receipt_id` INT NOT NULL,
  `urun_id` INT NOT NULL,
  `quantity_received` DECIMAL(10, 2) NOT NULL,
  `pallet_barcode` VARCHAR(50) NULL,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`receipt_id`) REFERENCES `goods_receipts`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`urun_id`) REFERENCES `urunler`(`UrunId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Stok Envanter Tablosu
CREATE TABLE IF NOT EXISTS `inventory_stock` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `urun_id` INT NOT NULL,
  `location_id` INT NOT NULL COMMENT 'Stokun bulunduğu lokasyon (warehouses_shelfs.id)',
  `quantity` DECIMAL(10, 2) NOT NULL,
  `pallet_barcode` VARCHAR(50) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stock_item` (`urun_id`, `location_id`, `pallet_barcode`),
  FOREIGN KEY (`urun_id`) REFERENCES `urunler`(`UrunId`) ON DELETE CASCADE,
  FOREIGN KEY (`location_id`) REFERENCES `warehouses_shelfs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Envanter Transferleri Tablosu (GÜNCELLENDİ)
CREATE TABLE IF NOT EXISTS `inventory_transfers` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `urun_id` INT NOT NULL,
  `from_location_id` INT NULL,
  `to_location_id` INT NOT NULL,
  `quantity` DECIMAL(10, 2) NOT NULL,
  `from_pallet_barcode` VARCHAR(50) NULL COMMENT 'Transferin yapıldığı KAYNAK palet barkodu.',
  `pallet_barcode` VARCHAR(50) NULL COMMENT 'Transferin vardığı HEDEF palet barkodu (tam palet transferinde).',
  `employee_id` INT NOT NULL,
  `transfer_date` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`urun_id`) REFERENCES `urunler`(`UrunId`),
  FOREIGN KEY (`from_location_id`) REFERENCES `warehouses_shelfs`(`id`),
  FOREIGN KEY (`to_location_id`) REFERENCES `warehouses_shelfs`(`id`),
  FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;


-- -----------------------------------------------------
-- BÖLÜM 3: ÖRNEK VERİ EKLEME
-- -----------------------------------------------------

-- Örnek Depolar
INSERT INTO `warehouses` (`id`, `name`, `warehouse_code`, `is_active`) VALUES
(1, 'Bursa Merkez Depo', 'BURSA-MERKEZ', 1),
(2, 'İstanbul Anadolu Deposu', 'IST-ANADOLU', 1);

-- Her depo için varsayılan bir Mal Kabul ve Stok Rafı oluşturalım.
-- PHP kodundaki `$malKabulLocationId = 1` bu ID'ye karşılık gelmelidir.
INSERT INTO `warehouses_shelfs` (`id`, `warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, 1, 'Bursa Mal Kabul Alanı', 'BUR-MK-01', 1),
(2, 1, 'Bursa Stok Rafı A-01', 'BUR-A-01', 1),
(3, 2, 'İstanbul Mal Kabul Alanı', 'IST-MK-01', 1),
(4, 2, 'İstanbul Stok Rafı A-01', 'IST-A-01', 1);

-- Örnek Çalışanlar
INSERT INTO `employees` (`id`, `first_name`, `last_name`, `username`, `password`, `warehouse_id`, `is_active`) VALUES
(1, 'Yusuf', 'KAHRAMAN', 'foxxafa', '123', 1, 1),
(2, 'Mehmet', 'Kaya', 'mehmet', '123', 1, 1),
(3, 'Zeynep', 'Çelik', 'zeynep.celik', '123', 2, 1);

-- Örnek Ürünler
INSERT INTO `urunler` (`UrunId`, `StokKodu`, `UrunAdi`, `Barcode1`, `aktif`) VALUES
(1, 'KOL-001', 'Kola 2.5 LT', '8690001123456', 1),
(2, 'SUT-001', 'Süt 1 LT', '8690002123457', 1),
(3, 'SU-001', 'Su 5 LT', '8690003123458', 1);

-- Örnek Satın Alma Siparişleri
INSERT INTO `satin_alma_siparis_fis` (`id`, `tarih`, `user`, `lokasyon_id`, `po_id`, `status`) VALUES
(101, '2025-06-17', 'sistem', 1, 'PO-25B001', 1), -- Bursa Deposu, Onaylandı
(102, '2025-06-18', 'sistem', 1, 'PO-25B002', 0), -- Bursa Deposu, Beklemede (Görünmemeli)
(201, '2025-06-17', 'sistem', 2, 'PO-25I001', 1); -- İstanbul Deposu, Onaylandı

-- Örnek Sipariş Satırları
INSERT INTO `satin_alma_siparis_fis_satir` (`siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(101, 1, 50.00, 'KUTU'), (101, 2, 100.00, 'KUTU'),
(102, 2, 200.00, 'KUTU'),
(201, 3, 300.00, 'ADET');