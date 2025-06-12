// lib/core/sync/pending_operation.dart
import 'dart:convert';

class PendingOperation {
  final int id;
  final String operationType;
  final Map<String, dynamic> operationData;
  final DateTime createdAt;
  final String status;
  final int attempts;
  final String? errorMessage;
  final String tableName;

  PendingOperation({
    required this.id,
    required this.operationType,
    required this.operationData,
    required this.createdAt,
    required this.status,
    this.attempts = 0,
    this.errorMessage,
    required this.tableName,
  });

  /// Pending Operations ekranında gösterilecek ana başlık.
  String get displayTitle {
    final header = operationData['header'] as Map<String, dynamic>? ?? {};
    switch (operationType) {
      case 'goods_receipt':
        return 'Mal Kabul: ${header['invoice_number'] ?? 'Fiş N/A'}';
      case 'pallet_transfer':
        return 'Palet Transferi';
      case 'box_transfer':
        return 'Kutu Transferi';
      default:
        return 'Bilinmeyen İşlem: $operationType';
    }
  }

  /// Pending Operations ekranında gösterilecek alt başlık.
  String get displaySubtitle {
    // HATA DÜZELTMESİ: 'header' değişkeni burada tanımlanmamıştı.
    final header = operationData['header'] as Map<String, dynamic>? ?? {};
    final items = operationData['items'] as List<dynamic>? ?? [];
    final dateString = header['receipt_date'] as String?;
    final date = dateString != null ? DateTime.tryParse(dateString) : null;
    final formattedDate = date != null
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
        : 'Tarih N/A';
    return '${items.length} kalem ürün • $formattedDate';
  }

  /// Veritabanına kaydetmek için modeli Map'e dönüştürür.
  Map<String, dynamic> toMapForDb() {
    return {
      'id': id == 0 ? null : id,
      'type': operationType,
      'data': jsonEncode(operationData),
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'attempts': attempts,
      'error_message': errorMessage,
    };
  }

  /// Sunucuya yükleme için uygun payload formatını oluşturur.
  Map<String, dynamic> toUploadPayload() {
    return {
      'type': operationType,
      'data': operationData,
    };
  }

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation(
      id: map['id'] as int,
      operationType: map['type'] as String,
      operationData: jsonDecode(map['data'] as String) as Map<String, dynamic>,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String? ?? 'pending',
      attempts: map['attempts'] as int? ?? 0,
      errorMessage: map['error_message'] as String?,
      tableName: map['table_name'] as String? ?? '',
    );
  }
}
