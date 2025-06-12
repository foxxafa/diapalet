// lib/features/pallet_assignment/domain/repositories/pallet_repository.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';

abstract class InventoryTransferRepository {
  Future<List<String>> getSourceLocations();
  
  Future<List<String>> getTargetLocations();

  Future<List<String>> getPalletIdsAtLocation(String locationName);
  
  Future<List<BoxItem>> getBoxesAtLocation(String locationName);

  Future<List<ProductItem>> getPalletContents(String palletId);

  Future<void> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
}
