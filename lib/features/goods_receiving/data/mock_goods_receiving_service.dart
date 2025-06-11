// lib/features/goods_receiving/data/mock_goods_receiving_service.dart
import 'package:flutter/foundation.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';

class MockGoodsReceivingService implements GoodsReceivingRepository {
  final List<String> _mockInvoices = [
    "INV-MOCK-001", "INV-MOCK-002", "INV-MOCK-003"
  ];

  final List<LocationInfo> _mockLocations = [
    const LocationInfo(id: 1, name: "MAL KABUL", code: "MK"),
    const LocationInfo(id: 2, name: "DEPO-A1", code: "A1"),
    const LocationInfo(id: 3, name: "DEPO-B2", code: "B2"),
  ];

  final List<ProductInfo> _mockProductsForDropdown = [
    const ProductInfo(id: 101, name: "Mock Ürün A (Kola)", stockCode: "MOCKA001", isActive: true),
    const ProductInfo(id: 102, name: "Mock Ürün B (Gofret)", stockCode: "MOCKB002", isActive: true),
    const ProductInfo(id: 103, name: "Mock Ürün C (Süt)", stockCode: "MOCKC003", isActive: true),
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
  Future<List<ProductInfo>> getProductsForDropdown() async {
    debugPrint("MockGoodsReceivingService: Fetching products for dropdown.");
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_mockProductsForDropdown);
  }
  
  @override
  Future<List<LocationInfo>> getLocationsForDropdown() async {
    debugPrint("MockGoodsReceivingService: Fetching locations for dropdown.");
    await Future.delayed(const Duration(milliseconds: 100));
    return List.from(_mockLocations);
  }

  @override
  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    debugPrint("MockGoodsReceivingService: Saving goods receipt for invoice: ${header.invoiceNumber}");
    await Future.delayed(const Duration(milliseconds: 300));

    final newHeader = GoodsReceipt(
      id: _nextReceiptId,
      externalId: header.externalId,
      invoiceNumber: header.invoiceNumber,
      receiptDate: header.receiptDate,
      synced: header.synced,
    );
    _savedReceipts.add(newHeader);

    List<GoodsReceiptItem> newItemsWithId = [];
    for (var item in items) {
      newItemsWithId.add(GoodsReceiptItem(
        id: _nextItemId++,
        receiptId: newHeader.id!,
        product: item.product,
        quantity: item.quantity,
        locationId: item.locationId,
        containerId: item.containerId,
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
      // This is not ideal as it modifies a list item directly. In a real app with state management, this would be handled differently.
      final oldReceipt = _savedReceipts[index];
      _savedReceipts[index] = GoodsReceipt(
        id: oldReceipt.id,
        externalId: oldReceipt.externalId,
        invoiceNumber: oldReceipt.invoiceNumber,
        receiptDate: oldReceipt.receiptDate,
        synced: 1, // Mark as synced
      );
    }
  }

  @override
  Future<List<PurchaseOrder>> getOpenPurchaseOrders() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return [
      PurchaseOrder(id: 1, poId: 'PO-MOCK-001', date: DateTime.now(), notes: 'Mock sipariş', status: 0, supplierName: 'Tedarikçi A', supplierId: 1),
      PurchaseOrder(id: 2, poId: 'PO-MOCK-002', date: DateTime.now(), notes: 'Mock sipariş 2', status: 0, supplierName: 'Tedarikçi B', supplierId: 2),
    ];
  }

  @override
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return [
      PurchaseOrderItem(id: 1, orderId: orderId, productId: 101, expectedQuantity: 10, unit: 'AD', notes: null, productName: 'Mock Ürün A', stockCode: 'MOCKA001', barcode: '123', itemsPerBox: 12, itemsPerPallet: 144),
      PurchaseOrderItem(id: 2, orderId: orderId, productId: 102, expectedQuantity: 5, unit: 'AD', notes: null, productName: 'Mock Ürün B', stockCode: 'MOCKB002', barcode: '456', itemsPerBox: 24, itemsPerPallet: 240),
    ];
  }
}
