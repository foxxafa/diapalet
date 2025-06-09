-- Additional tables for offline synchronization support
-- These can be added to the existing rowhub database

-- -----------------------------------------------------
-- Tablo: `pending_operations`
-- Stores all pending operations from mobile devices
-- -----------------------------------------------------
DROP TABLE IF EXISTS `pending_operations`;
CREATE TABLE IF NOT EXISTS `pending_operations` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL,
  `operation_type` ENUM('goods_receipt','pallet_transfer','box_transfer') CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL,
  `operation_data` JSON NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processed_at` TIMESTAMP NULL DEFAULT NULL,
  `status` ENUM('pending','processing','completed','failed') DEFAULT 'pending',
  `error_message` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NULL,
  `sync_attempts` INT DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_device_status` (`device_id`, `status`),
  KEY `idx_operation_type` (`operation_type`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- -----------------------------------------------------
-- Tablo: `sync_log`
-- Tracks synchronization history
-- -----------------------------------------------------
DROP TABLE IF EXISTS `sync_log`;
CREATE TABLE IF NOT EXISTS `sync_log` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL,
  `sync_type` ENUM('full','incremental','manual') DEFAULT 'incremental',
  `operations_count` INT DEFAULT 0,
  `success_count` INT DEFAULT 0,
  `failed_count` INT DEFAULT 0,
  `sync_started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sync_completed_at` TIMESTAMP NULL DEFAULT NULL,
  `status` ENUM('running','completed','failed') DEFAULT 'running',
  `error_details` JSON NULL,
  PRIMARY KEY (`id`),
  KEY `idx_device_sync_time` (`device_id`, `sync_started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci;

-- -----------------------------------------------------
-- Tablo: `mobile_devices`
-- Track registered mobile devices
-- -----------------------------------------------------
DROP TABLE IF EXISTS `mobile_devices`;
CREATE TABLE IF NOT EXISTS `mobile_devices` (
  `device_id` VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL,
  `device_name` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NULL,
  `platform` VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NOT NULL,
  `app_version` VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci NULL,
  `last_sync_at` TIMESTAMP NULL DEFAULT NULL,
  `registered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_active` TINYINT(1) DEFAULT 1,
  PRIMARY KEY (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_turkish_ci; 