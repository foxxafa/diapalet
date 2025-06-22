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
  final String data;
  final DateTime createdAt;
  final String status;
  final int attempts;
  final String? errorMessage;
  // YENİ: İşlemin ne zaman senkronize olduğunu takip etmek için eklendi.
  final DateTime? syncedAt;

  const PendingOperation({
    this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.status = 'pending',
    this.attempts = 0,
    this.errorMessage,
    this.syncedAt, // Constructor'a eklendi.
  });

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

  String get displaySubtitle {
    try {
      // Duruma göre oluşturulma veya senkronize olma tarihini göster.
      final dateToShow = status == 'synced' && syncedAt != null ? syncedAt! : createdAt;
      final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(dateToShow);
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
      type: PendingOperationType.values.firstWhere((e) => e.name == map['type']),
      data: map['data'],
      createdAt: DateTime.parse(map['created_at']),
      status: map['status'],
      attempts: map['attempts'],
      errorMessage: map['error_message'],
      // Veritabanından synced_at değerini oku.
      syncedAt: map['synced_at'] != null ? DateTime.parse(map['synced_at']) : null,
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
      // synced_at değerini veritabanına yaz.
      'synced_at': syncedAt?.toIso8601String(),
    };
  }
}