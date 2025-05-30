class MockProductService {
  static Future<List<String>> getProducts() async {
    await Future.delayed(Duration(milliseconds: 500));
    return ['Sucuk', 'Bal', 'Gofret'];
  }
}
