// lib/features/pallet_assignment/domain/repositories/pallet_repository.dart
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';

abstract class PalletAssignmentRepository {
  Future<List<String>> getSourceLocations();
  Future<List<String>> getTargetLocations();
  Future<List<ProductItem>> getContentsOfContainer(String containerId, AssignmentMode mode);

  Future<int> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);

  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations();
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId);
  Future<void> markTransferOperationAsSynced(int operationId);
  Future<void> updateContainerLocation(String containerId, String newLocation);
  Future<String?> getContainerLocation(String containerId);
  Future<void> synchronizePendingTransfers();
}
