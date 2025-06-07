// lib/features/pallet_assignment/domain/entities/transfer_operation_header.dart
import 'package:flutter/foundation.dart'; // For @immutable and @override
import 'assignment_mode.dart'; // Correct import

@immutable
class TransferOperationHeader {
  final int? id;
  final AssignmentMode operationType;
  final String sourceLocation;
  final String targetLocation;
  final DateTime transferDate;
  final int synced;

  const TransferOperationHeader({
    this.id,
    required this.operationType,
    required this.sourceLocation,
    required this.targetLocation,
    required this.transferDate,
    this.synced = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation_type': operationType.name,
      'source_location': sourceLocation,
      'target_location': targetLocation,
      'transfer_date': transferDate.toIso8601String(),
      'synced': synced,
    };
  }

  factory TransferOperationHeader.fromMap(Map<String, dynamic> map) {
    return TransferOperationHeader(
      id: map['id'] as int?,
      operationType: AssignmentMode.values.firstWhere(
            (e) => e.name == map['operation_type'],
        orElse: () => AssignmentMode.palet, // Defaulting, consider error handling
      ),
      sourceLocation: map['source_location'] as String? ?? '',
      targetLocation: map['target_location'] as String? ?? '',
      transferDate: DateTime.parse(map['transfer_date'] as String),
      synced: map['synced'] as int? ?? 0,
    );
  }

  TransferOperationHeader copyWith({
    int? id,
    AssignmentMode? operationType,
    String? sourceLocation,
    String? targetLocation,
    DateTime? transferDate,
    int? synced,
  }) {
    return TransferOperationHeader(
      id: id ?? this.id,
      operationType: operationType ?? this.operationType,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      targetLocation: targetLocation ?? this.targetLocation,
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
              sourceLocation == other.sourceLocation &&
              targetLocation == other.targetLocation &&
              transferDate.isAtSameMomentAs(other.transferDate) && // For DateTime comparison
              synced == other.synced;

  @override
  int get hashCode =>
      id.hashCode ^
      operationType.hashCode ^
      sourceLocation.hashCode ^
      targetLocation.hashCode ^
      transferDate.hashCode ^
      synced.hashCode;
}
