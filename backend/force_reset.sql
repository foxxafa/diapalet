-- FORCE DROP ALL TABLES AND RECREATE FROM SCRATCH
SET FOREIGN_KEY_CHECKS=0;

-- Drop ALL existing tables
DROP TABLE IF EXISTS `branches`;
DROP TABLE IF EXISTS `employees`;
DROP TABLE IF EXISTS `goods_receipt_items`;
DROP TABLE IF EXISTS `goods_receipts`;
DROP TABLE IF EXISTS `inventory_stock`;
DROP TABLE IF EXISTS `inventory_transfers`;
DROP TABLE IF EXISTS `processed_requests`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis`;
DROP TABLE IF EXISTS `satin_alma_siparis_fis_satir`;
DROP TABLE IF EXISTS `shelfs`;
DROP TABLE IF EXISTS `urunler`;
DROP TABLE IF EXISTS `warehouses`;
DROP TABLE IF EXISTS `wms_putaway_status`;

SET FOREIGN_KEY_CHECKS=1;

-- Now recreate from complete_setup.sql will be called next
