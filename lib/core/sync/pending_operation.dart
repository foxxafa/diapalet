// lib/core/sync/pending_operation.dart
import 'dart:convert';

class PendingOperation {
  // Primary key inside pending_operation table – handy for deletion
  final int id;
  // Optional reference to another local table (goods_receipt, transfer_operation)
  // kept for backward-compatibility but may be null if we only use the pending queue.
  final int? localId;
  final String operationType;
  final Map<String, dynamic> operationData;
  final DateTime createdAt;
  final String status;
  final int attempts;
  final String? errorMessage;
  final String tableName;

  PendingOperation({
    required this.id,
    this.localId,
    required this.operationType,
    required this.operationData,
    required this.createdAt,
    required this.status,
    this.attempts = 0,
    this.errorMessage,
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

  String get payloadSummary {
    try {
      final jsonString = jsonEncode(operationData);
      // To avoid overly long summaries, we can truncate or simplify.
      if (jsonString.length > 100) {
        return '${jsonString.substring(0, 97)}...';
      }
      return jsonString;
    } catch (e) {
      return 'Invalid payload data';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'local_id': localId,
      'operation_type': operationType,
      'operation_data': operationData,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'attempts': attempts,
      'error_message': errorMessage,
      'table_name': tableName,
    };
  }

  Map<String, dynamic> toUploadPayload() {
    return {
      'operation_type': operationType,
      'operationData': operationData,
    };
  }

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation(
      id: map['id'] as int,
      operationType: map['type'] as String,
      operationData: jsonDecode(map['data'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String? ?? 'pending',
      attempts: map['attempts'] as int? ?? 0,
      errorMessage: map['error_message'] as String?,
      tableName: 'pending_operation',
    );
  }

  factory PendingOperation.fromJson(Map<String, dynamic> json) {
    return PendingOperation(
      id: json['id'] as int,
      localId: json['local_id'] as int?,
      operationType: json['operation_type'] as String,
      operationData: Map<String, dynamic>.from(json['operation_data']),
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'pending',
      attempts: json['attempts'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
      tableName: json['table_name'] as String,
    );
  }
} 