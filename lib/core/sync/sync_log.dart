// lib/core/sync/sync_log.dart

import 'package:flutter/foundation.dart';

@immutable
class SyncLog {
  final int? id;
  final DateTime timestamp;
  final String type;
  final String status;
  final String message;

  const SyncLog({
    this.id,
    required this.timestamp,
    required this.type,
    required this.status,
    required this.message,
  });

  factory SyncLog.fromMap(Map<String, dynamic> map) {
    return SyncLog(
      id: map['id'],
      timestamp: DateTime.parse(map['timestamp']),
      type: map['type'],
      status: map['status'],
      message: map['message'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SyncLog &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              timestamp == other.timestamp &&
              type == other.type &&
              status == other.status &&
              message == other.message;

  @override
  int get hashCode =>
      id.hashCode ^
      timestamp.hashCode ^
      type.hashCode ^
      status.hashCode ^
      message.hashCode;
}
