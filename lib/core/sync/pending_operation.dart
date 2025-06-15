// lib/core/sync/pending_operation.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum PendingOperationType {
  goodsReceipt,
  inventoryTransfer,
}

@immutable
class PendingOperation {
  final int? id;
  final PendingOperationType type;
  final String data; // JSON string of the payload
  final DateTime createdAt;
  final String status;
  final int attempts;
  final String? errorMessage;

  const PendingOperation({
    this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.status = 'pending',
    this.attempts = 0,
    this.errorMessage,
  });

  /// Kullanıcı arayüzünde gösterilecek ana başlığı oluşturur.
  String get displayTitle {
    try {
      final jsonData = jsonDecode(data) as Map<String, dynamic>;
      switch (type) {
        case PendingOperationType.goodsReceipt:
          final header = jsonData['header'] as Map<String, dynamic>?;
          final poId = header?['invoice_number'] as String?;
          return poId != null && poId.isNotEmpty ? 'Mal Kabul: $poId' : 'Siparişe Bağlı Olmayan Mal Kabul';
        case PendingOperationType.inventoryTransfer:
          final header = jsonData['header'] as Map<String, dynamic>?;
          final operationType = header?['operation_type'] as String?;
          if (operationType == 'pallet_transfer') {
            return 'Palet Transferi';
          }
          return 'Envanter Transferi';
      }
    } catch (e) {
      return 'Bilinmeyen İşlem';
    }
  }

  /// Kullanıcı arayüzünde gösterilecek alt başlığı oluşturur.
  String get displaySubtitle {
    try {
      final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(createdAt);
      final jsonData = jsonDecode(data) as Map<String, dynamic>;
      final items = jsonData['items'] as List<dynamic>?;
      final itemCount = items?.length ?? 0;

      return '$itemCount kalem ürün | Tarih: $formattedDate';
    } catch (e) {
      debugPrint("displaySubtitle parse error: $e");
      return 'Detaylar okunamadı';
    }
  }

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation(
      id: map['id'],
      type: PendingOperationType.values.firstWhere(
            (e) => e.name == map['type'],
        orElse: () => throw ArgumentError('Unknown operation type: ${map['type']}'),
      ),
      data: map['data'],
      createdAt: DateTime.parse(map['created_at']),
      status: map['status'] as String,
      attempts: map['attempts'] as int,
      errorMessage: map['error_message'] as String?,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'type': type.name,
      'data': data,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'attempts': attempts,
      'error_message': errorMessage,
    };
  }
}
