// lib/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';

abstract class InventoryTransferRepository {
    Future<Map<String, int?>> getSourceLocations({bool includeReceivingArea = true});
    Future<Map<String, int?>> getTargetLocations({bool excludeReceivingArea = false});

    // GÜNCELLEME: Bu iki metod yerine daha genel bir metod kullanılacak.
    Future<List<String>> getPalletIdsAtLocation(int? locationId, {List<String> stockStatuses = const ['available'], String? deliveryNoteNumber});
    Future<List<BoxItem>> getBoxesAtLocation(int? locationId, {List<String> stockStatuses = const ['available'], String? deliveryNoteNumber});

    /// Belirli bir paletteki ürünleri ve miktarlarını getirir.
    Future<List<ProductItem>> getPalletContents(String palletBarcode, int? locationId, {String stockStatus = 'available', int? siparisId, String? deliveryNoteNumber});

    Future<void> recordTransferOperation(
        TransferOperationHeader header,
        List<TransferItemDetail> items,
        // DÜZELTME: Kaynak lokasyon artık nullable.
        int? sourceLocationId,
        int targetLocationId,
        );

    /// Transfer için uygun (Kısmi/Tam Kabul) siparişleri getirir.
    Future<List<PurchaseOrder>> getOpenPurchaseOrdersForTransfer();

    /// ANA GÜNCELLEME: Belirli bir lokasyondaki veya sanal mal kabul alanındaki transfer edilebilir birimleri getirir.
    /// `orderId` null değilse, bu bir rafa kaldırma işlemidir ve sanal alandan (`locationId` null) veri çeker.
    /// `orderId` null ise, bu bir serbest transferdir ve belirtilen `locationId`'den veri çeker.
    /// `deliveryNoteNumber` serbest mal kabul için spesifik irsaliye numarası
    Future<List<TransferableContainer>> getTransferableContainers(int? locationId, {int? orderId, String? deliveryNoteNumber});

    /// Verilen sipariş ID'leri listesinden hangilerinin transfer edilebilir stoğu olduğunu kontrol eder.
    Future<Set<int>> getOrderIdsWithTransferableItems(List<int> orderIds);

    Future<MapEntry<String, int?>?> findLocationByCode(String code);

    Future<void> checkAndCompletePutaway(int orderId);

    Future<List<ProductInfo>> getProductInfoByBarcode(String barcode);

    Future<BoxItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']});

    /// Serbest mal kabullerin delivery note numberlarını getirir
    Future<List<String>> getFreeReceiptDeliveryNotes();

    /// Belirli bir sipariş için palet ile kabul edilmiş ürün var mı kontrol eder
    Future<bool> hasOrderReceivedWithPallets(int orderId);

    /// Belirli bir sipariş için kutular ile kabul edilmiş ürün var mı kontrol eder
    Future<bool> hasOrderReceivedWithBoxes(int orderId);

    /// İrsaliye numarasına göre mal kabul ID'sini getirir.
    Future<int?> getGoodsReceiptIdByDeliveryNote(String deliveryNoteNumber);
}
