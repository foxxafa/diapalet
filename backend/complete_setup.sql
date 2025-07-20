-- COMPLETE DATABASE SETUP FOR DIAPALET
-- This file combines dump.sql, warehouses_update.sql, and test_data.sql

-- Set character encoding
SET character_set_client = utf8mb4;
SET character_set_connection = utf8mb4;
SET character_set_results = utf8mb4;
SET NAMES utf8mb4;

-- Disable foreign key checks temporarily
SET FOREIGN_KEY_CHECKS = 0;

-- ================================================
-- PART 1: DATABASE SCHEMA (from dump.sql)
-- ================================================

-- Table structure for table `employees`
DROP TABLE IF EXISTS `employees`;
CREATE TABLE `employees` (
  `id` int NOT NULL AUTO_INCREMENT,
  `first_name` varchar(100) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `last_name` varchar(100) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `branch_id` int DEFAULT NULL,
  `role` varchar(100) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `username` varchar(50) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `password` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `photo` varchar(150) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `warehouse_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  KEY `branch_id` (`branch_id`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_turkish_ci;

-- Table structure for table `goods_receipt_items`
DROP TABLE IF EXISTS `goods_receipt_items`;
CREATE TABLE `goods_receipt_items` (
  `id` int NOT NULL AUTO_INCREMENT,
  `receipt_id` int NOT NULL,
  `urun_id` int NOT NULL,
  `quantity_received` decimal(10,2) NOT NULL,
  `pallet_barcode` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `expiry_date` date DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Table structure for table `goods_receipts`
DROP TABLE IF EXISTS `goods_receipts`;
CREATE TABLE `goods_receipts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `invoice_number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `employee_id` int NOT NULL,
  `receipt_date` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Table structure for table `inventory_stock`
DROP TABLE IF EXISTS `inventory_stock`;
CREATE TABLE `inventory_stock` (
  `id` int NOT NULL AUTO_INCREMENT,
  `urun_id` int NOT NULL,
  `location_id` int DEFAULT NULL,
  `siparis_id` int DEFAULT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `pallet_barcode` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `stock_status` enum('receiving','available') CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL DEFAULT 'available' COMMENT 'receiving: Mal kabulde, available: Kullanilabilir',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `expiry_date` date DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stock_item` (`urun_id`,`location_id`,`pallet_barcode`,`stock_status`,`siparis_id`,`expiry_date`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Table structure for table `inventory_transfers`
DROP TABLE IF EXISTS `inventory_transfers`;
CREATE TABLE `inventory_transfers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `urun_id` int NOT NULL,
  `from_location_id` int DEFAULT NULL,
  `to_location_id` int NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `from_pallet_barcode` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `pallet_barcode` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `employee_id` int NOT NULL,
  `transfer_date` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Table structure for table `processed_requests`
DROP TABLE IF EXISTS `processed_requests`;
CREATE TABLE `processed_requests` (
  `idempotency_key` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL,
  `response_code` int NOT NULL,
  `response_body` json NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`idempotency_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Table structure for table `satin_alma_siparis_fis`
DROP TABLE IF EXISTS `satin_alma_siparis_fis`;
CREATE TABLE `satin_alma_siparis_fis` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tarih` date DEFAULT NULL,
  `notlar` text CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci,
  `user` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `gun` int DEFAULT '0',
  `branch_id` int DEFAULT NULL,
  `invoice` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `delivery` int DEFAULT NULL,
  `po_id` varchar(11) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `status` int DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=90 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_turkish_ci;

-- Table structure for table `satin_alma_siparis_fis_satir`
DROP TABLE IF EXISTS `satin_alma_siparis_fis_satir`;
CREATE TABLE `satin_alma_siparis_fis_satir` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `urun_id` int DEFAULT NULL,
  `miktar` decimal(10,2) DEFAULT NULL,
  `ort_son_30` int DEFAULT NULL,
  `ort_son_60` int DEFAULT NULL,
  `ort_son_90` int DEFAULT NULL,
  `tedarikci_id` int DEFAULT NULL,
  `tedarikci_fis_id` int DEFAULT NULL,
  `invoice` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `birim` varchar(10) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `layer` tinyint DEFAULT NULL,
  `notes` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `siparis_id` (`siparis_id`),
  CONSTRAINT `satin_alma_siparis_fis_satir_ibfk_1` FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2108 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_turkish_ci;

-- Table structure for table `shelfs`
DROP TABLE IF EXISTS `shelfs`;
CREATE TABLE `shelfs` (
  `id` int NOT NULL AUTO_INCREMENT,
  `warehouse_id` int DEFAULT NULL,
  `name` varchar(20) DEFAULT NULL,
  `code` varchar(20) DEFAULT NULL,
  `is_active` int DEFAULT '1',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Table structure for table `urunler`
DROP TABLE IF EXISTS `urunler`;
CREATE TABLE `urunler` (
  `UrunId` int NOT NULL AUTO_INCREMENT,
  `StokKodu` varchar(50) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `UrunAdi` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `AdetFiyati` decimal(10,2) DEFAULT NULL,
  `KutuFiyati` decimal(10,2) DEFAULT NULL,
  `Pm1` decimal(10,2) DEFAULT NULL,
  `Pm2` decimal(10,2) DEFAULT NULL,
  `Pm3` decimal(10,2) DEFAULT NULL,
  `Vat` decimal(5,2) DEFAULT NULL,
  `Birim1` varchar(50) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `BirimKey1` int DEFAULT NULL,
  `Birim2` varchar(50) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `BirimKey2` int DEFAULT NULL,
  `Birim3` varchar(45) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `BirimKey3` varchar(50) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `aktif` int DEFAULT '1',
  `marka_id` int DEFAULT NULL,
  `kategori_id` int DEFAULT NULL,
  `grup_id` int DEFAULT NULL,
  `mcat` varchar(120) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `cat` varchar(120) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `subcat` varchar(120) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `qty` int DEFAULT NULL,
  `size` varchar(15) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `unitkg` decimal(10,2) DEFAULT NULL,
  `palletqty` int DEFAULT NULL,
  `HSCode` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `rafkoridor` varchar(15) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `rafno` int DEFAULT NULL,
  `rafkat` varchar(15) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `rafomru` int DEFAULT NULL,
  `imsrc` varchar(155) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `Barcode1` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode2` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode3` varchar(255) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `Barcode4` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode5` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode6` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode7` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode8` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode9` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode10` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode11` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode12` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode13` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode14` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `Barcode15` varchar(45) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `PackFiyati` decimal(10,2) DEFAULT NULL,
  `fiyat4` int DEFAULT NULL,
  `fiyat5` int DEFAULT NULL,
  `fiyat6` int DEFAULT NULL,
  `fiyat7` int DEFAULT NULL,
  `fiyat8` int DEFAULT NULL,
  `fiyat9` int DEFAULT NULL,
  `fiyat10` int DEFAULT NULL,
  `Palet` int DEFAULT '0',
  `Layer` int DEFAULT '0',
  `_key` int DEFAULT NULL,
  PRIMARY KEY (`UrunId`),
  UNIQUE KEY `StokKodu_UNIQUE` (`StokKodu`)
) ENGINE=InnoDB AUTO_INCREMENT=210814 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_turkish_ci;

-- Table structure for table `warehouses`
DROP TABLE IF EXISTS `warehouses`;
CREATE TABLE `warehouses` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `post_code` varchar(10) DEFAULT NULL,
  `ap` char(1) DEFAULT NULL,
  `branch_id` int DEFAULT NULL,
  `warehouse_code` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Table structure for table `branches`
DROP TABLE IF EXISTS `branches`;
CREATE TABLE `branches` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_turkish_ci NOT NULL,
  `branch_code` varchar(15) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `post_code` varchar(10) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `is_active` int DEFAULT '1',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `address` varchar(255) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `description` text COLLATE utf8mb4_turkish_ci,
  `latitude` decimal(10,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `parent_code` varchar(10) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `ap` char(1) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `_key` varchar(10) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `branch_code` (`branch_code`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- Table structure for table `wms_putaway_status`
DROP TABLE IF EXISTS `wms_putaway_status`;
CREATE TABLE `wms_putaway_status` (
  `id` int NOT NULL AUTO_INCREMENT,
  `satinalmasiparisfissatir_id` int DEFAULT NULL,
  `putaway_quantity` decimal(10,2) DEFAULT '0.00',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_wms_putaway_status_line_id` (`satinalmasiparisfissatir_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ================================================
-- PART 2: WAREHOUSE UPDATES (from warehouses_update.sql)
-- ================================================

-- Add dia_id column to warehouses table
ALTER TABLE `warehouses` ADD COLUMN `dia_id` INT NULL AFTER `warehouse_code`;

-- Add dia_key column to shelfs table
ALTER TABLE `shelfs` ADD COLUMN `dia_key` VARCHAR(20) NULL AFTER `code`;

-- ================================================
-- PART 3: TEST DATA (from test_data.sql)
-- ================================================

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
(2, 'test', 'test', 'test', '123', 1, 1),
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

-- Re-enable foreign key checks
SET FOREIGN_KEY_CHECKS = 1; 