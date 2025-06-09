// features/goods_receiving/domain/repositories/goods_receiving_repository.dart
import '../entities/product_info.dart';
import '../entities/goods_receipt_entities.dart';

abstract class GoodsReceivingRepository {
  Future<List<String>> getInvoices();
  Future<List<ProductInfo>> getProductsForDropdown();

  Future<int> saveGoodsReceipt(GoodsReceipt header, List<GoodsReceiptItem> items);

  Future<List<GoodsReceipt>> getUnsyncedGoodsReceipts();
  Future<List<GoodsReceiptItem>> getItemsForGoodsReceipt(int receiptId);
  Future<void> markGoodsReceiptAsSynced(int receiptId);

  Future<List<PurchaseOrder>> getOpenPurchaseOrders();
}
