abstract class ProductRepository {
  Future<List<String>> getPallets();
  Future<List<String>> getInvoices();
  Future<List<String>> getProducts();
  Future<void> savePalletData(String? palletId, List<Map<String, dynamic>> products);
}