
import 'package:diapalet/features/inventory_inquiry/domain/entities/product_location.dart';

abstract class InventoryInquiryRepository {
  Future<List<ProductLocation>> findProductLocationsByBarcode(String barcode);
  Future<List<ProductLocation>> searchProductLocationsByStockCode(String query);
  Future<List<Map<String, dynamic>>> getProductSuggestions(String query);
} 