// features/goods_receiving/data/remote/goods_receiving_api_service.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
// Bu import yolları projenize göre farklılık gösterebilir, doğruluğunu kontrol edin.
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_item.dart';
import '../models/goods_receipt_payload.dart';

/// Mal kabulü ile ilgili uzak sunucu (API) işlemlerini tanımlar.
abstract class GoodsReceivingRemoteDataSource {
  Future<List<PurchaseOrder>> fetchOpenPurchaseOrders();
  Future<List<PurchaseOrderItem>> fetchPurchaseOrderItems(int orderId);
  Future<bool> postGoodsReceipt(GoodsReceiptPayload payload);
}

/// [GoodsReceivingRemoteDataSource] arayüzünün canlı API ile çalışan gerçeklemesi.
class GoodsReceivingRemoteDataSourceImpl implements GoodsReceivingRemoteDataSource {
  final Dio _dio;

  // Dio istemcisini dışarıdan alarak veya burada oluşturarak yapılandırın.
  // **GÜNCELLENDİ:** Base URL, yerel ağdaki Flask sunucusunu işaret edecek şekilde değiştirildi.
  // "YOUR_PC_IP_ADDRESS" kısmını kendi bilgisayarınızın IP adresi ile değiştirin.
  GoodsReceivingRemoteDataSourceImpl({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
    baseUrl: "http://YOUR_PC_IP_ADDRESS:5000/v1",
    connectTimeout: const Duration(seconds: 10), // Bağlantı zaman aşımı eklendi
    receiveTimeout: const Duration(seconds: 10), // Cevap zaman aşımı eklendi
  ));

  @override
  Future<List<PurchaseOrder>> fetchOpenPurchaseOrders() async {
    debugPrint("API: Fetching open purchase orders from remote...");
    try {
      final response = await _dio.get('/purchase-orders');

      if (response.statusCode == 200 && response.data is List) {
        // API'den gelen JSON'da 'purchaseOrderNumber' ve 'supplierName' gibi
        // alan adları Flask tarafında tanımlandığı gibi olmalı.
        // PurchaseOrder.fromJson metodunun bu yeni alan adlarını handle edebildiğinden emin olun.
        return (response.data as List)
            .map((json) => PurchaseOrder.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load purchase orders. Invalid data format.');
      }
    } on DioException catch (e) {
      debugPrint("API Error fetching purchase orders: ${e.message}");
      rethrow;
    }
  }

  @override
  Future<List<PurchaseOrderItem>> fetchPurchaseOrderItems(int orderId) async {
    debugPrint("API: Fetching items for order ID: $orderId from remote...");
    try {
      final response = await _dio.get('/purchase-orders/$orderId/items');

      if (response.statusCode == 200 && response.data is List) {
        // PurchaseOrderItem.fromJson'ın da Flask API'sinden dönen JSON yapısıyla
        // uyumlu olduğundan emin olun.
        return (response.data as List)
            .map((json) => PurchaseOrderItem.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load purchase order items. Invalid data format.');
      }
    } on DioException catch (e) {
      debugPrint("API Error fetching order items: ${e.message}");
      rethrow;
    }
  }

  @override
  Future<bool> postGoodsReceipt(GoodsReceiptPayload payload) async {
    debugPrint("API: Sending goods receipt for order ID: ${payload.purchaseOrderId} to remote...");
    try {
      final response = await _dio.post('/goods-receipts', data: payload.toJson());

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint("API: Goods receipt sent successfully.");
        return true;
      } else {
        debugPrint("API: Failed to send goods receipt. Status: ${response.statusCode}, Body: ${response.data}");
        return false;
      }
    } on DioException catch (e) {
      debugPrint("API Error sending goods receipt: ${e.message}");
      debugPrint("API Error response: ${e.response?.data}");
      return false;
    }
  }
}
