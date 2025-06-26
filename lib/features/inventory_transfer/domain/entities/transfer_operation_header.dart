// lib/features/inventory_transfer/domain/entities/transfer_operation_header.dart
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';

class TransferOperationHeader {
  final int employeeId;
  final DateTime transferDate;
  final AssignmentMode operationType;
  final String sourceLocationName;
  final String targetLocationName;
  final String? containerId;
  final int? siparisId;

  const TransferOperationHeader({
    required this.employeeId,
    required this.transferDate,
    required this.operationType,
    required this.sourceLocationName,
    required this.targetLocationName,
    this.containerId,
    this.siparisId,
  });

  Map<String, dynamic> toApiJson(int sourceLocationId, int targetLocationId) {
    // # HATA DÜZELTMESİ: Map'in tipi açıkça 'Map<String, dynamic>' olarak belirtildi.
    // Bu, 'invalid_assignment' hatasını çözer.
    final Map<String, dynamic> jsonMap = {
      'employee_id': employeeId,
      'transfer_date': transferDate.toIso8601String(),
      'operation_type': operationType.apiName,
      'source_location_id': sourceLocationId,
      'target_location_id': targetLocationId,
    };

    // Eğer siparisId null değilse, JSON'a ekle.
    if (siparisId != null) {
      jsonMap['siparis_id'] = siparisId;
    }

    return jsonMap;
  }
}
