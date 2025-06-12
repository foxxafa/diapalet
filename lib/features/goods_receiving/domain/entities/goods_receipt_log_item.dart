//features/goods_receiving/domain/entities/goods_receipt_log_item.dart
import 'package:equatable/equatable.dart';

class GoodsReceiptLogItem extends Equatable {
  final int id;
  final int urunId;
  final String urunName;
  final int locationId;
  final String locationName;
  final double quantity;
  final String? containerId; // Pallet barcode
  final String createdAt;

  const GoodsReceiptLogItem({
    required this.id,
    required this.urunId,
    required this.urunName,
    required this.locationId,
    required this.locationName,
    required this.quantity,
    this.containerId,
    required this.createdAt,
  });

  factory GoodsReceiptLogItem.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptLogItem(
      id: map['id'] as int,
      urunId: map['urun_id'] as int,
      urunName: map['urun_name'] as String,
      locationId: map['location_id'] as int,
      locationName: map['location_name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      containerId: map['container_id'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  @override
  List<Object?> get props => [id, urunId, urunName, locationId, locationName, quantity, containerId, createdAt];
}
