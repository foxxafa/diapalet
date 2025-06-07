// lib/features/pallet_assignment/data/datasources/pallet_assignment_local_datasource.dart
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:uuid/uuid.dart';


abstract class PalletAssignmentLocalDataSource {
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<void> markTransferOperationAsSynced(int operationId);
  Future<void> updateContainerLocation(String containerId, String newLocation, DateTime updateTime);
  Future<String?> getContainerLocation(String containerId);
  Future<void> clearSyncedTransferOperations();
  Future<List<String>> getDistinctContainerLocations();
  Future<List<String>> getContainerIdsByLocation(String location, String mode);
  Future<List<ProductItem>> getContainerContents(String containerId);
  Future<void> decreaseProductQuantityInGoodsReceipt(String containerId, String productCode, int quantityToDecrease);
  Future<void> addReceivedPortionAtTarget(
      String originalContainerId,
      String targetLocation,
      AssignmentMode mode,
      DateTime transferDate,
      List<TransferItemDetail> transferredItems
      );
}

class PalletAssignmentLocalDataSourceImpl implements PalletAssignmentLocalDataSource {
  final DatabaseHelper dbHelper;

  PalletAssignmentLocalDataSourceImpl({required this.dbHelper});

  @override
  Future<int> saveTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    final db = await dbHelper.database;
    late int operationId;

