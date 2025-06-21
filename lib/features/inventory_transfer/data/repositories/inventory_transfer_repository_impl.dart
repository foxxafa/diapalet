// lib/features/inventory_transfer/data/repositories/inventory_transfer_repository_impl.dart
import 'dart:convert';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/core/network/network_info.dart';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class InventoryTransferRepositoryImpl implements InventoryTransferRepository {
  final DatabaseHelper dbHelper;
  final Dio dio;
  final NetworkInfo networkInfo;

  static const int malKabulLocationId = 1;

  InventoryTransferRepositoryImpl({
    required this.dbHelper,
    required this.dio,
    required this.networkInfo,
  });

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'satin_alma_siparis_fis',
      // GÜNCELLEME: Sadece 'Kısmi Kabul' (2) ve 'Tamamlandı' (3) değil,
      // aynı zamanda 'Onaylandı' (1) durumundaki siparişler de mal kabule uygun olabilir.
      // Sizin mantığınıza göre 'status IN (2, 3)' doğruysa bu satırı değiştirmeyin.
      // Genellikle mal kabulü yapılmış siparişler için transfer yapılır, bu yüzden 2 ve 3 mantıklıdır.
      where: 'status IN (?, ?)',
      whereArgs: [2, 3],
      orderBy: 'tarih DESC',
    );
    return maps.map((map) => PurchaseOrder.fromMap(map)).toList();
  }

  // GÜNCELLEME BAŞLANGIÇ: getTransferableContainers metodu tamamen yenilendi.
  @override
  Future<List<TransferableContainer>> getTransferableContainers(int orderId) async {
    final db = await dbHelper.database;

    // 1. Bu sipariş için mal kabulü yapılmış tüm kalemleri (urun_id, pallet_barcode) bul.
    // Bu, hangi stok kalemlerinin bu siparişe ait olduğunu belirlemek için anahtarımızdır.
    final receiptItemsForOrder = await db.rawQuery('''
      SELECT DISTINCT
        gri.urun_id,
        gri.pallet_barcode
      FROM goods_receipt_items gri
      JOIN goods_receipts gr ON gr.id = gri.receipt_id
      WHERE gr.siparis_id = ?
    ''', [orderId]);

    if (receiptItemsForOrder.isEmpty) {
      return []; // Bu siparişe ait mal kabul kaydı yoksa, boş liste dön.
    }

    // 2. Mal kabul alanında (location_id = 1) bulunan TÜM stokları ve ürün detaylarını çek.
    final stockInReceiptArea = await db.rawQuery('''
      SELECT
        s.urun_id,
        s.quantity,
        s.pallet_barcode,
        u.id, 
        u.UrunAdi,
        u.StokKodu,
        u.Barcode1,
        u.aktif
      FROM inventory_stock s
      JOIN urunler u ON u.id = s.urun_id
      WHERE s.location_id = ?
    ''', [malKabulLocationId]);

    // 3. Mal kabul alanındaki stokları, sadece bu siparişe ait olanlarla eşleştirerek filtrele.
    final relevantStock = stockInReceiptArea.where((stock) {
      return receiptItemsForOrder.any((receiptItem) {
        bool isSameProduct = stock['urun_id'] == receiptItem['urun_id'];
        bool isSamePallet = stock['pallet_barcode'] == receiptItem['pallet_barcode'];
        return isSameProduct && isSamePallet;
      });
    }).toList();

    if (relevantStock.isEmpty) {
      return []; // Siparişe ait ürünler mal kabul alanından taşınmış.
    }

    // 4. Filtrelenmiş ve doğrulanmış stokları, UI'da gösterilecek container'lara grupla.
    final containers = <String, List<Map<String, dynamic>>>{};
    for (var stockItem in relevantStock) {
      final pallet = stockItem['pallet_barcode'] as String?;
      final productId = stockItem['urun_id'] as int;
      final key = pallet ?? 'PALETSIZ_$productId'; // Gruplama anahtarı
      containers.putIfAbsent(key, () => []).add(stockItem);
    }

    final result = <TransferableContainer>[];
    for (var entry in containers.entries) {
      final containerId = entry.key;
      final itemsInContainer = entry.value;
      final firstItem = itemsInContainer.first;

      final displayName = (firstItem['pallet_barcode'] as String?) != null
          ? "Palet: ${firstItem['pallet_barcode']}"
          : "Paletsiz: ${firstItem['UrunAdi']}";

      result.add(
        TransferableContainer(
          id: containerId,
          displayName: displayName,
          items: itemsInContainer.map((item) {
            return TransferableItem(
              product: ProductInfo.fromDbMap(item),
              quantity: (item['quantity'] as num).toDouble(),
              sourcePalletBarcode: item['pallet_barcode'] as String?,
            );
          }).toList(),
        ),
      );
    }
    return result;
  }
  // GÜNCELLEME SONU

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
          // 'item.palletId' serbest transferden, 'sourcePalletBarcode' sipariş transferinden gelir.
          // İkisini de kontrol ederek kaynak paleti bulalım.
          final sourcePallet = item.palletId ?? item.sourcePalletBarcode;

          // Stok güncelleme ve transfer kaydı
          await _updateStock(txn, item.productId, sourceLocationId, -item.quantity, sourcePallet);
          await _updateStock(txn, item.productId, targetLocationId, item.quantity, null); // Hedef her zaman paletsiz

          await txn.insert('inventory_transfers', {
            'urun_id': item.productId,
            'from_location_id': sourceLocationId,
            'to_location_id': targetLocationId,
            'quantity': item.quantity,
            'from_pallet_barcode': sourcePallet,
            'pallet_barcode': null, // Hedef palet şimdilik null, bu mantık ileride geliştirilebilir
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
    final condition = palletBarcode == null ? 'urun_id = ? AND location_id = ? AND pallet_barcode IS NULL' : 'urun_id = ? AND location_id = ? AND pallet_barcode = ?';
    final args = palletBarcode == null ? [urunId, locationId] : [urunId, locationId, palletBarcode];

    final existingStock = await txn.query('inventory_stock', where: condition, whereArgs: args);

    if (existingStock.isNotEmpty) {
      final currentStock = existingStock.first;
      final currentQty = (currentStock['quantity'] as num);
      final newQty = currentQty + quantityChange;

      if (newQty > 0.001) {
        await txn.update('inventory_stock', {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [currentStock['id']]);
      } else {
        await txn.delete('inventory_stock', where: 'id = ?', whereArgs: [currentStock['id']]);
      }
    } else if (quantityChange > 0) {
      await txn.insert('inventory_stock', {
        'urun_id': urunId,
        'location_id': locationId,
        'quantity': quantityChange,
        'pallet_barcode': palletBarcode,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      final errorMessage = "Kaynakta stok bulunamadı (Lokasyon: $locationId, Ürün: $urunId, Palet: ${palletBarcode ?? 'YOK'}). İşlem iptal edildi.";
      debugPrint(errorMessage);
      throw Exception(errorMessage);
    }
  }

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
    final maps = await db.rawQuery('SELECT DISTINCT pallet_barcode FROM inventory_stock WHERE location_id = ? AND pallet_barcode IS NOT NULL', [locationId]);
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
      GROUP BY u.id, u.UrunAdi, u.StokKodu, u.Barcode1
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