-- Diapallet WMS için Gerekli Minimum Veritabanı Şeması
-- Bu script, sadece WMS uygulamasının çalışması için gereken tabloları içerir.
-- Mevcut 'enzo' tablolarının yapısını DEĞİŞTİRMEZ.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS=0;

-- ÖNCE MEVCUT TABLOLARI TEMİZLE (LOKAL KURULUM İÇİN)
DROP TABLE IF EXISTS `wms_putaway_status`, `inventory_transfers`, `inventory_stock`, `goods_receipt_items`, `goods_receipts`, `warehouses_shelfs`, `warehouses`, `processed_requests`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis_satir`, `satin_alma_siparis_fis`, `urunler`, `employees`;

-- =================================================================
-- MEVCUT SİSTEMDEN GELEN ANA TABLOLAR (YAPI OLARAK OLUŞTURULUYOR)
-- =================================================================

CREATE TABLE `employees` (
  `id` int NOT NULL AUTO_INCREMENT,
  `first_name` varchar(100) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `last_name` varchar(100) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `username` varchar(50) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `password` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `warehouse_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB;

CREATE TABLE `urunler` (
  `UrunId` int NOT NULL AUTO_INCREMENT,
  `StokKodu` varchar(50) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `UrunAdi` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `aktif` int DEFAULT '1',
  `Barcode1` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  PRIMARY KEY (`UrunId`),
  UNIQUE KEY `StokKodu_UNIQUE` (`StokKodu`),
  KEY `idx_urunler_barcode1` (`Barcode1`),
  KEY `idx_urunler_adi` (`UrunAdi`)
) ENGINE=InnoDB;

