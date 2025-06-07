// lib/features/goods_receiving/data/mock_goods_receiving_service.dart
import 'package:flutter/foundation.dart';
import '../domain/entities/product_info.dart';
import '../domain/entities/goods_receipt_entities.dart';
import '../domain/repositories/goods_receiving_repository.dart';

class MockGoodsReceivingService implements GoodsReceivingRepository {
  final List<String> _mockInvoices = [
    "INV-MOCK-001", "INV-MOCK-002", "INV-MOCK-003"
  ];


  final List<ProductInfo> _mockProductsForDropdown = [
    ProductInfo(id: "mock_prod_1", name: "Mock Ürün A (Kola)", stockCode: "MOCKA001"),
    ProductInfo(id: "mock_prod_2", name: "Mock Ürün B (Gofret)", stockCode: "MOCKB002"),
    ProductInfo(id: "mock_prod_3", name: "Mock Ürün C (Süt)", stockCode: "MOCKC003"),
  ];

  final List<GoodsReceipt> _savedReceipts = [];
  final Map<int, List<GoodsReceiptItem>> _savedReceiptItems = {};
  int _nextReceiptId = 1;
  int _nextItemId = 1;

  @override
  Future<List<String>> getInvoices() async {
    debugPrint("MockGoodsReceivingService: Fetching invoices.");
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_mockInvoices);
  }

  @override

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    debugPrint("MockGoodsReceivingService: Fetching products for dropdown.");
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_mockProductsForDropdown);
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    debugPrint("MockGoodsReceivingService: Saving goods receipt for invoice: ${header.invoiceNumber}");
    await Future.delayed(const Duration(milliseconds: 300));

    final newHeader = GoodsReceipt(
      id: _nextReceiptId,
      invoiceNumber: header.invoiceNumber,
      receiptDate: header.receiptDate,
      mode: header.mode,
      synced: header.synced,
    );
    _savedReceipts.add(newHeader);

    List<GoodsReceiptItem> newItemsWithId = [];
    for (var item in items) {
      newItemsWithId.add(GoodsReceiptItem(
        id: _nextItemId++,
        goodsReceiptId: newHeader.id!,
        palletOrBoxId: item.palletOrBoxId,
        product: item.product,
        quantity: item.quantity,
      ));
    }
    _savedReceiptItems[newHeader.id!] = newItemsWithId;

    debugPrint("MockGoodsReceivingService: Saved goods receipt with ID: ${newHeader.id} and ${newItemsWithId.length} items.");
    _nextReceiptId++;
    return newHeader.id!;
  }

  @override
  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts() async {
    debugPrint("MockGoodsReceivingService: Fetching unsynced goods receipts.");
    await Future.delayed(const Duration(milliseconds: 50));
    return _savedReceipts.where((r) => r.synced == 0).toList();
  }

  @override
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId) async {
    debugPrint("MockGoodsReceivingService: Fetching items for goods receipt ID: $receiptId");
    await Future.delayed(const Duration(milliseconds: 50));
    return _savedReceiptItems[receiptId] ?? [];
  }

  @override
  Future<void> markGoodsReceiptAsSynced(int receiptId) async {
    debugPrint("MockGoodsReceivingService: Marking goods receipt ID: $receiptId as synced.");
    await Future.delayed(const Duration(milliseconds: 50));
    final index = _savedReceipts.indexWhere((r) => r.id == receiptId);
    if (index != -1) {
      _savedReceipts[index].synced = 1;
    }
  }

}
