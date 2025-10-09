// lib/features/warehouse_count/domain/entities/count_sheet.dart

class CountSheet {
  final int? id; // NULL for new sheets, filled after save
  final String operationUniqueId; // UUID v4
  final String sheetNumber; // COUNT-YYYYMMDD-EMPLOYEEID-UUID4
  final int employeeId;
  final String warehouseCode;
  final String status; // 'in_progress' or 'completed'
  final String? notes;
  final DateTime startDate;
  final DateTime? completeDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CountSheet({
    this.id,
    required this.operationUniqueId,
    required this.sheetNumber,
    required this.employeeId,
    required this.warehouseCode,
    required this.status,
    this.notes,
    required this.startDate,
    this.completeDate,
    this.createdAt,
    this.updatedAt,
  });

  /// Create from SQLite database row
  factory CountSheet.fromMap(Map<String, dynamic> map) {
    return CountSheet(
      id: map['id'] as int?,
      operationUniqueId: map['operation_unique_id'] as String,
      sheetNumber: map['sheet_number'] as String,
      employeeId: map['employee_id'] as int,
      warehouseCode: map['warehouse_code'] as String,
      status: map['status'] as String,
      notes: map['notes'] as String?,
      startDate: DateTime.parse(map['start_date'] as String),
      completeDate: map['complete_date'] != null
          ? DateTime.parse(map['complete_date'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// Convert to SQLite database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'operation_unique_id': operationUniqueId,
      'sheet_number': sheetNumber,
      'employee_id': employeeId,
      'warehouse_code': warehouseCode,
      'status': status,
      if (notes != null) 'notes': notes,
      'start_date': startDate.toIso8601String(),
      if (completeDate != null) 'complete_date': completeDate!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Convert to JSON for API sync
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'operation_unique_id': operationUniqueId,
      'sheet_number': sheetNumber,
      'employee_id': employeeId,
      'warehouse_code': warehouseCode,
      'status': status,
      if (notes != null) 'notes': notes,
      'start_date': startDate.toIso8601String(),
      if (completeDate != null) 'complete_date': completeDate!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';

  /// Create a copy with updated fields
  CountSheet copyWith({
    int? id,
    String? operationUniqueId,
    String? sheetNumber,
    int? employeeId,
    String? warehouseCode,
    String? status,
    String? notes,
    DateTime? startDate,
    DateTime? completeDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CountSheet(
      id: id ?? this.id,
      operationUniqueId: operationUniqueId ?? this.operationUniqueId,
      sheetNumber: sheetNumber ?? this.sheetNumber,
      employeeId: employeeId ?? this.employeeId,
      warehouseCode: warehouseCode ?? this.warehouseCode,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      startDate: startDate ?? this.startDate,
      completeDate: completeDate ?? this.completeDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
