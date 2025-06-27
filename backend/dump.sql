-- VTYS Mobil Depo Yönetim Sistemi için Veritabanı Şeması
-- v5.0 - stock_status ve putaway_quantity alanları eklendi.

SET NAMES utf8mb4 COLLATE utf8mb4_turkish_ci;
SET FOREIGN_KEY_CHECKS = 0;

-- Önce mevcut tabloları sil
DROP TABLE IF EXISTS `inventory_transfers`, `inventory_stock`, `goods_receipt_items`, `goods_receipts`, `satin_alma_siparis_fis_satir`, `satin_alma_siparis_fis`, `urunler`, `employees`, `warehouses_shelfs`, `warehouses`;

SET FOREIGN_KEY_CHECKS = 1;

-- =================================================================
-- Tablo Yapıları
-- =================================================================

CREATE TABLE IF NOT EXISTS `processed_terminal_operations` (
  `operation_id` INT NOT NULL,
  `processed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`operation_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `warehouses` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `dia_id` INT NULL UNIQUE,
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
  `status` int DEFAULT '0' COMMENT '0:Beklemede, 1:Onaylandi, 2:Kismi Kabul, 3:Tamamlandi',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_satin_alma_lokasyon_idx` (`lokasyon_id`),
  CONSTRAINT `fk_satin_alma_warehouse` FOREIGN KEY (`lokasyon_id`) REFERENCES `warehouses` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `satin_alma_siparis_fis_satir` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `urun_id` int DEFAULT NULL,
  `miktar` decimal(10,2) DEFAULT NULL,
  `putaway_quantity` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Rafa yerleştirilen miktar',
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
  `stock_status` enum('receiving','available') NOT NULL DEFAULT 'available' COMMENT 'receiving: Mal kabulde, available: Kullanilabilir',
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stock_item` (`urun_id`, `location_id`, `pallet_barcode`, `stock_status`),
  KEY `idx_stock_status` (`stock_status`),
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