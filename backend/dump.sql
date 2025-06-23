-- VTYS Mobil Depo Yönetim Sistemi için Veritabanı Şeması
-- v2.0 - İŞ AKIŞINA UYGUN GÜNCELLENMİŞ VE ZENGİNLEŞTİRİLMİŞ ÖRNEK VERİLER

SET NAMES utf8mb4 COLLATE utf8mb4_turkish_ci;

-- Veritabanı adını kendi yapınıza göre değiştirin, örn: USE diapalet_test;
-- USE your_database_name;

-- Tabloları yeniden oluşturmadan önce mevcut olanları güvenli bir şekilde kaldıralım.
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `inventory_transfers`, `inventory_stock`, `goods_receipt_items`, `goods_receipts`, `satin_alma_siparis_fis_satir`, `satin_alma_siparis_fis`, `urunler`, `employees`, `warehouses_shelfs`, `warehouses`;
SET FOREIGN_KEY_CHECKS = 1;

-- Tablo Yapıları

CREATE TABLE IF NOT EXISTS `warehouses` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `warehouse_code` VARCHAR(15) NOT NULL UNIQUE,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `warehouses_shelfs` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `warehouse_id` INT NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `code` VARCHAR(20) NOT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_warehouse_shelf` (`warehouse_id`, `code`),
  FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `employees` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `first_name` VARCHAR(100) NOT NULL,
  `last_name` VARCHAR(100) NOT NULL,
  `username` VARCHAR(50) NOT NULL UNIQUE,
  `password` VARCHAR(255) NOT NULL,
  `warehouse_id` INT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `urunler` (
  `UrunId` INT NOT NULL AUTO_INCREMENT,
  `StokKodu` VARCHAR(50) NOT NULL UNIQUE,
  `UrunAdi` VARCHAR(255) NOT NULL,
  `Barcode1` VARCHAR(255) NULL,
  `aktif` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`UrunId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `satin_alma_siparis_fis` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tarih` date DEFAULT NULL,
  `notlar` text,
  `user` varchar(255) DEFAULT NULL,
  `gun` int DEFAULT '0',
  `lokasyon_id` int DEFAULT NULL,
  `invoice` varchar(45) DEFAULT NULL,
  `delivery` int DEFAULT NULL,
  `po_id` varchar(20) DEFAULT NULL,
  `status` int DEFAULT '0' COMMENT '0:Beklemede, 1:Onaylandi (Mal Kabul Bekliyor), 2:Kismi Kabul (Islemde), 3:Tamamlandi (Mal Kabul Bitti)',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_satin_alma_lokasyon_idx` (`lokasyon_id`),
  CONSTRAINT `fk_satin_alma_warehouse` FOREIGN KEY (`lokasyon_id`) REFERENCES `warehouses` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=202;

CREATE TABLE IF NOT EXISTS `satin_alma_siparis_fis_satir` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `urun_id` int DEFAULT NULL,
  `miktar` decimal(10,2) DEFAULT NULL,
  `birim` varchar(10) DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL,
  `status` int DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `siparis_id` (`siparis_id`),
  KEY `fk_satin_alma_urun_idx` (`urun_id`),
  CONSTRAINT `satin_alma_siparis_fis_satir_ibfk_1` FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_satin_alma_urun` FOREIGN KEY (`urun_id`) REFERENCES `urunler` (`UrunId`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `goods_receipts` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `siparis_id` INT NULL,
  `invoice_number` VARCHAR(255) NULL,
  `employee_id` INT NOT NULL,
  `receipt_date` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis`(`id`),
  FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `goods_receipt_items` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `receipt_id` INT NOT NULL,
  `urun_id` INT NOT NULL,
  `quantity_received` DECIMAL(10, 2) NOT NULL,
  `pallet_barcode` VARCHAR(50) NULL,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`receipt_id`) REFERENCES `goods_receipts`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`urun_id`) REFERENCES `urunler`(`UrunId`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `inventory_stock` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `urun_id` INT NOT NULL,
  `location_id` INT NOT NULL,
  `quantity` DECIMAL(10, 2) NOT NULL,
  `pallet_barcode` VARCHAR(50) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stock_item` (`urun_id`, `location_id`, `pallet_barcode`),
  FOREIGN KEY (`urun_id`) REFERENCES `urunler`(`UrunId`) ON DELETE CASCADE,
  FOREIGN KEY (`location_id`) REFERENCES `warehouses_shelfs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `inventory_transfers` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `urun_id` INT NOT NULL,
  `from_location_id` INT NULL,
  `to_location_id` INT NOT NULL,
  `quantity` DECIMAL(10, 2) NOT NULL,
  `from_pallet_barcode` VARCHAR(50) NULL,
  `pallet_barcode` VARCHAR(50) NULL,
  `employee_id` INT NOT NULL,
  `transfer_date` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`urun_id`) REFERENCES `urunler`(`UrunId`),
  FOREIGN KEY (`from_location_id`) REFERENCES `warehouses_shelfs`(`id`),
  FOREIGN KEY (`to_location_id`) REFERENCES `warehouses_shelfs`(`id`),
  FOREIGN KEY (`employee_id`) REFERENCES `employees`(`id`)
) ENGINE=InnoDB;

-- Örnek Veriler

INSERT INTO `warehouses` (`id`, `name`, `warehouse_code`, `is_active`) VALUES
(1, 'Bursa Merkez Depo', 'BURSA-MERKEZ', 1),
(2, 'Istanbul Anadolu Deposu', 'IST-ANADOLU', 1);

INSERT INTO `warehouses_shelfs` (`id`, `warehouse_id`, `name`, `code`, `is_active`) VALUES
(1, 1, 'Bursa Mal Kabul Alani', '000', 1),
(2, 1, 'Bursa Stok Rafi 10A21', '10A21', 1),
(3, 1, 'Bursa Stok Rafi 10A22', '10A22', 1),
(4, 1, 'Bursa Stok Rafi 5C3', '5C3', 1),
(5, 2, 'Istanbul Mal Kabul Alani', '000', 1),
(6, 2, 'Istanbul Stok Rafi 20C01', '20C01', 1),
(7, 2, 'Istanbul Stok Rafi 21D05', '21D05', 1);

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

INSERT INTO `satin_alma_siparis_fis_satir` (`siparis_id`, `urun_id`, `miktar`, `birim`) VALUES
(101, 1, 50.00, 'KUTU'),
(101, 2, 100.00, 'KUTU'),
(102, 5, 250.00, 'KUTU'),
(201, 3, 300.00, 'ADET'),
(201, 4, 150.00, 'KUTU');