// lib/core/sync/pending_operation.dart
class PendingOperation {
  // Primary key inside pending_operation table – handy for deletion
  final int id;
  // Optional reference to another local table (goods_receipt, transfer_operation)
  // kept for backward-compatibility but may be null if we only use the pending queue.
  final int? localId;
  final String operationType;
  final Map<String, dynamic> operationData;
  final DateTime createdAt;
  final String tableName;

  PendingOperation({
    required this.id,
    this.localId,
    required this.operationType,
    required this.operationData,
    required this.createdAt,
    required this.tableName,
  });

  String get displayTitle {
    switch (operationType) {
      case 'goods_receipt':
        return 'Goods Receipt: ${operationData['invoice_number'] ?? 'Unknown'}';
      case 'pallet_transfer':
        return 'Pallet Transfer: ${operationData['source_location']} → ${operationData['target_location']}';
      case 'box_transfer':
        return 'Box Transfer: ${operationData['source_location']} → ${operationData['target_location']}';
      default:
        return 'Operation: $operationType';
    }
  }

  String get displaySubtitle {
    switch (operationType) {
      case 'goods_receipt':
        final items = operationData['items'] as List<dynamic>? ?? [];
        return '${items.length} items • ${operationData['receipt_date']}';
      case 'pallet_transfer':
      case 'box_transfer':
        final items = operationData['items'] as List<dynamic>? ?? [];
        return '${items.length} items • ${operationData['transfer_date']}';
      default:
        return 'Created: ${createdAt.toString().split(' ')[0]}';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'local_id': localId,
      'operation_type': operationType,
      'operation_data': operationData,
      'created_at': createdAt.toIso8601String(),
      'table_name': tableName,
    };
  }

  factory PendingOperation.fromJson(Map<String, dynamic> json) {
    return PendingOperation(
      id: json['id'] as int,
      localId: json['local_id'] as int?,
      operationType: json['operation_type'] as String,
      operationData: Map<String, dynamic>.from(json['operation_data']),
      createdAt: DateTime.parse(json['created_at'] as String),
      tableName: json['table_name'] as String,
    );
  }
} 