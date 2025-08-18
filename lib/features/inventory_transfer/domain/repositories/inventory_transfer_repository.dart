// lib/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_stock_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';

abstract class InventoryTransferRepository {
    Future<Map<String, int?>> getSourceLocations({bool includeReceivingArea = true});
    Future<Map<String, int?>> getTargetLocations({bool excludeReceivingArea = false});

    // GÜNCELLEME: Bu iki metod yerine daha genel bir metod kullanılacak.
    Future<List<String>> getPalletIdsAtLocation(int? locationId, {List<String> stockStatuses = const ['available'], String? deliveryNoteNumber});
    Future<List<ProductStockItem>> getProductsAtLocation(int? locationId, {List<String> stockStatuses = const ['available'], String? deliveryNoteNumber});

    /// @deprecated Use getProductsAtLocation instead
    @Deprecated('Use getProductsAtLocation instead')
    Future<List<ProductStockItem>> getBoxesAtLocation(int? locationId, {List<String> stockStatuses = const ['available'], String? deliveryNoteNumber});

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

    Future<ProductStockItem?> findProductByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']});

    /// @deprecated Use findProductByCodeAtLocation instead
    @Deprecated('Use findProductByCodeAtLocation instead')
    Future<ProductStockItem?> findBoxByCodeAtLocation(String productCodeOrBarcode, int? locationId, {List<String> stockStatuses = const ['available']});

    /// Serbest mal kabullerin delivery note numberlarını getirir
    Future<List<String>> getFreeReceiptDeliveryNotes();

    /// Free receipt'lerin detaylı bilgilerini getirir (put-away için)
    Future<List<Map<String, dynamic>>> getFreeReceiptsForPutaway();

    /// Belirli bir sipariş için palet ile kabul edilmiş ürün var mı kontrol eder
    Future<bool> hasOrderReceivedWithPallets(int orderId);

    /// Belirli bir sipariş için ürün olarak kabul edilmiş ürün var mı kontrol eder
    Future<bool> hasOrderReceivedWithProducts(int orderId);

    /// İrsaliye numarasına göre mal kabul ID'sini getirir.
    Future<int?> getGoodsReceiptIdByDeliveryNote(String deliveryNoteNumber);

    /// Context-aware product search for transfers
    /// - If orderId provided: Search products related to that order
    /// - If deliveryNoteNumber provided: Search products from that delivery note
    /// - If locationId provided: Search products at that location
    /// - Otherwise: Search all available products
    Future<List<ProductInfo>> searchProductsForTransfer(String query, {
      int? orderId,
      String? deliveryNoteNumber, 
      int? locationId,
      List<String> stockStatuses = const ['available', 'receiving']
    });
}
