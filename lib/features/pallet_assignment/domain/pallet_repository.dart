abstract class PalletRepository {
  List<String> getPalletList();
  List<ProductItem> getPalletProducts(String palletName);
}

class ProductItem {
  final String name;
  final int quantity;
  ProductItem({required this.name, required this.quantity});
}
