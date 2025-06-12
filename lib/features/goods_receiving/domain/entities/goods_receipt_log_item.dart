//features/goods_receiving/domain/entities/goods_receipt_log_item.dart
import 'package:equatable/equatable.dart';

class GoodsReceiptLogItem extends Equatable {
  final int id;
  final int urun_id;
  final String urun_name;
  final int location_id;
  final String location_name;
  final double quantity;
  final String? container_id; // Pallet barcode
  final String created_at;

  const GoodsReceiptLogItem({
    required this.id,
    required this.urun_id,
    required this.urun_name,
    required this.location_id,
    required this.location_name,
    required this.quantity,
    this.container_id,
    required this.created_at,
  });

  factory GoodsReceiptLogItem.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptLogItem(
      id: map['id'] as int,
      urun_id: map['urun_id'] as int,
      urun_name: map['urun_name'] as String,
      location_id: map['location_id'] as int,
      location_name: map['location_name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      container_id: map['container_id'] as String?,
      created_at: map['created_at'] as String,
    );
  }

  @override
  List<Object?> get props => [id, urun_id, location_id, quantity, container_id, created_at];
}
