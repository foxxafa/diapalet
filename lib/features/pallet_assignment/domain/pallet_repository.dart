// features/pallet_assignment/domain/pallet_repository.dart

enum AssignmentMode { palet, kutu }

extension AssignmentModeExtension on AssignmentMode {
  String get displayName {
    switch (this) {
      case AssignmentMode.palet:
        return 'Palet';
      case AssignmentMode.kutu:
        return 'Kutu';
      default:
        return '';
    }
  }
}

// Represents a product item with its details and current quantity on a container.
class ProductItem {
  final String id; // Unique ID for the product
  final String name;
  final int currentQuantity; // Current quantity available on the source container

  ProductItem({
    required this.id,
    required this.name,
    required this.currentQuantity,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ProductItem &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// Represents an item and the quantity to be transferred.
class TransferItem {
  final String productId;
  final String productName;
  final int quantityToTransfer;

  TransferItem({
    required this.productId,
    required this.productName,
    required this.quantityToTransfer,
  });
}

abstract class PalletRepository {
  Future<List<String>> getSourceLocations();
  Future<List<String>> getTargetLocations();

  /// Fetches the list of products and their current quantities on a specific container.
  Future<List<ProductItem>> getContentsOfContainer(String containerId, AssignmentMode mode);

  /// Saves the transfer operation.
  Future<void> recordTransfer({
    required AssignmentMode mode,
    required String? sourceLocation,
    required String containerId, // The ID of the pallet/box being sourced from
    required String? targetLocation,
    required List<TransferItem> transferredItems, // List of products and quantities being moved
  });
}
