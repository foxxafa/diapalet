// lib/features/goods_receiving/domain/repositories/goods_receiving_repository.dart

import '../entities/product_info.dart';
import '../entities/received_product_item.dart';

/// Abstract repository for goods receiving operations.
/// This defines the contract for data handling, allowing for different
/// implementations (e.g., mock data, real API).
abstract class GoodsReceivingRepository {
  /// Fetches product details based on a given barcode.
  /// Returns [ProductInfo] if found, otherwise null or throws an error.
  Future<ProductInfo?> getProductDetailsByBarcode(String barcode);

  /// Fetches a list of available units (e.g., "BOX", "PCS").
  Future<List<String>> getAvailableUnits();

  /// Saves a list of received product items.
  Future<void> saveReceivedProducts(List<ReceivedProductItem> items);
}
