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
  inventoryStock,
  warehouseCount,
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
      case PendingOperationType.inventoryStock:
        return 'inventoryStock';
      case PendingOperationType.warehouseCount:
        return 'warehouseCount';
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
      case 'inventoryStock':
        return PendingOperationType.inventoryStock;
      case 'warehouseCount':
        return PendingOperationType.warehouseCount;
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
      case PendingOperationType.inventoryStock:
        return 'Inventory Stock Sync';
      case PendingOperationType.warehouseCount:
        return 'pending_operations.titles.warehouse_count'.tr();
    }
  }

  /// Force close order ve inventory stock işlemleri history'de gösterilmeyecek
  bool get shouldShowInHistory {
    return type != PendingOperationType.forceCloseOrder && 
           type != PendingOperationType.inventoryStock;
  }

  /// Inventory stock işlemleri pending listesinde gösterilmeyecek (internal sync operation)
  bool get shouldShowInPending {
    return type != PendingOperationType.inventoryStock;
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
        case PendingOperationType.inventoryStock:
          final stockCount = (dataMap['stocks'] as List?)?.length ?? 0;
          return 'Syncing $stockCount inventory stock records';
        case PendingOperationType.warehouseCount:
          final sheetNumber = dataMap['header']?['sheet_number'];
          final itemCount = (dataMap['items'] as List?)?.length ?? 0;
          return 'pending_operations.subtitles.warehouse_count'.tr(namedArgs: {
            'sheetNumber': sheetNumber?.toString() ?? 'N/A',
            'count': itemCount.toString()
          });
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
    final effectiveDate = syncedAt ?? createdAt;
    final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(effectiveDate);
    final typeName = displayTitle.replaceAll(' ', '');
    
    String identifier = '';
    try {
      final dataMap = jsonDecode(data);
      switch (type) {
        case PendingOperationType.goodsReceipt:
          identifier = dataMap['header']?['po_id']?.toString() ?? '';
          break;
        case PendingOperationType.inventoryTransfer:
          // Try to get po_id from enriched data first, then fallback to original data
          identifier = dataMap['header']?['po_id']?.toString() ??
                      dataMap['header']?['container_id']?.toString() ?? '';
          break;
        case PendingOperationType.forceCloseOrder:
          identifier = dataMap['po_id']?.toString() ?? '';
          break;
        case PendingOperationType.inventoryStock:
          identifier = 'stock';
          break;
        case PendingOperationType.warehouseCount:
          identifier = dataMap['header']?['sheet_number']?.toString() ?? '';
          break;
      }
    } catch (e) {
      // Parsing error, ignore identifier
    }

    if (identifier.isNotEmpty) {
      return '${typeName}_${identifier}_$formattedDate.pdf';
    }
    
    return '${typeName}_$formattedDate.pdf';
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