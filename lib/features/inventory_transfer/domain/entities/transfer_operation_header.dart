// lib/features/pallet_assignment/domain/entities/transfer_operation_header.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override
import 'assignment_mode.dart'; // Correct import
import 'package:equatable/equatable.dart';

@immutable
class TransferOperationHeader extends Equatable {
  final int? id;
  final AssignmentMode operationType;
  final String sourceLocationName;
  final String targetLocationName;
  final String? containerId;
  final DateTime transferDate;
  final int synced;

  const TransferOperationHeader({
    this.id,
    required this.operationType,
    required this.sourceLocationName,
    required this.targetLocationName,
    this.containerId,
    required this.transferDate,
    this.synced = 0,
  });

  @override
  List<Object?> get props => [id, operationType, sourceLocationName, targetLocationName, containerId, transferDate, synced];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation_type': operationType.name,
      'source_location_name': sourceLocationName,
      'target_location_name': targetLocationName,
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
      sourceLocationName: map['source_location_name'],
      targetLocationName: map['target_location_name'],
      containerId: map['pallet_id'],
      transferDate: DateTime.parse(map['transfer_date'] as String),
      synced: map['synced'] as int? ?? 0,
    );
  }

  TransferOperationHeader copyWith({
    int? id,
    AssignmentMode? operationType,
    String? sourceLocationName,
    String? targetLocationName,
    String? containerId,
    DateTime? transferDate,
    int? synced,
  }) {
    return TransferOperationHeader(
      id: id ?? this.id,
      operationType: operationType ?? this.operationType,
      sourceLocationName: sourceLocationName ?? this.sourceLocationName,
      targetLocationName: targetLocationName ?? this.targetLocationName,
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
              sourceLocationName == other.sourceLocationName &&
              targetLocationName == other.targetLocationName &&
              containerId == other.containerId &&
              transferDate.isAtSameMomentAs(other.transferDate) && // For DateTime comparison
              synced == other.synced;

  @override
  int get hashCode =>
      id.hashCode ^
      operationType.hashCode ^
      sourceLocationName.hashCode ^
      targetLocationName.hashCode ^
      containerId.hashCode ^
      transferDate.hashCode ^
      synced.hashCode;

  Map<String, dynamic> toMapForDb() {
    return {
      'operation_type': operationType.name,
      'source_location_name': sourceLocationName,
      'target_location_name': targetLocationName,
      'pallet_id': containerId,
      'transfer_date': transferDate.toIso8601String(),
      'synced': synced,
    };
  }
}
