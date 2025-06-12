// features/goods_receiving/domain/repositories/goods_receiving_repository.dart
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_log_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';

/// The contract for fetching data required for the goods receiving process
/// and for recording the receiving operation. This implementation is offline-first.
abstract class GoodsReceivingRepository {
  /// Fetches all open purchase orders from the local database.
  Future<List<PurchaseOrder>> getOpenPurchaseOrders();

  /// Fetches all items for a specific purchase order from the local database.
  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int orderId);

  /// Fetches a list of all products available in the local database for manual selection.
  Future<List<ProductInfo>> getAllProducts();

  /// Records a completed goods receipt operation.
  /// This will update local stock immediately and queue the operation for server sync.
  Future<void> recordGoodsReceipt({
    required int? purchaseOrderId,
    String? invoiceNumber,
    required List<GoodsReceiptLogItem> receivedItems,
  });
}
