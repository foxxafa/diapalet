import 'package:flutter/foundation.dart';

/// Bir paletin temel bilgilerini temsil eder.
/// Sunucu tarafında 'mal_kabul_paletleri' gibi bir tabloya karşılık gelebilir.
@immutable
class PalletInfo {
  final String id; // Paletin benzersiz ID'si (örn: PALET-2024-0001)
  final String locationId; // Bulunduğu lokasyonun kodu
  final DateTime createdAt;

  const PalletInfo({
    required this.id,
    required this.locationId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location_id': locationId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PalletInfo.fromJson(Map<String, dynamic> json) {
    return PalletInfo(
      id: json['id'],
      locationId: json['location_id'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
} 