// lib/features/pallet_assignment/data/mock_pallet_service.dart
import 'package:flutter/foundation.dart';

// Ensure all imports use the absolute package path for consistency
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
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
    "KUTU-X01": [ // Kutu için ProductItem'da id alanı productId'yi temsil eder.
      const ProductItem(id: 'prod1_kutu_x01', name: 'Coca-Cola 1L (Kutu)', productCode: 'COLA1L', currentQuantity: 10),
    ],
    "KUTU-Y01": [
      const ProductItem(id: 'prod2_kutu_y01', name: 'Fanta 1L (Kutu)', productCode: 'FANTA1L', currentQuantity: 12),
    ],
    "XYZ123": [
      const ProductItem(id: 'prod7', name: 'Genel Ürün Alpha', productCode: 'GENALPHA', currentQuantity: 75),
      const ProductItem(id: 'prod8', name: 'Genel Ürün Beta', productCode: 'GENBETA', currentQuantity: 60),
    ]
  };

  // For getContainerIdsAtLocation mock
  final Map<String, List<String>> _locationContainerPallets = {
    "RAF-A1-01": ["PALET-A001", "PALET-C003"],
    "SEVKİYAT-ALANI-1": ["PALET-B001"],
  };
  final Map<String, List<String>> _locationContainerBoxes = {
    "DEPO-GİRİŞ-A": ["KUTU-X01", "KUTU-Z05"],
    "URETIM-HATTI-1": ["KUTU-Y01"],
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
  Future<List<ProductItem>> getProductInfo(String productId, String location) async {
    debugPrint("MockPalletService: Fetching product info for $productId at $location");
    await Future.delayed(const Duration(milliseconds: 300));

    if (_containerContents.containsKey(productId)) {
      return List.from(_containerContents[productId]!);
    }
    if (productId == "PALET-EMPTY" || productId == "KUTU-EMPTY") return [];
    debugPrint("MockPalletService: No content found for $productId, returning empty list.");
    return [];
  }

  @override
  Future<List<String>> getProductIdsAtLocation(String location) async {
    debugPrint("MockPalletService: Fetching product IDs at location: $location");
    await Future.delayed(const Duration(milliseconds: 200));
    final pallets = _locationContainerPallets[location] ?? [];
    final boxes = _locationContainerBoxes[location] ?? [];
    return [...pallets, ...boxes];
  }

  @override
  Future<int> recordTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    debugPrint('MockPalletService: Recording Transfer Operation...');
    await Future.delayed(const Duration(milliseconds: 200));

    final newHeader = header.copyWith(
      id: _nextTransferOpId,
    );
    _savedTransferHeaders.add(newHeader);

    List<TransferItemDetail> newItemsWithCorrectOpId = [];
    for (var item in items) {
      // Mock servisinde, ProductItem'dan gelen 'id'yi productId olarak kullanıyoruz.
      // Gerçek senaryoda, bu productId'nin transfer edilen ürünün gerçek ID'si olması gerekir.
      // Eğer items listesi zaten doğru productId ile geliyorsa (ki PalletAssignmentScreen'den öyle geliyor olmalı),
      // item.productId doğrudan kullanılabilir.
      newItemsWithCorrectOpId.add(TransferItemDetail(
        id: _nextTransferItemId++,
        operationId: newHeader.id!,
        productId: item.productId, // HATA BURADAYDI, item.productId KULLANILMALI (Bu yorum daha önceki bir düzeltmeye ait olabilir)
        productCode: item.productCode,
        productName: item.productName,
        quantity: item.quantity,
      ));
    }
    _savedTransferItems[newHeader.id!] = newItemsWithCorrectOpId;

    debugPrint('Mock Saved Transfer - ID: ${newHeader.id}, Mode: ${newHeader.operationType.displayName}, Synced: ${newHeader.synced}');
    debugPrint('  Source: ${newHeader.sourceLocation}');
    debugPrint('  Target: ${newHeader.targetLocation}');
    debugPrint('  Items (${newItemsWithCorrectOpId.length}):');
    for (var item in newItemsWithCorrectOpId) {
      debugPrint('    - ProductID: ${item.productId}, Name: ${item.productName} (Code: ${item.productCode}), Qty: ${item.quantity}, OpID: ${item.operationId}');
    }

    // Eğer kutu transferi ise, kaynak kutudaki miktarı azalt (mock için)
    if (header.operationType == AssignmentMode.kutu && items.isNotEmpty) {
      final transferredItemDetail = items.first;
      final sourceId = header.sourceLocation;
      if (_containerContents.containsKey(sourceId)) {
        final productInSource = _containerContents[sourceId]!.firstWhere(
                (p) => p.productCode == transferredItemDetail.productCode,
            orElse: () => const ProductItem(id: 'not-found', name: 'Not Found', productCode: 'N/A', currentQuantity: 0) // Dummy item
        );
        if (productInSource.productCode != 'N/A') {
          final newQuantity = productInSource.currentQuantity - transferredItemDetail.quantity;
          _containerContents[sourceId] = [
            ProductItem(
                id: productInSource.id, // Orjinal product id'sini koru
                name: productInSource.name,
                productCode: productInSource.productCode,
                currentQuantity: newQuantity >= 0 ? newQuantity : 0
            )
          ];
          debugPrint("Mock Kutu Transferi: Kaynak $sourceId içindeki ${productInSource.name} miktarı ${transferredItemDetail.quantity} azaltıldı. Yeni miktar: ${newQuantity >= 0 ? newQuantity : 0}");
        }
      }
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
  Future<void> synchronizePendingTransfers() async {
    debugPrint("MockPalletService: Synchronizing pending transfers.");
    await Future.delayed(const Duration(milliseconds: 50));
    for (final header in _savedTransferHeaders.where((op) => op.synced == 0)) {
      if (header.id != null) {
        debugPrint("MockPalletService: Simulating API sync for transfer ID ${header.id}");
        await markTransferOperationAsSynced(header.id!);
      }
    }
    debugPrint("MockPalletService: Synchronization complete.");
  }
}
