// lib/core/sync/pending_operation.dart
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

enum PendingOperationType {
  goodsReceipt,
  inventoryTransfer,
  forceCloseOrder,
}

extension PendingOperationTypeExtension on PendingOperationType {
  String get apiName {
    switch (this) {
      case PendingOperationType.goodsReceipt:
        return 'goodsReceipt';
      case PendingOperationType.inventoryTransfer:
        return 'inventoryTransfer';
      case PendingOperationType.forceCloseOrder:
        return 'forceCloseOrder';
    }
  }

  static PendingOperationType fromString(String type) {
    switch (type) {
      case 'goodsReceipt':
        return PendingOperationType.goodsReceipt;
      case 'inventoryTransfer':
        return PendingOperationType.inventoryTransfer;
      case 'forceCloseOrder':
        return PendingOperationType.forceCloseOrder;
      default:
        throw ArgumentError('Unknown pending operation type: $type');
    }
  }
}

@immutable
class PendingOperation {
  final int? id;
  final PendingOperationType type;
  final String data;
  final DateTime createdAt;
  final String status;
  final String? errorMessage;
  // YENİ: İşlemin ne zaman senkronize olduğunu takip etmek için eklendi.
  final DateTime? syncedAt;

  const PendingOperation({
    this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.status = 'pending',
    this.errorMessage,
    this.syncedAt,
  });

  String get displayTitle {
    switch (type) {
      case PendingOperationType.goodsReceipt:
        return 'pending_operations.titles.goods_receipt'.tr();
      case PendingOperationType.inventoryTransfer:
        return 'pending_operations.titles.inventory_transfer'.tr();
      case PendingOperationType.forceCloseOrder:
        return 'pending_operations.titles.force_close_order'.tr();
    }
  }

  String get displaySubtitle {
    try {
      final dataMap = jsonDecode(data);
      switch (type) {
        case PendingOperationType.goodsReceipt:
          final poId = dataMap['header']?['po_id'];
          final siparisId = dataMap['header']?['siparis_id'];
          final itemCount = (dataMap['items'] as List?)?.length ?? 0;
          
          // Eğer gerçek PO ID varsa göster, yoksa sadece item sayısını göster
          if (poId != null && poId.toString().isNotEmpty) {
            return 'pending_operations.subtitles.goods_receipt_with_po'
                .tr(namedArgs: {'poId': poId.toString(), 'count': itemCount.toString()});
          } else {
            return 'pending_operations.subtitles.goods_receipt'
                .tr(namedArgs: {'count': itemCount.toString()});
          }
        case PendingOperationType.inventoryTransfer:
          final source = dataMap['header']?['source_location_name'] ?? dataMap['header']?['source_location_id'];
          final target = dataMap['header']?['target_location_name'] ?? dataMap['header']?['target_location_id'];
          final itemCount = (dataMap['items'] as List?)?.length ?? 0;
          return 'pending_operations.subtitles.inventory_transfer'.tr(namedArgs: {
            'source': source.toString(),
            'target': target.toString(),
            'count': itemCount.toString()
          });
        case PendingOperationType.forceCloseOrder:
          final poId = dataMap['po_id'];
          final siparisId = dataMap['siparis_id'];
          
          // Eğer gerçek PO ID varsa göster
          if (poId != null && poId.toString().isNotEmpty) {
            return 'pending_operations.subtitles.force_close_order_with_po'
                .tr(namedArgs: {'poId': poId.toString()});
          } else {
            return 'pending_operations.subtitles.force_close_order'.tr();
          }
      }
    } catch (e) {
      return 'pending_operations.subtitles.parsing_error'.tr();
    }
  }

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation(
      id: map['id'],
      type: PendingOperationType.values.firstWhere((e) => e.name == map['type']),
      data: map['data'],
      createdAt: DateTime.parse(map['created_at']),
      status: map['status'],
      errorMessage: map['error_message'],
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
      'error_message': errorMessage,
      'synced_at': syncedAt?.toIso8601String(),
    };
  }
}