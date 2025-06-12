// lib/features/goods_receiving/domain/repositories/goods_receiving_repository.dart

import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';

/// Mal kabul süreci için veri getirme ve kaydetme sözleşmesi (kontrat).
/// Implementasyonlar (somut sınıflar) bu arayüzü kullanmalıdır.
abstract class GoodsReceivingRepository {
  /// Yerel veritabanından açık (tamamlanmamış) satınalma siparişlerini getirir.
  Future<List<PurchaseOrder>> getOpenPurchaseOrders();

  /// Belirli bir satınalma siparişinin kalemlerini yerel veritabanından getirir.
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId);

  /// Verilen bir sorgu metnine göre ürünleri arar.
  Future<List<ProductInfo>> searchProducts(String query);

  /// Sistemdeki tüm lokasyonları getirir.
  Future<List<LocationInfo>> getLocations();

  /// Yeni bir mal kabul işlemini kaydeder.
  /// Bu metot, online/offline mantığını yönetmelidir.
  Future<void> saveGoodsReceipt(GoodsReceiptPayload payload);
}
