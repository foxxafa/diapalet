-- MySQL Import Script for Railway
-- Bu dosyayı Railway MySQL konsolunda çalıştırın

-- Mevcut veritabanını temizle (dikkatli!)
-- DROP DATABASE IF EXISTS railway;
-- CREATE DATABASE railway CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci;
-- USE railway;

-- Veya mevcut tabloları temizle
SET FOREIGN_KEY_CHECKS = 0;

-- Tabloları sil (varsa)
DROP TABLE IF EXISTS `wms_putaway_status`;
DROP TABLE IF EXISTS `inventory_transfers`;
DROP TABLE IF EXISTS `inventory_stock`;
DROP TABLE IF EXISTS `goods_receipt_items`;
DROP TABLE IF EXISTS `goods_receipts`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis_satir`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis`;
DROP TABLE IF EXISTS `processed_requests`;
DROP TABLE IF EXISTS `employees`;
DROP TABLE IF EXISTS `shelfs`;
DROP TABLE IF EXISTS `warehouses`;
DROP TABLE IF EXISTS `branches`;
DROP TABLE IF EXISTS `urunler`;

SET FOREIGN_KEY_CHECKS = 1;

-- Şimdi complete_setup.sql dosyasını çalıştırın:
-- source backend/complete_setup.sql;