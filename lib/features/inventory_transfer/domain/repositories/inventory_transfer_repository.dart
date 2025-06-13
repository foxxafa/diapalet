// lib/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';

abstract class InventoryTransferRepository {
  /// GÜNCELLEME: Lokasyonları artık {isim: id} formatında bir harita olarak döndürür.
  Future<Map<String, int>> getSourceLocations();

  /// GÜNCELLEME: Lokasyonları artık {isim: id} formatında bir harita olarak döndürür.
  Future<Map<String, int>> getTargetLocations();

  /// GÜNCELLEME: Parametre olarak artık lokasyon ID'si alır.
  Future<List<String>> getPalletIdsAtLocation(int locationId);

  /// GÜNCELLEME: Parametre olarak artık lokasyon ID'si alır.
  Future<List<BoxItem>> getBoxesAtLocation(int locationId);

  Future<List<ProductItem>> getPalletContents(String palletId);

  /// GÜNCELLEME: Metot, kaynak ve hedef lokasyon ID'lerini de parametre olarak alır.
  Future<void> recordTransferOperation(
      TransferOperationHeader header,
      List<TransferItemDetail> items,
      int sourceLocationId,
      int targetLocationId,
      );
}
