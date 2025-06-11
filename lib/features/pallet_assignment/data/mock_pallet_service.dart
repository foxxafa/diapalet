// lib/features/pallet_assignment/data/mock_pallet_service.dart
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:flutter/foundation.dart';

// Ensure all imports use the absolute package path for consistency
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';

class MockPalletService implements PalletAssignmentRepository {
  final List<LocationInfo> _mockLocations = [
    const LocationInfo(id: 1, name: "DEPO-GİRİŞ-A", code: "DGA"),
    const LocationInfo(id: 2, name: "RAF-A1-01", code: "A101"),
    const LocationInfo(id: 3, name: "SEVKİYAT-ALANI-1", code: "SEVK1"),
    const LocationInfo(id: 4, name: "İADE-BÖLÜMÜ-X", code: "IADE-X"),
    const LocationInfo(id: 5, name: "URETIM-HATTI-1", code: "URETIM1"),
  ];

  final Map<String, List<ProductItem>> _containerContents = {
    "PALET-A001": [
      const ProductItem(id: 101, name: 'Coca-Cola 1L', productCode: 'COLA1L', currentQuantity: 50),
      const ProductItem(id: 102, name: 'Fanta 1L', productCode: 'FANTA1L', currentQuantity: 30),
    ],
    "PALET-B001": [
      const ProductItem(id: 201, name: 'Süt İçim 1L', productCode: 'ICIM1L', currentQuantity: 100),
    ],
    // Box contents are now identified by an integer ID (from inventory_stock table)
    "1": [ 
      const ProductItem(id: 101, name: 'Coca-Cola 1L (Kutu)', productCode: 'COLA1L', currentQuantity: 10),
    ],
    "2": [
      const ProductItem(id: 102, name: 'Fanta 1L (Kutu)', productCode: 'FANTA1L', currentQuantity: 12),
    ],
  };

  // Maps location ID to a list of container IDs (pallets are strings, boxes are int strings)
  final Map<int, List<String>> _locationContainers = {
    1: ["1"], // DEPO-GİRİŞ-A has one box
    2: ["PALET-A001"], // RAF-A1-01 has one pallet
    3: ["PALET-B001", "2"], // SEVKİYAT-ALANI-1 has a pallet and a box
  };

  final List<TransferOperationHeader> _savedTransferHeaders = [];
  final Map<int, List<TransferItemDetail>> _savedTransferItems = {};
  int _nextTransferOpId = 1;
  int _nextTransferItemId = 1;

  @override
  Future<List<LocationInfo>> getSourceLocations() async {
    debugPrint("MockPalletService: Fetching source locations.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockLocations);
  }

  @override
  Future<List<LocationInfo>> getTargetLocations() async {
    debugPrint("MockPalletService: Fetching target locations.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockLocations.where((l) => l.id != 1)); // Exclude source-only locations for variety
  }

  @override
  Future<List<ProductItem>> getContainerContent(String containerId) async {
    debugPrint("MockPalletService: Fetching product info for container: $containerId");
    await Future.delayed(const Duration(milliseconds: 300));
    return List.from(_containerContents[containerId] ?? []);
  }

  @override
  Future<List<String>> getContainerIdsByLocation(int locationId) async {
    debugPrint("MockPalletService: Fetching container IDs at location ID: $locationId");
    await Future.delayed(const Duration(milliseconds: 200));
    return _locationContainers[locationId] ?? [];
  }

  @override
  Future<List<BoxItem>> getBoxesAtLocation(int locationId) async {
    debugPrint("MockPalletService: Fetching boxes at location ID: $locationId");
    await Future.delayed(const Duration(milliseconds: 150));
    final containerIds = _locationContainers[locationId] ?? [];
    
    final boxIds = containerIds.where((id) => int.tryParse(id) != null).toList();

    List<BoxItem> boxItems = [];
    for (String boxIdStr in boxIds) {
        final content = _containerContents[boxIdStr] ?? [];
        if (content.isNotEmpty) {
           final product = content.first;
            boxItems.add(BoxItem(
              boxId: int.parse(boxIdStr),
              productId: product.id,
              productName: product.name,
              productCode: product.productCode,
              quantity: product.currentQuantity,
            ));
        }
    }
    return boxItems;
  }

  @override
  Future<int> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    debugPrint('MockPalletService: Recording Transfer Operation...');
    await Future.delayed(const Duration(milliseconds: 200));

    final newHeader = header.copyWith(id: _nextTransferOpId);
    _savedTransferHeaders.add(newHeader);

    final newItems = items.map((item) => TransferItemDetail(
      id: _nextTransferItemId++,
      operationId: newHeader.id!,
      productId: item.productId,
      productCode: item.productCode,
      productName: item.productName,
      quantity: item.quantity,
    )).toList();
    _savedTransferItems[newHeader.id!] = newItems;

    debugPrint('Mock Saved Transfer - ID: ${newHeader.id}, Mode: ${newHeader.operationType.name}, Synced: ${newHeader.synced}');
    debugPrint('  Source ID: ${newHeader.sourceLocationId}');
    debugPrint('  Target ID: ${newHeader.targetLocationId}');
    debugPrint('  Items (${newItems.length}):');
    for (var item in newItems) {
      debugPrint('    - ProductID: ${item.productId}, Name: ${item.productName}, Qty: ${item.quantity}');
    }
    
    _nextTransferOpId++;
    return newHeader.id!;
  }

  @override
  Future<List<TransferOperationHeader>> getUnsyncedTransferOperations() async {
    debugPrint("MockPalletService: Fetching unsynced transfer operations.");
    await Future.delayed(const Duration(milliseconds: 50));
    return _savedTransferHeaders.where((op) => op.synced == 0).toList();
  }

  @override
  Future<List<TransferItemDetail>> getTransferItemsForOperation(int operationId) async {
    debugPrint("MockPalletService: Fetching items for transfer operation ID: $operationId");
    await Future.delayed(const Duration(milliseconds: 50));
    return _savedTransferItems[operationId] ?? [];
  }

  @override
  Future<void> markTransferOperationAsSynced(int operationId) async {
    debugPrint("MockPalletService: Marking transfer operation ID: $operationId as synced.");
    await Future.delayed(const Duration(milliseconds: 50));
    final index = _savedTransferHeaders.indexWhere((op) => op.id == operationId);
    if (index != -1) {
      _savedTransferHeaders[index] = _savedTransferHeaders[index].copyWith(synced: 1);
    }
  }

  @override
  Future<void> synchronizePendingTransfers() async {
    debugPrint("MockPalletService: Synchronizing pending transfers.");
    await Future.delayed(const Duration(milliseconds: 50));
    for (final header in _savedTransferHeaders.where((op) => op.synced == 0)) {
      if (header.id != null) {
        debugPrint("MockPalletService: Simulating API sync for transfer ID ${header.id}");
        await markTransferOperationAsSynced(header.id!);
      }
    }
  }
}
