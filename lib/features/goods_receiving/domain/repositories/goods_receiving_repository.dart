// features/goods_receiving/domain/repositories/goods_receiving_repository.dart
import '../entities/product_info.dart';
import '../entities/goods_receipt_entities.dart';
import '../entities/purchase_order.dart';
import '../entities/location_info.dart';
import '../entities/purchase_order_item.dart';

abstract class GoodsReceivingRepository {
  Future<List<String>> getInvoices();
  Future<List<ProductInfo>> getProductsForDropdown();
  Future<List<LocationInfo>> getLocationsForDropdown();

  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items);

  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts();
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId);
  Future<void> markGoodsReceiptAsSynced(int receiptId);

  Future<List<PurchaseOrder>> getOpenPurchaseOrders();
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId);
}
