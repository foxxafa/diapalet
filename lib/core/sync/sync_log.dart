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
}
