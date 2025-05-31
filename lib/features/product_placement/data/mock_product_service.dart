// features/product_placement/data/mock_product_service.dart
import '../domain/product_repository.dart';

class MockProductService implements ProductRepository {
  @override
  Future<List<String>> getPallets() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return ['Palet A', 'Palet B', 'Palet C'];
  }

  @override
  Future<List<String>> getInvoices() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return ['İrsaliye 1', 'İrsaliye 2'];
  }

  @override
  Future<List<String>> getProducts() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return ['Gofret', 'Sucuk', 'Bal'];
  }
}
