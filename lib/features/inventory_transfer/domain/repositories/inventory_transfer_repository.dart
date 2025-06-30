// ----- lib/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart (GÜNCELLENDİ) -----
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';

abstract class InventoryTransferRepository {
    Future<Map<String, int>> getSourceLocations();
    Future<Map<String, int>> getTargetLocations();
    Future<List<String>> getPalletIdsAtLocation(int locationId, {String stockStatus = 'available'});
    Future<List<BoxItem>> getBoxesAtLocation(int locationId, {String stockStatus = 'available'});
    Future<List<ProductItem>> getPalletContents(String palletBarcode, int locationId, {String stockStatus = 'available'});

    Future<void> recordTransferOperation(
        TransferOperationHeader header,
        List<TransferItemDetail> items,
        int sourceLocationId,
        int targetLocationId,
        );

    /// Transfer için uygun (Kısmi/Tam Kabul) siparişleri getirir.
    Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer();

    /// ANA GÜNCELLEME: Belirli bir sipariş için transfer edilebilir tüm fiziksel birimleri (paletler ve paletsiz gruplar) getirir.
    Future<List<TransferableContainer>> getTransferableContainers(int locationId, {int? orderId});

    /// GÜNCELLEME: Koda göre lokasyon arayan yeni fonksiyon.
    /// Başarılı olursa MapEntry<name, id> döner, bulunamazsa null döner.
    Future<MapEntry<String, int>?> findLocationByCode(String code);

    Future<List<MapEntry<String, int>>> getAllLocations(int warehouseId);

    Future<void> updatePurchaseOrderStatus(int orderId, int status);

    Future<List<TransferOperationHeader>> getPendingTransfers();

    Future<void> checkAndCompletePutaway(int orderId);
}