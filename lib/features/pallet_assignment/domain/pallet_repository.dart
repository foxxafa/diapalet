// Örnek: features/pallet_assignment/domain/pallet_repository.dart
enum Mode { palet, kutu }

class ProductItem {
  final String id;
  final String name;
  final int quantity;

  ProductItem({required this.id, required this.name, required this.quantity});
}

abstract class PalletRepository {
  List<String> getPalletList();
  List<ProductItem> getPalletProducts(String palletName);

  List<String> getBoxList();
  List<ProductItem> getBoxProducts(String boxName);

  Future<void> saveAssignment(Map<String, dynamic> formData, Mode mode);
}