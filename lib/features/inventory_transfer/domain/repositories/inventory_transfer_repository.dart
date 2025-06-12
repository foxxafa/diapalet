// lib/features/pallet_assignment/domain/repositories/pallet_repository.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';

abstract class InventoryTransferRepository {
  Future<List<String>> getSourceLocations();
  Future<List<String>> getTargetLocations();
  Future<List<String>> getPalletIdsAtLocation(String location);
  Future<List<BoxItem>> getBoxesAtLocation(String location);
  Future<List<ProductItem>> getPalletContents(String palletId);
  Future<void> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
}
