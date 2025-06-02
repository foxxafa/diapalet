import 'package:diapalet/features/product_placement/domain/product_repository.dart';

class MockProductRepository implements ProductRepository {
  @override
  Future<List<String>> getPallets() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return ['Palet #1', 'Palet #2', 'Palet #3'];
  }

  @override
  Future<List<String>> getInvoices() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      'İrsaliye 24.05.2024/001',
      'İrsaliye 24.05.2024/002',
      'İrsaliye 24.05.2024/003',
    ];
  }

  @override
  Future<List<String>> getProducts() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      'Coca-Cola 1L',
      'Fanta 1L',
      'Eti Karam Gofret 40g',
      'Ülker Çikolatalı Gofret 35g',
      'Şampuan Elidor 500ml',
      'Fairy Bulaşık Deterjanı 1L',
      'Süt İçim 1L',
      'Bebek Bezi Prima 4 Numara',
    ];
  }

  @override
  Future<void> savePalletData(String? palletId, List<Map<String, dynamic>> products) async {
    await Future.delayed(const Duration(seconds: 1));
  }
}