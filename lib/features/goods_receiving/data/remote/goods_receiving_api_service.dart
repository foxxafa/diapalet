// features/goods_receiving/data/remote/goods_receiving_api_service.dart
import 'package:flutter/foundation.dart';
import '../../domain/entities/goods_receipt_entities.dart';
import '../../domain/entities/product_info.dart';

abstract class GoodsReceivingRemoteDataSource {
  Future<List<String>> fetchInvoices();
  Future<List<String>> fetchPalletsForDropdown();
  Future<List<String>> fetchBoxesForDropdown();
  Future<List<ProductInfo>> fetchProductsForDropdown();
  Future<bool> sendGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items);
// Future<ProductInfo?> fetchProductDetailsByBarcode(String barcode); // Opsiyonel
}

class GoodsReceivingRemoteDataSourceImpl implements GoodsReceivingRemoteDataSource {
  // Gerçek uygulamada HttpClient (Dio, http) burada olurdu.
  final Set<String> _processedIds = {};

  @override
  Future<List<String>> fetchInvoices() async {
    debugPrint("API: Fetching invoices...");
    await Future.delayed(const Duration(milliseconds: 400));
    return ["API-INV-001", "API-INV-002", "API-INV-003"];
  }

  @override
  Future<List<String>> fetchPalletsForDropdown() async {
    debugPrint("API: Fetching pallets for dropdown...");
    await Future.delayed(const Duration(milliseconds: 300));
    return ["API-PALET-X1", "API-PALET-Y2", "API-PALET-Z3"];
  }

  @override
  Future<List<String>> fetchBoxesForDropdown() async {
    debugPrint("API: Fetching boxes for dropdown...");
    await Future.delayed(const Duration(milliseconds: 300));
    return ["API-KUTU-S1", "API-KUTU-M2", "API-KUTU-L3"];
  }

  @override
  Future<List<ProductInfo>> fetchProductsForDropdown() async {
    debugPrint("API: Fetching products for dropdown...");
    await Future.delayed(const Duration(milliseconds: 600));
    return [
      ProductInfo(id: "api_prod_101", name: "API Ürün Elma", stockCode: "ELMA001"),
      ProductInfo(id: "api_prod_102", name: "API Ürün Armut", stockCode: "ARMUT002"),
      ProductInfo(id: "api_prod_103", name: "API Ürün Muz", stockCode: "MUZ003"),
    ];
  }

  @override
  Future<bool> sendGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items) async {
    if (_processedIds.contains(header.externalId)) {
      debugPrint('API: Duplicate receipt ${header.externalId} ignored.');
      return true;
    }
    debugPrint(
        "API: Sending goods receipt ${header.externalId} for invoice: ${header.invoiceNumber}...");
    debugPrint("API: Header: ${header.toMap()}");
    for (var item in items) {
      debugPrint("API: Item: ${item.toMap()}");
    }
    await Future.delayed(const Duration(seconds: 2));
    _processedIds.add(header.externalId);
    debugPrint("API: Goods receipt sent successfully.");
    return true;
  }

// @override
// Future<ProductInfo?> fetchProductDetailsByBarcode(String barcode) async {
//   debugPrint("API: Fetching product by barcode $barcode...");
//   await Future.delayed(const Duration(milliseconds: 500));
//   if (barcode == "12345API") {
//     return ProductInfo(id: "api_barcode_prod", name: "API Barkodlu Ürün", stockCode: "BARCODE001");
//   }
//   return null;
// }
}
