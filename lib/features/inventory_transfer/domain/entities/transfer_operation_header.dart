// lib/features/inventory_transfer/domain/entities/transfer_operation_header.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';

class TransferOperationHeader {
  final int employeeId;
  final DateTime transferDate;
  final AssignmentMode operationType;
  final String sourceLocationName; // HATA DÜZELTMESİ: UI'da kullanılmak üzere eklendi.
  final String targetLocationName; // HATA DÜZELTMESİ: UI'da kullanılmak üzere eklendi.
  final String? containerId;

  const TransferOperationHeader({
    required this.employeeId,
    required this.transferDate,
    required this.operationType,
    required this.sourceLocationName,
    required this.targetLocationName,
    this.containerId,
  });

  Map<String, dynamic> toApiJson(int sourceLocationId, int targetLocationId) {
    return {
      'employee_id': employeeId,
      'transfer_date': transferDate.toIso8601String(),
      'operation_type': operationType.apiName,
      'source_location_id': sourceLocationId,
      'target_location_id': targetLocationId,
    };
  }
}
