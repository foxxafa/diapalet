-- Mevcut veritabanındaki branch_id değerlerini düzeltme
USE `enzo`;

-- Warehouses tablosundaki branch_id değerlerini güncelle
UPDATE `warehouses` SET `branch_id` = 1 WHERE `id` = 1;
UPDATE `warehouses` SET `branch_id` = 2 WHERE `id` = 2;

-- Employees tablosundaki branch_id değerlerini güncelle  
UPDATE `employees` SET `branch_id` = 1 WHERE `warehouse_id` = 1;
UPDATE `employees` SET `branch_id` = 2 WHERE `warehouse_id` = 2;

-- Satin alma siparis fis tablosundaki branch_id değerlerini güncelle
UPDATE `satin_alma_siparis_fis` SET `branch_id` = 1 WHERE `branch_id` = 10;
UPDATE `satin_alma_siparis_fis` SET `branch_id` = 2 WHERE `branch_id` = 20; 