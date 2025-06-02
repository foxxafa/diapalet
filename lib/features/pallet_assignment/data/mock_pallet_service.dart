// File: features/pallet_assignment/data/mock_pallet_service.dart
import '../domain/pallet_repository.dart'; // Imports PalletRepository, ProductItem, and Mode

class MockPalletService implements PalletRepository {
  final Map<String, List<ProductItem>> _palletProducts = {
    'Palet #1': [
      ProductItem(id: 'p1_1', name: 'Coca-Cola 1L', quantity: 120),
      ProductItem(id: 'p1_2', name: 'Fanta 1L', quantity: 80),
      ProductItem(id: 'p1_3', name: 'Süt İçim 1L', quantity: 60),
    ],
    'Palet #2': [
      ProductItem(id: 'p2_1', name: 'Fairy Bulaşık Deterjanı 1L', quantity: 100),
      ProductItem(id: 'p2_2', name: 'Bebek Bezi Prima 4 Numara', quantity: 30),
    ],
    'Palet #3': [
      ProductItem(id: 'p3_1', name: 'Şampuan Elidor 500ml', quantity: 96),
      ProductItem(id: 'p3_2', name: 'Eti Karam Gofret 40g', quantity: 240),
      ProductItem(id: 'p3_3', name: 'Ülker Çikolatalı Gofret 35g', quantity: 200),
      ProductItem(id: 'p3_4', name: 'Fairy Bulaşık Deterjanı 1L', quantity: 100),
      ProductItem(id: 'p3_5', name: 'Bebek Bezi Prima 4 Numara', quantity: 30),
    ],
  };

  final Map<String, List<ProductItem>> _boxProducts = {
    'Kutu #A': [
      ProductItem(id: 'bA_1', name: 'Coca-Cola 1L', quantity: 12),
      ProductItem(id: 'bA_2', name: 'Fanta 1L', quantity: 12),
    ],
    'Kutu #B': [
      ProductItem(id: 'bB_1', name: 'Şampuan Elidor 500ml', quantity: 6),
      ProductItem(id: 'bB_2', name: 'Fairy Bulaşık Deterjanı 1L', quantity: 4),
    ],
    'Kutu #C': [
      ProductItem(id: 'bC_1', name: 'Eti Karam Gofret 40g', quantity: 24),
      ProductItem(id: 'bC_2', name: 'Ülker Çikolatalı Gofret 35g', quantity: 20),
    ],
  };


  @override
  List<String> getPalletList() => _palletProducts.keys.toList();

  @override
  List<ProductItem> getPalletProducts(String palletName) =>
      _palletProducts[palletName] ?? [];

  @override
  List<String> getBoxList() => _boxProducts.keys.toList();

  @override
  List<ProductItem> getBoxProducts(String boxName) =>
      _boxProducts[boxName] ?? [];

  @override
  Future<void> saveAssignment(Map<String, dynamic> formData, Mode mode) async {
    // Simulate network delay or database operation
    await Future.delayed(const Duration(milliseconds: 500));
    print('MockPalletService: Saving assignment for ${mode.toString()}');
    print('Form Data: $formData');
    // In a real scenario, you would save this data to a database or backend API.
    // For this mock, we're just printing it.
  }
}
