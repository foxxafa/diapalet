// features/pallet_assignment/data/mock_pallet_service.dart
import '../domain/pallet_repository.dart';

class MockPalletService implements PalletRepository {
  final Map<String, List<ProductItem>> _palletProducts = {
    'Palet #1': [
      ProductItem(name: 'Domates', quantity: 100),
      ProductItem(name: 'Salata', quantity: 50),
    ],
    'Palet #2': [
      ProductItem(name: 'Biber', quantity: 200),
      ProductItem(name: 'Patlıcan', quantity: 80),
    ],
    'Palet #3': [
      ProductItem(name: 'Elma', quantity: 120),
      ProductItem(name: 'Armut', quantity: 70),
      ProductItem(name: 'Sucuk', quantity: 50),
      ProductItem(name: 'Peynir', quantity: 20),
      ProductItem(name: 'Elma', quantity: 120),
      ProductItem(name: 'Armut', quantity: 70),
      ProductItem(name: 'Sucuk', quantity: 50),
      ProductItem(name: 'Peynir', quantity: 20),
    ],
  };

  @override
  List<String> getPalletList() => _palletProducts.keys.toList();

  @override
  List<ProductItem> getPalletProducts(String palletName) =>
      _palletProducts[palletName] ?? [];
}
