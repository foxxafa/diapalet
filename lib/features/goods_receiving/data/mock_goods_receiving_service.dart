// lib/features/goods_receiving/data/mock_goods_receiving_service.dart
// Mock servis yeni repository arayüzüne göre güncellendi.
import 'package:flutter/foundation.dart';
import '../domain/entities/product_info.dart';
import '../domain/entities/goods_receipt_log_item.dart';
import '../domain/repositories/goods_receiving_repository.dart';

class MockGoodsReceivingService implements GoodsReceivingRepository {
  final List<String> _mockInvoices = [
    "INV-2023-001", "INV-2023-002", "INV-2023-003", "INV-2023-004"
  ];

  final List<String> _mockPallets = [
    "PALET-A001", "PALET-A002", "PALET-B001", "PALET-C001X"
  ];

  final List<String> _mockBoxes = [
    "KUTU-X01", "KUTU-X02", "KUTU-Y01", "KUTU-Z05"
  ];

  final List<ProductInfo> _mockProductsForDropdown = [
    ProductInfo(id: "prod1", name: "Coca-Cola 1L", stockCode: "COLA1L"),
    ProductInfo(id: "prod2", name: "Eti Karam Gofret 40g", stockCode: "ETIGF40"),
    ProductInfo(id: "prod3", name: "Fairy Bulaşık Deterjanı 1L", stockCode: "FAIRY1L"),
    ProductInfo(id: "prod4", name: "Süt İçim 1L", stockCode: "ICIM1L"),
    ProductInfo(id: "prod5", name: "Super Widget (Demo)", stockCode: "SWG007"),
  ];

  @override
  Future<List<String>> getInvoices() async {
    debugPrint("MockService: Fetching invoices.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockInvoices);
  }

  @override
  Future<List<String>> getPalletsForDropdown() async {
    debugPrint("MockService: Fetching pallets for dropdown.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockPallets);
  }

  @override
  Future<List<String>> getBoxesForDropdown() async {
    debugPrint("MockService: Fetching boxes for dropdown.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockBoxes);
  }

  @override
  Future<List<ProductInfo>> getProductsForDropdown() async {
    debugPrint("MockService: Fetching products for dropdown.");
    await Future.delayed(const Duration(milliseconds: 250));
    return List.from(_mockProductsForDropdown);
  }

  @override
  Future<void> saveGoodsReceiptLog(List<GoodsReceiptLogItem> items, ReceiveMode mode) async {
    debugPrint("MockService: Attempting to save ${items.length} goods receipt log items for mode: ${mode.displayName}.");
    await Future.delayed(const Duration(seconds: 1));
    if (items.isEmpty) {
      debugPrint("MockService: No items to save.");
      return;
    }
    for (var item in items) {
      debugPrint("MockService: Saving item - ${item.toString()}");
    }
    debugPrint("MockService: All items processed successfully for ${mode.displayName}.");
  }
}
