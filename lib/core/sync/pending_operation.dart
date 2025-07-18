// lib/core/sync/pending_operation.dart
import 'dart:convert';
import 'package:diapalet/core/services/pdf_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
  final String uniqueId;
  final PendingOperationType type;
  final String data;
  final DateTime createdAt;
  final String status;
  final String? errorMessage;
  final DateTime? syncedAt;

  const PendingOperation({
    this.id,
    String? uniqueId,
    required this.type,
    required this.data,
    required this.createdAt,
    this.status = 'pending',
    this.errorMessage,
    this.syncedAt,
  }) : uniqueId = uniqueId ?? '';

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

  /// Force close order işlemleri history'de gösterilmeyecek
  bool get shouldShowInHistory {
    return type != PendingOperationType.forceCloseOrder;
  }

  String get displaySubtitle {
    try {
      final dataMap = jsonDecode(data);
      switch (type) {
        case PendingOperationType.goodsReceipt:
          final poId = dataMap['header']?['po_id'];
          final itemCount = (dataMap['items'] as List?)?.length ?? 0;

          if (poId != null && poId.toString().isNotEmpty) {
            return 'pending_operations.subtitles.goods_receipt_with_po'
                .tr(namedArgs: {'poId': poId.toString(), 'count': itemCount.toString()});
          } else {
            return 'pending_operations.subtitles.goods_receipt'
                .tr(namedArgs: {'count': itemCount.toString()});
          }
        case PendingOperationType.inventoryTransfer:
          // Önce isimleri dene, yoksa "Kaynak" ve "Hedef" gibi anlamlı ifadeler kullan
          var source = dataMap['header']?['source_location_name'];
          var target = dataMap['header']?['target_location_name'];

          // Eğer isim yoksa ID'den anlamlı çeviri yap
          if (source == null) {
            final sourceId = dataMap['header']?['source_location_id'];
            if (sourceId == null || sourceId == 0) {
              source = '000';
            } else {
              source = 'Shelf $sourceId';
            }
          }

          if (target == null) {
            final targetId = dataMap['header']?['target_location_id'];
            target = targetId != null ? 'Shelf $targetId' : 'Unknown Target';
          }

          final itemCount = (dataMap['items'] as List?)?.length ?? 0;
          return 'pending_operations.subtitles.inventory_transfer'.tr(namedArgs: {
            'source': source.toString(),
            'target': target.toString(),
            'count': itemCount.toString()
          });
        case PendingOperationType.forceCloseOrder:
          final poId = dataMap['po_id'];

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

  /// Generates a PDF report for this pending operation
  Future<Uint8List> generatePdf() async {
    return await PdfService.generatePendingOperationPdf(operation: this);
  }

  /// Creates a filename for PDF export
  String get pdfFileName {
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(createdAt);
    final typePrefix = type.apiName.toUpperCase();

    try {
      final dataMap = jsonDecode(data);
      switch (type) {
        case PendingOperationType.goodsReceipt:
          final poId = dataMap['header']?['po_id'];
          if (poId != null && poId.toString().isNotEmpty) {
            return '${typePrefix}_${poId}_$formattedDate.pdf';
          }
          break;
        case PendingOperationType.inventoryTransfer:
          final containerId = dataMap['header']?['container_id'];
          if (containerId != null) {
            return '${typePrefix}_${containerId}_$formattedDate.pdf';
          }
          break;
        case PendingOperationType.forceCloseOrder:
          final poId = dataMap['po_id'];
          if (poId != null && poId.toString().isNotEmpty) {
            return '${typePrefix}_${poId}_$formattedDate.pdf';
          }
          break;
      }
    } catch (e) {
      debugPrint('Error creating PDF filename: $e');
    }

    return '${typePrefix}_${uniqueId.substring(0, 8)}_$formattedDate.pdf';
  }

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation.create(
      id: map['id'],
      uniqueId: map['unique_id'],
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
      'unique_id': uniqueId,
      'type': type.name,
      'data': data,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'error_message': errorMessage,
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  // Static method to create with UUID
  static PendingOperation create({
    int? id,
    String? uniqueId,
    required PendingOperationType type,
    required String data,
    required DateTime createdAt,
    String status = 'pending',
    String? errorMessage,
    DateTime? syncedAt,
  }) {
    return PendingOperation(
      id: id,
      uniqueId: uniqueId ?? const Uuid().v4(),
      type: type,
      data: data,
      createdAt: createdAt,
      status: status,
      errorMessage: errorMessage,
      syncedAt: syncedAt,
    );
  }
}