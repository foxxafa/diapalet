import 'package:equatable/equatable.dart';

class LocationInfo extends Equatable {
  final int id;
  final String name;
  final String code;

  const LocationInfo({
    required this.id,
    required this.name,
    required this.code,
  });

  @override
  List<Object?> get props => [id, name, code];

  // Optional: if you need to create from a map
  factory LocationInfo.fromMap(Map<String, dynamic> map) {
    return LocationInfo(
      id: map['id'] as int,
      name: map['name'] as String,
      code: map['code'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
    };
  }

  String get location => name;
} 