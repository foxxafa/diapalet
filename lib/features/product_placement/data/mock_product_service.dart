import 'package:diapalet/features/product_placement/domain/product_repository.dart';

class MockProductRepository implements ProductRepository {
  @override
  Future<List<String>> getPallets() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return List.generate(5, (index) => 'Palet ${100 + index}');
  }

  @override
  Future<List<String>> getInvoices() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return List.generate(3, (index) => 'İrsaliye XYZ00${index + 1}');
  }

  @override
  Future<List<String>> getProducts() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return ['Ürün A', 'Ürün B', 'Laptop HP Spectre', 'Klavye Logitech MX', 'Monitor Dell 27"'];
  }

  @override
  Future<void> savePalletData(String? palletId, List<Map<String, dynamic>> products) async {
    await Future.delayed(const Duration(seconds: 1));
  }
}