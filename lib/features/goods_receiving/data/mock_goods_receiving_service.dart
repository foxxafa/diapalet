// lib/features/goods_receiving/data/mock_goods_receiving_service.dart

import 'package:flutter/foundation.dart'; // For debugPrint
import '../domain/entities/product_info.dart';
import '../domain/entities/received_product_item.dart';
import '../domain/repositories/goods_receiving_repository.dart';

/// Mock implementation of [GoodsReceivingRepository] for development and testing.
class MockGoodsReceivingService implements GoodsReceivingRepository {
  // Mock database of products
  final Map<String, ProductInfo> _mockProducts = {
    "8697459290704": ProductInfo(name: "LABBAIK LEMON UP", stockCode: "30221"),
    "1234567890123": ProductInfo(name: "Sample Product X", stockCode: "SPX001"),
    "9876543210987": ProductInfo(name: "Another Item Y", stockCode: "AIY999"),
    "1112223334445": ProductInfo(name: "Super Widget", stockCode: "SWG007"),
  };

  // Mock list of units
  final List<String> _mockUnits = ["BOX", "UNIT"];

  @override
  Future<ProductInfo?> getProductDetailsByBarcode(String barcode) async {
    debugPrint("MockService: Fetching product for barcode: $barcode");
    await Future.delayed(const Duration(milliseconds: 600)); // Simulate network delay
    if (_mockProducts.containsKey(barcode)) {
      return _mockProducts[barcode];
    }
    debugPrint("MockService: Product not found for barcode: $barcode");
    return null; // Or throw an exception: throw Exception('Product not found');
  }

  @override
  Future<List<String>> getAvailableUnits() async {
    debugPrint("MockService: Fetching available units.");
    await Future.delayed(const Duration(milliseconds: 300)); // Simulate network delay
    return List.from(_mockUnits); // Return a copy
  }

  @override
  Future<void> saveReceivedProducts(List<ReceivedProductItem> items) async {
    debugPrint("MockService: Attempting to save ${items.length} received products.");
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
    if (items.isEmpty) {
      debugPrint("MockService: No items to save.");
      // throw Exception("No items to save."); // Optionally throw error
      return;
    }
    for (var item in items) {
      debugPrint("MockService: Saving item - ${item.toString()}");
    }
    debugPrint("MockService: All items processed successfully.");
    // In a real scenario, this would involve API calls or local database operations.
  }
}
