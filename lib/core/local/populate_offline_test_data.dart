// lib/core/local/populate_offline_test_data.dart
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart'; // For ReceiveMode
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

Future<void> populateTestData() async {
  final dbHelper = DatabaseHelper();
  final db = await dbHelper.database;

  debugPrint("Populating test data...");

  // Goods receipt - Palet
  const externalIdPalet = 'GR-PALET-001';
  var checkPalet = await db.query(
    'goods_receipt',
    where: 'external_id = ?',
    whereArgs: [externalIdPalet],
  );
  if (checkPalet.isEmpty) {
    final receiptIdPalet = await db.insert('goods_receipt', {
      'external_id': externalIdPalet,
      'invoice_number': 'INV-TEST-PALET',
      'receipt_date': DateTime.now().toIso8601String(),
      'mode': ReceiveMode.palet.name,
      'synced': 0,
    });
    debugPrint("Inserted pallet goods_receipt with id: $receiptIdPalet");

    await db.insert('goods_receipt_item', {
      'receipt_id': receiptIdPalet,
      'pallet_or_box_id': 'PALET-ABC',
      'product_id': 'PROD-P1',
      'product_name': 'Test Palet Ürün 1',
      'product_code': 'TP100',
      'quantity': 15,
    });
    await db.insert('goods_receipt_item', {
      'receipt_id': receiptIdPalet,
      'pallet_or_box_id': 'PALET-DEF', // Different pallet for variety
      'product_id': 'PROD-P2',
      'product_name': 'Test Palet Ürün 2',
      'product_code': 'TP200',
      'quantity': 25,
    });
    // Add initial location for these pallets
    await _setContainerLocation(db, 'PALET-ABC', 'MAL KABUL');
    await _setContainerLocation(db, 'PALET-DEF', 'MAL KABUL');
    debugPrint("Inserted items for pallet goods_receipt: $receiptIdPalet");
  } else {
    debugPrint("Pallet test data for goods_receipt $externalIdPalet already exists.");
  }


  // Goods receipt - Kutu
  const externalIdKutu = 'GR-KUTU-001';
  var checkKutu = await db.query(
    'goods_receipt',
    where: 'external_id = ?',
    whereArgs: [externalIdKutu],
  );
  if (checkKutu.isEmpty) {
    final receiptIdKutu = await db.insert('goods_receipt', {
      'external_id': externalIdKutu,
      'invoice_number': 'INV-TEST-KUTU',
      'receipt_date': DateTime.now().toIso8601String(),
      'mode': ReceiveMode.kutu.name,
      'synced': 0,
    });
    debugPrint("Inserted box goods_receipt with id: $receiptIdKutu");

    await db.insert('goods_receipt_item', {
      'receipt_id': receiptIdKutu,
      'pallet_or_box_id': 'KUTU-XYZ',
      'product_id': 'PROD-K1',
      'product_name': 'Test Kutu Ürün 1',
      'product_code': 'TK100',
      'quantity': 5,
    });
    await db.insert('goods_receipt_item', {
      'receipt_id': receiptIdKutu,
      'pallet_or_box_id': 'KUTU-QWE', // Different box
      'product_id': 'PROD-K2',
      'product_name': 'Test Kutu Ürün 2',
      'product_code': 'TK200',
      'quantity': 8,
    });
    // Add initial location for these boxes
    await _setContainerLocation(db, 'KUTU-XYZ', 'MAL KABUL');
    await _setContainerLocation(db, 'KUTU-QWE', 'MAL KABUL');
    debugPrint("Inserted items for box goods_receipt: $receiptIdKutu");
  } else {
    debugPrint("Box test data for goods_receipt $externalIdKutu already exists.");
  }


  // Palet transferi (example from previous data, can be kept or modified)
  const transferContainerId = 'PALET-TRANSFER-001';
  const sourceLocationTransfer = 'MAL KABUL'; // Start from MAL KABUL
  const targetLocationTransfer = 'RAF-A1-01';

  // First, ensure this pallet exists from a goods receipt or add it to container_location
  // For simplicity, we'll assume it might be a new pallet or one already received.
  // If it's a new pallet being introduced via transfer (less common), its items would be defined here.
  // If it's an existing pallet, its items are already from goods_receipt.

  // Let's create a goods receipt for PALET-TRANSFER-001 if it doesn't exist,
  // so it has some items to be transferred.
  const externalIdTransferPallet = 'GR-TRANS-PALET-001';
  var checkTransferPalletGR = await db.query(
    'goods_receipt',
    where: 'external_id = ?',
    whereArgs: [externalIdTransferPallet],
  );
  int? transferPalletReceiptId;

  if (checkTransferPalletGR.isEmpty) {
    transferPalletReceiptId = await db.insert('goods_receipt', {
      'external_id': externalIdTransferPallet,
      'invoice_number': 'INV-TRANSFER-PALET',
      'receipt_date': DateTime.now().toIso8601String(),
      'mode': ReceiveMode.palet.name,
      'synced': 0,
    });
    await db.insert('goods_receipt_item', {
      'receipt_id': transferPalletReceiptId,
      'pallet_or_box_id': transferContainerId,
      'product_id': 'PROD-TR1',
      'product_name': 'Transfer Ürün 1',
      'product_code': 'TR001',
      'quantity': 20,
    });
    await _setContainerLocation(db, transferContainerId, sourceLocationTransfer); // Initial location
    debugPrint("Created goods receipt for transfer pallet $transferContainerId at $sourceLocationTransfer");
  }


  // Check if a transfer operation for this container already exists to avoid duplicates (optional)
  final transferId = await db.insert('transfer_operation', {
    'operation_type': 'palet', // or use AssignmentMode.palet.name from pallet_assignment entities
    'source_location': sourceLocationTransfer,
    'container_id': transferContainerId,
    'target_location': targetLocationTransfer,
    'transfer_date': DateTime.now().toIso8601String(),
    'synced': 0,
  });
  debugPrint("Inserted transfer_operation with id: $transferId");

  await db.insert('transfer_item', {
    'operation_id': transferId,
    'product_code': 'TR001', // Match product from the goods receipt for this pallet
    'product_name': 'Transfer Ürün 1',
    'quantity': 5, // Transferring a portion
  });
  debugPrint("Inserted item for transfer_operation: $transferId");

  // Update container location after transfer
  await _setContainerLocation(db, transferContainerId, targetLocationTransfer);
  debugPrint("Updated location for $transferContainerId to $targetLocationTransfer after transfer");

  debugPrint("Test data population completed.");
}

// Helper to set container location
Future<void> _setContainerLocation(Database db, String containerId, String location) async {
  await db.insert('container_location', {
    'container_id': containerId,
    'location': location,
    'last_updated': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
