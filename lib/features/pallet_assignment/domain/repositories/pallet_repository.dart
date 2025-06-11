// lib/features/pallet_assignment/domain/repositories/pallet_repository.dart
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';

abstract class PalletAssignmentRepository {
  Future<List<LocationInfo>> getSourceLocations();
  Future<List<LocationInfo>> getTargetLocations();
  Future<List<String>> getContainerIdsByLocation(int locationId);
  Future<List<ProductItem>> getContainerContent(String containerId);
  Future<List<BoxItem>> getBoxesAtLocation(int locationId);

  Future<int> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);

  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<void> markTransferOperationAsSynced(int operationId);
  Future<void> synchronizePendingTransfers();
}
