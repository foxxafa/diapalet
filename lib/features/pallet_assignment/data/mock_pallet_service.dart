// features/pallet_assignment/data/mock_pallet_service.dart
import 'package:flutter/foundation.dart'; // debugPrint için
import '../domain/pallet_repository.dart';

class MockPalletService implements PalletRepository {
  final List<String> _mockSourceLocations = [
    "RAF-A1-01", "RAF-A1-02", "YER-001", "DEPO-GİRİŞ-A", "ALAN-X"
  ];

  final List<String> _mockTargetLocations = [
    "RAF-B2-05", "RAF-C3-10", "SEVKİYAT-ALANI-1", "İADE-BÖLÜMÜ-X", "URETIM-HATTI-1"
  ];

  // Mock data for contents of specific pallets/boxes
  final Map<String, List<ProductItem>> _containerContents = {
    "PALET-A001": [
      ProductItem(id: 'prod1', name: 'Coca-Cola 1L', currentQuantity: 50),
      ProductItem(id: 'prod2', name: 'Fanta 1L', currentQuantity: 30),
    ],
    "PALET-B001": [
      ProductItem(id: 'prod3', name: 'Süt İçim 1L', currentQuantity: 100),
      ProductItem(id: 'prod4', name: 'Eti Karam Gofret 40g', currentQuantity: 200),
    ],
    "KUTU-X01": [
      ProductItem(id: 'prod1', name: 'Coca-Cola 1L', currentQuantity: 10),
      ProductItem(id: 'prod5', name: 'Super Widget (Demo)', currentQuantity: 5),
    ],
    "KUTU-Y01": [
      ProductItem(id: 'prod2', name: 'Fanta 1L', currentQuantity: 12),
    ],
  };


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
    // Simulate finding contents based on ID.
    // In a real app, you might have different maps or logic for pallets vs boxes if IDs overlap.
    if (_containerContents.containsKey(containerId)) {
      return List.from(_containerContents[containerId]!);
    }
    // Simulate a case where the pallet/box is known but empty, or just return empty if not found.
    // For example, if "PALET-EMPTY" is scanned:
    if (containerId == "PALET-EMPTY") return [];

    if (mode == AssignmentMode.palet && !containerId.startsWith("PALET-")) {
      return [
        ProductItem(id: 'demoProdA', name: 'Demo Palet Ürünü A', currentQuantity: 25),
        ProductItem(id: 'demoProdB', name: 'Demo Palet Ürünü B', currentQuantity: 15),
      ];
    }
    if (mode == AssignmentMode.kutu && !containerId.startsWith("KUTU-")) {
      return [
        ProductItem(id: 'demoProdC', name: 'Demo Kutu Ürünü C', currentQuantity: 8),
      ];
    }
    return []; // Default to empty if no specific match and no demo fallback triggered
  }

  @override
  Future<void> recordTransfer({
    required AssignmentMode mode,
    required String? sourceLocation,
    required String containerId,
    required String? targetLocation,
    required List<TransferItem> transferredItems,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    debugPrint('MockPalletService: Recording Transfer...');
    debugPrint('Mode: ${mode.displayName}');
    debugPrint('Source Location: $sourceLocation');
    debugPrint('Source Container ID: $containerId');
    debugPrint('Target Location: $targetLocation');
    debugPrint('Transferred Items (${transferredItems.length}):');
    for (var item in transferredItems) {
      debugPrint('  - Product: ${item.productName} (ID: ${item.productId}), Quantity: ${item.quantityToTransfer}');
    }
    debugPrint('Transfer recorded successfully (mock).');
    // Here you would typically interact with a backend or local database.
  }
}