    await db.transaction((txn) async {
      await txn.insert(
        'container',
        {'container_id': header.containerId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      operationId = await txn.insert(
        'transfer_operation',
        header.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint("Saved transfer_operation with id: $operationId. Synced status: ${header.synced}");

      for (var item in items) {
        final itemToSave = TransferItemDetail(
          operationId: operationId,
          productId: item.productId, // HATA DÜZELTİLDİ: item.productId değeri atandı.
          productCode: item.productCode,
          productName: item.productName,
          quantity: item.quantity,
        );
        await txn.insert(
          'transfer_item',
          itemToSave.toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        debugPrint("Saved transfer_item for operation_id: $operationId, product: ${item.productName} (${item.productCode}), productId: ${item.productId}");
      }
    });
    return operationId;
  }

  @override
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transfer_operation',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id DESC',
    );
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) {
      return TransferOperationHeader.fromMap(maps[i]);
    });
  }

  @override
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT ti.id, ti.operation_id, ti.product_id, ti.quantity,
             p.name AS product_name, p.code AS product_code
      FROM transfer_item ti
      JOIN product p ON p.id = ti.product_id
      WHERE ti.operation_id = ?
    ''', [operationId]);
    if (maps.isEmpty) return [];
    return List.generate(maps.length, (i) {
      return TransferItemDetail.fromMap(maps[i]);
    });
  }

  @override
  Future<void> markTransferOperationAsSynced(int operationId) async {
    final db = await dbHelper.database;
    final count = await db.update(
      'transfer_operation',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [operationId],
    );
    debugPrint("Marked transfer_operation id $operationId as synced. Rows affected: $count");
  }

  @override
  Future<void> updateContainerLocation(String containerId, String newLocation, DateTime updateTime) async {
    final db = await dbHelper.database;
    await db.insert(
      'container',
      {'container_id': containerId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'container_location',
      {'container_id': containerId, 'location': newLocation, 'last_updated': updateTime.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint("Updated/Inserted location for container $containerId to $newLocation.");
  }

  @override
  Future<String?> getContainerLocation(String containerId) async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'container_location',
      columns: ['location'],
      where: 'container_id = ?',
      whereArgs: [containerId],
    );
    if (maps.isNotEmpty) {
      return maps.first['location'] as String?;
    }
    return null;
  }

  @override
  Future<void> clearSyncedTransferOperations() async {
    final db = await dbHelper.database;
    final count = await db.delete(
      'transfer_operation',
      where: 'synced = ?',
      whereArgs: [1],
    );
    debugPrint("Cleared $count synced transfer operations.");
  }

  @override
  Future<List<String>> getDistinctContainerLocations() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT location FROM container_location ORDER BY location',
    );
    return rows.map((e) => e['location'] as String).toList();
  }

  @override
  Future<List<String>> getContainerIdsByLocation(String location, String mode) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT cl.container_id
      FROM container_location cl
      JOIN goods_receipt_item gri ON gri.pallet_or_box_id = cl.container_id
      JOIN goods_receipt gr ON gr.id = gri.receipt_id 
      WHERE cl.location = ? AND gr.mode = ? 
      ORDER BY cl.container_id
    ''', [location, mode]);
    return rows.map((e) => e['container_id'] as String).toList();
  }

  @override
  Future<List<ProductItem>> getContainerContents(String containerId) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS product_id, p.name AS product_name, p.code AS product_code, SUM(gri.quantity) as qty
      FROM goods_receipt_item gri
      JOIN product p ON p.id = gri.product_id
      WHERE gri.pallet_or_box_id = ? AND gri.quantity > 0
      GROUP BY p.id, p.name, p.code
      ORDER BY p.name
    ''', [containerId]);
    return rows
        .map((e) => ProductItem(
      id: e['product_id'] as String,
      name: e['product_name'] as String,
      productCode: e['product_code'] as String,
      currentQuantity: (e['qty'] as int? ?? 0),
    ))
        .toList();
  }

  @override
  Future<void> decreaseProductQuantityInGoodsReceipt(String containerId, String productCode, int quantityToDecrease) async {
    final db = await dbHelper.database;
    if (quantityToDecrease <= 0) return;

    List<Map<String, dynamic>> itemsInContainer = await db.rawQuery('''
      SELECT gri.id, gri.quantity
      FROM goods_receipt_item gri
      JOIN product p ON p.id = gri.product_id
      WHERE gri.pallet_or_box_id = ? AND p.code = ? AND gri.quantity > 0
      ORDER BY gri.id ASC
    ''', [containerId, productCode]);

    if (itemsInContainer.isEmpty) {
      debugPrint("UYARI: Miktar azaltılacak ürün ($productCode) $containerId içinde bulunamadı veya miktarı zaten sıfır.");
      return;
    }

    int remainingToDecrease = quantityToDecrease;

    for (var itemMap in itemsInContainer) {
      if (remainingToDecrease <= 0) break;

      int currentItemDbId = itemMap['id'] as int;
      int currentItemQty = itemMap['quantity'] as int;

      if (currentItemQty >= remainingToDecrease) {
        int newQty = currentItemQty - remainingToDecrease;
        await db.update(
          'goods_receipt_item',
          {'quantity': newQty},
          where: 'id = ?',
          whereArgs: [currentItemDbId],
        );
        debugPrint("goods_receipt_item ID $currentItemDbId miktarı $remainingToDecrease azaltıldı. Yeni miktar: $newQty");
        remainingToDecrease = 0;
      } else {
        await db.update(
          'goods_receipt_item',
          {'quantity': 0},
          where: 'id = ?',
          whereArgs: [currentItemDbId],
        );
        debugPrint("goods_receipt_item ID $currentItemDbId tamamen tüketildi (eski miktar: $currentItemQty).");
        remainingToDecrease -= currentItemQty;
      }
    }

    if (remainingToDecrease > 0) {
      debugPrint("KRİTİK UYARI: $containerId içindeki $productCode için toplam stok, istenen $quantityToDecrease miktarını karşılayamadı. $remainingToDecrease birim eksik kaldı.");
    }
  }

  @override
  Future<void> addReceivedPortionAtTarget(
      String originalContainerId,
      String targetLocation,
      AssignmentMode mode,
      DateTime transferDate,
      List<TransferItemDetail> transferredItems
      ) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      for (var item in transferredItems) {
        final existing = await txn.rawQuery('''
          SELECT gri.id, gri.quantity, gri.pallet_or_box_id
          FROM goods_receipt_item gri
          JOIN container_location cl ON cl.container_id = gri.pallet_or_box_id
          JOIN product p ON p.id = gri.product_id
          WHERE cl.location = ?
            AND gri.pallet_or_box_id LIKE ?
            AND p.code = ?
          ORDER BY gri.id DESC
          LIMIT 1
        ''', [
          targetLocation,
          '${originalContainerId}_${item.productCode}_%',
          item.productCode
        ]);

        if (existing.isNotEmpty) {
          final row = existing.first;
          final currentQty = row['quantity'] as int? ?? 0;
          final itemId = row['id'] as int;
          final containerId = row['pallet_or_box_id'] as String;

          await txn.update(
            'goods_receipt_item',
            {'quantity': currentQty + item.quantity},
            where: 'id = ?',
            whereArgs: [itemId],
          );

          await txn.update(
            'container_location',
            {'last_updated': transferDate.toIso8601String()},
            where: 'container_id = ?',
            whereArgs: [containerId],
          );

          debugPrint(
              "Hedefte mevcut kutu $containerId miktarı ${item.quantity} arttırıldı. Yeni miktar: ${currentQty + item.quantity}");
        } else {
          String externalReceiptId =
              'TRANSFER_${originalContainerId}_${DateTime.now().millisecondsSinceEpoch}';
          String invoiceNumber = 'FROM_$originalContainerId';

          final receiptData = {
            'external_id': externalReceiptId,
            'invoice_number': invoiceNumber,
            'receipt_date': transferDate.toIso8601String(),
            'mode': mode.name,
            'synced': 0,
          };
          int newReceiptId = await txn.insert('goods_receipt', receiptData);
          debugPrint(
              "Hedef lokasyon için yeni goods_receipt oluşturuldu ID: $newReceiptId");

          String targetInstanceContainerId =
              '${originalContainerId}_${item.productCode}_${const Uuid().v4().substring(0,8)}';

          await txn.insert(
            'product',
            {
              'id': item.productId,
              'name': item.productName,
              'code': item.productCode,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          await txn.insert(
            'container',
            {'container_id': targetInstanceContainerId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

          final itemData = {
            'receipt_id': newReceiptId,
            'pallet_or_box_id': targetInstanceContainerId,
            'product_id': item.productId,
            'quantity': item.quantity,
          };
          await txn.insert('goods_receipt_item', itemData);
          debugPrint(
              "Hedef lokasyon için yeni goods_receipt_item oluşturuldu: ${item.productName}, Miktar: ${item.quantity}, Sanal Kutu ID: $targetInstanceContainerId");

          await txn.insert(
            'container_location',
            {
              'container_id': targetInstanceContainerId,
              'location': targetLocation,
              'last_updated': transferDate.toIso8601String()
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          debugPrint(
              "Sanal container $targetInstanceContainerId, $targetLocation lokasyonuna eklendi.");
        }
      }
    });
  }
}
