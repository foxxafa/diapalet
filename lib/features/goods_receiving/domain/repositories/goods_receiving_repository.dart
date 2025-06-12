// features/goods_receiving/domain/repositories/goods_receiving_repository.dart
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/recent_receipt_item.dart';

/// Mal kabul süreci için veri getirme ve kaydetme sözleşmesi.
/// Bu implementasyon offline-first (önce çevrimdışı) çalışır.
abstract class GoodsReceivingRepository {
  /// Yerel veritabanından açık satınalma siparişlerini getirir.
  Future<List<PurchaseOrder>> getOpenPurchaseOrders();

  /// Belirli bir satınalma siparişinin kalemlerini yerel veritabanından getirir.
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId);
  
  /// Ürünleri filtreleyerek getirir.
  Future<List<ProductInfo>> getProducts({String? filter});

  /// Son mal kabul işlemlerini yerel veritabanından getirir.
  Future<List<RecentReceiptItem>> getRecentReceipts({int limit = 50});

  /// Yeni bir mal kabul işlemini kaydeder.
  /// Bu, yerel stoğu anında günceller ve işlemi sunucuya senkronizasyon için kuyruğa alır.
  Future<void> saveGoodsReceipt({
    required int? purchaseOrderId,
    required List<({int productId, double quantity, String? palletBarcode})> items,
  });

  Future<List<PurchaseOrder>> getPurchaseOrders();
  Future<List<ProductInfo>> searchProducts(String query);
  Future<ProductInfo?> getProductDetails(String barcode);
  Future<LocationInfo?> getLocationDetails(String barcode);
  Future<void> saveGoodsReceipt(GoodsReceipt receipt);
}
