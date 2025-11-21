
import 'package:diapalet/features/inventory_inquiry/domain/entities/product_location.dart';

enum SuggestionSearchType { barcode, stockCode, productName, pallet }

abstract class InventoryInquiryRepository {
  Future<List<ProductLocation>> findProductLocationsByBarcode(String barcode);
  Future<List<ProductLocation>> searchProductLocationsByStockCode(String query);
  Future<List<ProductLocation>> searchProductLocationsByProductName(String query);
  Future<List<ProductLocation>> searchProductLocationsByPalletBarcode(String palletBarcode);
  Future<List<Map<String, dynamic>>> getProductSuggestions(String query, SuggestionSearchType searchType);
} 