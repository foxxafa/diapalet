// lib/features/pallet_assignment/domain/entities/transfer_operation_header.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override
import 'assignment_mode.dart'; // Correct import

@immutable
class TransferOperationHeader {
  final int? id;
  final AssignmentMode operationType;
  final int sourceLocationId;
  final int targetLocationId;
  final String? containerId;
  final DateTime transferDate;
  final int synced;

  const TransferOperationHeader({
    this.id,
    required this.operationType,
    required this.sourceLocationId,
    required this.targetLocationId,
    this.containerId,
    required this.transferDate,
    this.synced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation_type': operationType.name,
      'source_location_id': sourceLocationId,
      'target_location_id': targetLocationId,
      'pallet_id': containerId,
      'transfer_date': transferDate.toIso8601String(),
      'synced': synced,
    };
  }

  factory TransferOperationHeader.fromMap(Map<String, dynamic> map) {
    return TransferOperationHeader(
      id: map['id'],
      operationType: (map['operation_type'] as String) == AssignmentMode.pallet.name
          ? AssignmentMode.pallet
          : AssignmentMode.box,
      sourceLocationId: map['source_location_id'],
      targetLocationId: map['target_location_id'],
      containerId: map['pallet_id'],
      transferDate: DateTime.parse(map['transfer_date'] as String),
      synced: map['synced'] as int? ?? 0,
    );
  }

  TransferOperationHeader copyWith({
    int? id,
    AssignmentMode? operationType,
    int? sourceLocationId,
    int? targetLocationId,
    String? containerId,
    DateTime? transferDate,
    int? synced,
  }) {
    return TransferOperationHeader(
      id: id ?? this.id,
      operationType: operationType ?? this.operationType,
      sourceLocationId: sourceLocationId ?? this.sourceLocationId,
      targetLocationId: targetLocationId ?? this.targetLocationId,
      containerId: containerId ?? this.containerId,
      transferDate: transferDate ?? this.transferDate,
      synced: synced ?? this.synced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TransferOperationHeader &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              operationType == other.operationType &&
              sourceLocationId == other.sourceLocationId &&
              targetLocationId == other.targetLocationId &&
              containerId == other.containerId &&
              transferDate.isAtSameMomentAs(other.transferDate) && // For DateTime comparison
              synced == other.synced;

  @override
  int get hashCode =>
      id.hashCode ^
      operationType.hashCode ^
      sourceLocationId.hashCode ^
      targetLocationId.hashCode ^
      containerId.hashCode ^
      transferDate.hashCode ^
      synced.hashCode;

  Map<String, dynamic> toMapForDb() {
    return {
      'operation_type': operationType.name,
      'source_location_id': sourceLocationId,
      'target_location_id': targetLocationId,
      'pallet_id': containerId,
      'transfer_date': transferDate.toIso8601String(),
      'synced': synced,
    };
  }
}
