
import 'package:diapalet/features/inventory_inquiry/domain/entities/product_location.dart';

abstract class InventoryInquiryRepository {
  Future<List<ProductLocation>> findProductLocationsByBarcode(String barcode);
} 