// lib/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';

abstract class InventoryTransferRepository {
  Future<Map<String, int>> getSourceLocations();
  Future<Map<String, int>> getTargetLocations();
  Future<List<String>> getPalletIdsAtLocation(int locationId);
  Future<List<BoxItem>> getBoxesAtLocation(int locationId);
  Future<List<ProductItem>> getPalletContents(String palletId);

  Future<void> recordTransferOperation(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      );

  // === YENİ METOTLAR ===
  /// Transfer için uygun (Kısmi/Tam Kabul) siparişleri getirir.
  Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer();

  /// Belirli bir siparişin kalemlerini, ne kadarının taşındığı bilgisiyle birlikte getirir.
  Future<List<PurchaseOrderItem>> getPurchaseOrderItemsForTransfer(int orderId);
// ======================
}