CREATE TABLE `satin_alma_siparis_fis` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tarih` date DEFAULT NULL,
  `notlar` text CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci,
  `po_id` varchar(11) CHARACTER SET utf8mb3 COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  `status` int DEFAULT '0' COMMENT '0:Beklemede, 1:Onaylandi, 2:Islemde, 3:Manuel Kapatildi, 4:Oto. Tamamlandi',
  `lokasyon_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_siparis_status` (`status`),
  KEY `idx_siparis_lokasyon` (`lokasyon_id`)
) ENGINE=InnoDB;

CREATE TABLE `satin_alma_siparis_fis_satir` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `urun_id` int DEFAULT NULL,
  `miktar` decimal(10,2) DEFAULT NULL,
  `birim` varchar(10) COLLATE utf8mb3_turkish_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `siparis_id` (`siparis_id`),
  CONSTRAINT `satin_alma_siparis_fis_satir_ibfk_1` FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;


-- =================================================================
-- WMS (DEPO YÖNETİM SİSTEMİ) İÇİN GEREKLİ YENİ TABLOLAR
-- =================================================================

CREATE TABLE `warehouses` (
  `id` int NOT NULL AUTO_INCREMENT,
  `dia_id` int DEFAULT NULL,  -- YENİDEN EKLENDİ
  `name` varchar(255) NOT NULL,
  `warehouse_code` varchar(15) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `dia_id_UNIQUE` (`dia_id`), -- YENİDEN EKLENDİ
  UNIQUE KEY `warehouse_code_UNIQUE` (`warehouse_code`)
) ENGINE=InnoDB;

CREATE TABLE `warehouses_shelfs` (
  `id` int NOT NULL AUTO_INCREMENT,
  `warehouse_id` int NOT NULL,
  `name` varchar(255) NOT NULL,
  `code` varchar(20) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_warehouse_shelf` (`warehouse_id`,`code`),
  CONSTRAINT `fk_wms_shelf_warehouse` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `goods_receipts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `siparis_id` int DEFAULT NULL,
  `invoice_number` varchar(255) DEFAULT NULL,
  `employee_id` int NOT NULL,
  `receipt_date` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_receipt_siparis` (`siparis_id`),
  CONSTRAINT `fk_wms_receipt_order` FOREIGN KEY (`siparis_id`) REFERENCES `satin_alma_siparis_fis` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_wms_receipt_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `goods_receipt_items` (
  `id` int NOT NULL AUTO_INCREMENT,
  `receipt_id` int NOT NULL,
  `urun_id` int NOT NULL,
  `quantity_received` decimal(10,2) NOT NULL,
  `pallet_barcode` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_wms_receiptitem_receipt` FOREIGN KEY (`receipt_id`) REFERENCES `goods_receipts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_wms_receiptitem_product` FOREIGN KEY (`urun_id`) REFERENCES `urunler` (`UrunId`)
) ENGINE=InnoDB;

CREATE TABLE `inventory_stock` (
  `id` int NOT NULL AUTO_INCREMENT,
  `urun_id` int NOT NULL,
  `location_id` int NOT NULL,
  `siparis_id` int DEFAULT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `pallet_barcode` varchar(50) COLLATE utf8mb4_turkish_ci DEFAULT NULL,
  `stock_status` enum('receiving','available') COLLATE utf8mb4_turkish_ci NOT NULL DEFAULT 'available' COMMENT 'receiving: Mal kabulde, available: Kullanilabilir',
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_stock_item` (`urun_id`,`location_id`,`pallet_barcode`,`stock_status`,`siparis_id`),
  KEY `idx_stock_location` (`location_id`),
  KEY `idx_stock_pallet` (`pallet_barcode`),
  CONSTRAINT `fk_wms_stock_product` FOREIGN KEY (`urun_id`) REFERENCES `urunler` (`UrunId`) ON DELETE CASCADE,
  CONSTRAINT `fk_wms_stock_location` FOREIGN KEY (`location_id`) REFERENCES `warehouses_shelfs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `inventory_transfers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `urun_id` int NOT NULL,
  `from_location_id` int DEFAULT NULL,
  `to_location_id` int NOT NULL,
  `quantity` decimal(10,2) NOT NULL,
  `from_pallet_barcode` varchar(50) DEFAULT NULL,
  `pallet_barcode` varchar(50) DEFAULT NULL,
  `employee_id` int NOT NULL,
  `transfer_date` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_transfer_from_location` (`from_location_id`),
  KEY `idx_transfer_to_location` (`to_location_id`),
  KEY `idx_transfer_employee` (`employee_id`),
  CONSTRAINT `fk_wms_transfer_product` FOREIGN KEY (`urun_id`) REFERENCES `urunler` (`UrunId`),
  CONSTRAINT `fk_wms_transfer_from` FOREIGN KEY (`from_location_id`) REFERENCES `warehouses_shelfs` (`id`),
  CONSTRAINT `fk_wms_transfer_to` FOREIGN KEY (`to_location_id`) REFERENCES `warehouses_shelfs` (`id`),
  CONSTRAINT `fk_wms_transfer_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`)
) ENGINE=InnoDB;

-- YENİ YARDIMCI TABLO: Bu tablo, mevcut şemayı bozmadan rafa yerleştirme takibi yapar.
CREATE TABLE `wms_putaway_status` (
  `id` int NOT NULL AUTO_INCREMENT,
  `satin_alma_siparis_fis_satir_id` int NOT NULL COMMENT 'orijinal sipariş satırının IDsi',
  `putaway_quantity` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT 'rafa yerleştirilen miktar',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_line_item` (`satin_alma_siparis_fis_satir_id`),
  CONSTRAINT `fk_putaway_order_line` FOREIGN KEY (`satin_alma_siparis_fis_satir_id`) REFERENCES `satin_alma_siparis_fis_satir` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- İDEMPOTENCY SUPPORT: İsteklerin tekrar işlenmesini önlemek için
CREATE TABLE `processed_requests` (
  `idempotency_key` VARCHAR(36) NOT NULL,
  `response_code` INT NOT NULL,
  `response_body` JSON NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`idempotency_key`)
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS=1;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
