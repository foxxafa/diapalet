// lib/features/goods_receiving/domain/repositories/goods_receiving_repository.dart
import '../entities/product_info.dart';
import '../entities/goods_receipt_log_item.dart';

abstract class GoodsReceivingRepository {
  Future<List<String>> getInvoices();
  Future<List<String>> getPalletsForDropdown(); // Palet ID/isim listesi
  Future<List<String>> getBoxesForDropdown();   // Kutu ID/isim listesi
  Future<List<ProductInfo>> getProductsForDropdown(); // Ürün listesi (ProductInfo olarak)

  Future<void> saveGoodsReceiptLog(List<GoodsReceiptLogItem> items, ReceiveMode mode);
}
