// lib/features/pallet_assignment/data/mock_pallet_service.dart
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';
import 'package:flutter/foundation.dart';

// Ensure all imports use the absolute package path for consistency
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';

class MockPalletService implements PalletAssignmentRepository {
  final List<String> _mockSourceLocations = [
    "RAF-A1-01", "RAF-A1-02", "YER-001", "DEPO-GİRİŞ-A", "ALAN-X", "10A21", "10B20"
  ];

  final List<String> _mockTargetLocations = [
    "RAF-B2-05", "RAF-C3-10", "SEVKİYAT-ALANI-1", "İADE-BÖLÜMÜ-X", "URETIM-HATTI-1"
  ];

  final Map<String, List<ProductItem>> _containerContents = {
    "PALET-A001": [
      const ProductItem(id: 'prod1', name: 'Coca-Cola 1L', productCode: 'COLA1L', currentQuantity: 50),
      const ProductItem(id: 'prod2', name: 'Fanta 1L', productCode: 'FANTA1L', currentQuantity: 30),
      const ProductItem(id: 'prod6', name: 'Sprite 1.5L', productCode: 'SPRITE15', currentQuantity: 24),
    ],
    "PALET-B001": [
      const ProductItem(id: 'prod3', name: 'Süt İçim 1L', productCode: 'ICIM1L', currentQuantity: 100),
      const ProductItem(id: 'prod4', name: 'Eti Karam Gofret 40g', productCode: 'ETIKARAM40', currentQuantity: 200),
    ],
    "KUTU-X01": [
      const ProductItem(id: 'prod1', name: 'Coca-Cola 1L', productCode: 'COLA1L', currentQuantity: 10),
      const ProductItem(id: 'prod5', name: 'Super Widget (Demo)', productCode: 'SWIDGET', currentQuantity: 5),
    ],
    "KUTU-Y01": [
      const ProductItem(id: 'prod2', name: 'Fanta 1L', productCode: 'FANTA1L', currentQuantity: 12),
    ],
    "XYZ123": [
      const ProductItem(id: 'prod7', name: 'Genel Ürün Alpha', productCode: 'GENALPHA', currentQuantity: 75),
      const ProductItem(id: 'prod8', name: 'Genel Ürün Beta', productCode: 'GENBETA', currentQuantity: 60),
    ]
  };

  final List<TransferOperationHeader> _savedTransferHeaders = [];
  final Map<int, List<TransferItemDetail>> _savedTransferItems = {};
  int _nextTransferOpId = 1;
  int _nextTransferItemId = 1;

  @override
  Future<List<String>> getSourceLocations() async {
    debugPrint("MockPalletService: Fetching source locations.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockSourceLocations);
  }

  @override
  Future<List<String>> getTargetLocations() async {
    debugPrint("MockPalletService: Fetching target locations.");
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockTargetLocations);
  }

  @override
  Future<List<ProductItem>> getContentsOfContainer(String containerId, AssignmentMode mode) async {
    debugPrint("MockPalletService: Fetching contents for ${mode.displayName} ID: $containerId");
    await Future.delayed(const Duration(milliseconds: 300));

    if (_containerContents.containsKey(containerId)) {
      return List.from(_containerContents[containerId]!);
    }
    if (containerId == "PALET-EMPTY" || containerId == "KUTU-EMPTY") return [];
    debugPrint("MockPalletService: No content found for $containerId, returning empty list.");
    return [];
  }

  @override
  Future<int> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    debugPrint('MockPalletService: Recording Transfer Operation...');
    await Future.delayed(const Duration(milliseconds: 200));

    final newHeader = header.copyWith(
      id: _nextTransferOpId,
      // synced status is preserved from the input 'header' by copyWith
    );
    _savedTransferHeaders.add(newHeader);

    List<TransferItemDetail> newItemsWithCorrectOpId = [];
    for (var item in items) {
      newItemsWithCorrectOpId.add(TransferItemDetail(
        id: _nextTransferItemId++,
        operationId: newHeader.id!,
        productCode: item.productCode,
        productName: item.productName,
        quantity: item.quantity,
      ));
    }
    _savedTransferItems[newHeader.id!] = newItemsWithCorrectOpId;

    debugPrint('Mock Saved Transfer - ID: ${newHeader.id}, Mode: ${newHeader.operationType.displayName}, Synced: ${newHeader.synced}');
    debugPrint('  Source: ${newHeader.sourceLocation} -> ${newHeader.containerId}');
    debugPrint('  Target: ${newHeader.targetLocation}');
    debugPrint('  Items (${newItemsWithCorrectOpId.length}):');
    for (var item in newItemsWithCorrectOpId) {
      debugPrint('    - ${item.productName} (Code: ${item.productCode}), Qty: ${item.quantity}, OpID: ${item.operationId}');
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
    } else {
      debugPrint("MockPalletService: Operation ID $operationId not found to mark as synced.");
    }
  }

  @override
  Future<void> updateContainerLocation(String containerId, String newLocation) async {
    debugPrint("MockPalletService: Updating container $containerId location to $newLocation (mock).");
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<String?> getContainerLocation(String containerId) async {
    debugPrint("MockPalletService: Getting container $containerId location (mock).");
    await Future.delayed(const Duration(milliseconds: 50));
    if (containerId == "PALET-A001") return "RAF-A1-01";
    if (containerId == "KUTU-X01" && _savedTransferHeaders.any((h) => h.containerId == "KUTU-X01" && h.targetLocation == "SEVKİYAT-ALANI-1")) {
      return "SEVKİYAT-ALANI-1";
    }
    return null;
  }
}
