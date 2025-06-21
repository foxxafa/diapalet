// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
    final DatabaseHelper dbHelper;
    final Dio dio;
    final NetworkInfo networkInfo;

    InventoryTransferRepositoryImpl({
      required this.dbHelper,
      required this.dio,
      required this.networkInfo,
    });

    // === YENİ METOTLARIN IMPLEMENTASYONU ===

    @override
    Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer() async {
      final db = await dbHelper.database;
      // DÜZELTME: Sipariş durumu 'Kısmi Kabul' (2) veya mal kabulü 'Tamamlandı' (3) olanları getir.
      // 'Tamamlandı' olan siparişler, tüm kalemleri rafa yerleştirilene kadar listede kalmalıdır.
      final maps = await db.query(
        'satin_alma_siparis_fis',
        where: 'status IN (?, ?)',
        whereArgs: [2, 3], // 2: Kısmi Kabul, 3: Tamamlandı
        orderBy: 'tarih DESC',
      );
      return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
    }

    @override
    Future<List<PurchaseOrderItem>> getPurchaseOrderItemsForTransfer(int orderId) async {
      final db = await dbHelper.database;
      // ANA DÜZELTME: SQL sorgusu, bir ürüne ait mal kabulü yapılmış MİKTARI ve bu miktardan ne kadarının
      // transfer edildiğini (taşındığını) hesaplayacak şekilde güncellendi.
      // `from_location_id = 1` varsayımı, tüm ürünlerin önce "Mal Kabul Alanı"na (ID: 1) girdiği iş akışına dayanır.
      final maps = await db.rawQuery('''
      SELECT
        s.*,
        u.UrunAdi,
        u.StokKodu,
        u.Barcode1,
        u.aktif,
        -- Bu sipariş ve ürün için kabul edilmiş toplam miktar
        COALESCE((SELECT SUM(gri.quantity_received)
                  FROM goods_receipt_items gri
                  JOIN goods_receipts gr ON gr.id = gri.receipt_id
                  WHERE gr.siparis_id = s.siparis_id AND gri.urun_id = s.urun_id), 0) as receivedQuantity,
        -- Bu ürün için Mal Kabul Alanı'ndan (id=1) çıkışı yapılan toplam miktar
        COALESCE((SELECT SUM(it.quantity)
                  FROM inventory_transfers it
                  WHERE it.urun_id = s.urun_id AND it.from_location_id = 1), 0) as transferredQuantity
      FROM satin_alma_siparis_fis_satir s
      JOIN urunler u ON u.id = s.urun_id
      WHERE s.siparis_id = ?
    ''', [orderId]);
      return maps.map((map) => PurchaseOrderItem.fromDb(map)).toList();
    }

    // =====================================

    @override
    Future<void> recordTransferOperation(
        TransferOperationHeader header,
        List<TransferItemDetail> items,
        int sourceLocationId,
        int targetLocationId,
        ) async {
      final apiPayload = _buildApiPayload(header, items, sourceLocationId, targetLocationId);
      await _saveForSync(apiPayload, header, items, sourceLocationId, targetLocationId);
    }

    Map<String, dynamic> _buildApiPayload(
        TransferOperationHeader header,
        List<TransferItemDetail> items,
        int sourceLocationId,
        int targetLocationId,
        ) {
      return {
        "header": header.toApiJson(sourceLocationId, targetLocationId),
        "items": items.map((item) => item.toApiJson()).toList(),
      };
    }

    Future<void> _saveForSync(
        Map<String, dynamic> apiPayload,
        TransferOperationHeader header,
        List<TransferItemDetail> items,
        int sourceLocationId,
        int targetLocationId) async {
      final db = await dbHelper.database;
      try {
        await db.transaction((txn) async {
          for (final item in items) {
            final isPalletOperation = (header.operationType == AssignmentMode.pallet || header.operationType == AssignmentMode.box_from_pallet);
            final sourcePallet = isPalletOperation ? item.sourcePalletBarcode : null;
            final targetPallet = (header.operationType == AssignmentMode.pallet) ? item.sourcePalletBarcode : null;

            await _updateStock(txn, item.productId, sourceLocationId, -item.quantity, sourcePallet);
            await _updateStock(txn, item.productId, targetLocationId, item.quantity, targetPallet);

            await txn.insert('inventory_transfers', {
              'urun_id': item.productId,
              'from_location_id': sourceLocationId,
              'to_location_id': targetLocationId,
              'quantity': item.quantity,
              'pallet_barcode': targetPallet,
              'employee_id': header.employeeId,
              'transfer_date': header.transferDate.toIso8601String(),
              'created_at': DateTime.now().toIso8601String(),
            });
          }

          final pendingOp = PendingOperation(
            type: PendingOperationType.inventoryTransfer,
            data: jsonEncode(apiPayload),
            createdAt: DateTime.now(),
          );
          await txn.insert('pending_operation', pendingOp.toDbMap());
        });
        debugPrint("Transfer işlemi başarıyla lokale kaydedildi.");
      } catch (e, s) {
        debugPrint("Lokal transfer kaydı hatası: $e\n$s");
        throw Exception("Lokal veritabanına transfer kaydedilirken hata oluştu: $e");
      }
    }

    Future<void> _updateStock(Transaction txn, int urunId, int locationId, double quantityChange, String? palletBarcode) async {
      final condition = palletBarcode == null
          ? 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL'
          : 'urun_id = ? AND location_id = ? AND pallet_barcode = ?';
      final args = palletBarcode == null ? [urunId, locationId] : [urunId, locationId, palletBarcode];

      final existingStock = await txn.query('inventory_stock', where: condition, whereArgs: args);

      if (existingStock.isNotEmpty) {
        final currentStock = existingStock.first;
        final currentQty = (currentStock['quantity'] as num);
        final newQty = currentQty + quantityChange;

        if (newQty > 0.001) {
          await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
              where: 'id = ?', whereArgs: [currentStock['id']]);
        } else {
          await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [currentStock['id']]);
        }
      } else if (quantityChange > 0) {
        await txn.insert('inventory_stock', {
          'urun_id': urunId, 'location_id': locationId, 'quantity': quantityChange,
          'pallet_barcode': palletBarcode, 'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        debugPrint("UYARI: Kaynak lokasyonda ($locationId) bulunmayan bir stok (Ürün ID: $urunId, Palet: $palletBarcode) düşülmeye çalışıldı. İşlem atlandı.");
      }
    }

    // --- MEVCUT METOTLAR (DEĞİŞİKLİK YOK) ---
    @override
    Future<Map<String, int>> getSourceLocations() async {
      final db = await dbHelper.database;
      final maps = await db.query('locations', where: 'is_active = 1');
      return {for (var map in maps) map['name'] as String: map['id'] as int};
    }

    @override
    Future<Map<String, int>> getTargetLocations() async => getSourceLocations();

    @override
    Future<List<String>> getPalletIdsAtLocation(int locationId) async {
      final db = await dbHelper.database;
      final maps = await db.rawQuery(
          'SELECT DISTINCT pallet_barcode FROM inventory_stock WHERE location_id = ? AND pallet_barcode IS NOT NULL', [locationId]);
      return maps.map((map) => map['pallet_barcode'] as String).toList();
    }

    @override
    Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
      final db = await dbHelper.database;
      final maps = await db.rawQuery('''
      SELECT u.id as productId, u.UrunAdi as productName, u.StokKodu as productCode, u.Barcode1 as barcode1, SUM(s.quantity) as quantity 
      FROM inventory_stock s 
      JOIN urunler u ON u.id = s.urun_id 
      WHERE s.location_id = ? AND s.pallet_barcode IS NULL 
      GROUP BY u.id
    ''', [locationId]);
      return maps.map((map) => BoxItem.fromDbMap(map)).toList();
    }

    @override
    Future<List<ProductItem>> getPalletContents(String palletId) async {
      final db = await dbHelper.database;
      final maps = await db.rawQuery('''
      SELECT u.id, u.UrunAdi as name, u.StokKodu as code, s.quantity as currentQuantity 
      FROM inventory_stock s 
      JOIN urunler u ON u.id = s.urun_id 
      WHERE s.pallet_barcode = ?
    ''', [palletId]);
      return maps.map((map) => ProductItem.fromMap(map)).toList();
    }
}