-- DepoComponent.php için warehouses tablosuna dia_id kolonu ekleme
ALTER TABLE `warehouses` ADD COLUMN `dia_id` INT NULL AFTER `warehouse_code`;

-- Shelfs tablosuna da dia_key kolonu ekleyelim (ihtiyaç olursa)
ALTER TABLE `shelfs` ADD COLUMN `dia_key` VARCHAR(20) NULL AFTER `code`; 