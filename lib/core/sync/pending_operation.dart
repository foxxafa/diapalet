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
          final invoice = dataMap['header']?['invoice_number'];
          final poId = dataMap['header']?['siparis_id'];
          final itemCount = (dataMap['items'] as List?)?.length ?? 0;
          return 'pending_operations.subtitles.goods_receipt'
              .tr(namedArgs: {'poId': poId?.toString() ?? 'N/A', 'count': itemCount.toString()});
        case PendingOperationType.inventoryTransfer:
          final containerId = dataMap['header']?['container_id']?.toString() ?? 'N/A';
          final targetLocation = dataMap['header']?['target_location_id']?.toString() ?? 'N/A';
          final itemCount = (dataMap['items'] as List?)?.length ?? 0;
          return 'pending_operations.subtitles.inventory_transfer'.tr(namedArgs: {
            'containerId': containerId,
            'targetId': targetLocation,
            'count': itemCount.toString()
          });
        case PendingOperationType.forceCloseOrder:
          final poId = dataMap['siparis_id'];
          return 'pending_operations.subtitles.force_close_order'.tr(namedArgs: {'poId': poId?.toString() ?? 'N/A'});
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