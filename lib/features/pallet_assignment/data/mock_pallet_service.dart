// File: features/pallet_assignment/data/mock_pallet_service.dart
import '../domain/pallet_repository.dart'; // Imports PalletRepository, ProductItem, and Mode

class MockPalletService implements PalletRepository {
  final Map<String, List<ProductItem>> _palletProducts = {
    'Palet #1': [
      ProductItem(id: 'p1_item1', name: 'Domates', quantity: 100),
      ProductItem(id: 'p1_item2', name: 'Salata', quantity: 50),
    ],
    'Palet #2': [
      ProductItem(id: 'p2_item1', name: 'Biber', quantity: 200),
      ProductItem(id: 'p2_item2', name: 'Patlıcan', quantity: 80),
    ],
    'Palet #3': [
      ProductItem(id: 'p3_item1', name: 'Elma', quantity: 120),
      ProductItem(id: 'p3_item2', name: 'Armut', quantity: 70),
      ProductItem(id: 'p3_item3', name: 'Sucuk', quantity: 50),
      ProductItem(id: 'p3_item4', name: 'Peynir', quantity: 20),
      ProductItem(id: 'p3_item5', name: 'Elma Tekrar', quantity: 120), // Assuming different ID if it's a distinct entry
      ProductItem(id: 'p3_item6', name: 'Armut Tekrar', quantity: 70),
      ProductItem(id: 'p3_item7', name: 'Sucuk Tekrar', quantity: 50),
      ProductItem(id: 'p3_item8', name: 'Peynir Tekrar', quantity: 20),
    ],
  };

  final Map<String, List<ProductItem>> _boxProducts = {
    'Kutu #A': [ProductItem(id: 'bA_item1', name: 'Şampuan', quantity: 30)],
    'Kutu #B': [ProductItem(id: 'bB_item1', name: 'Deterjan', quantity: 15)],
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
