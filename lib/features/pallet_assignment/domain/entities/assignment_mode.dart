// lib/features/pallet_assignment/domain/entities/assignment_mode.dart
enum AssignmentMode { palet, kutu }

extension AssignmentModeExtension on AssignmentMode {
  String get displayName {
    switch (this) {
      case AssignmentMode.palet:
        return 'Palet';
      case AssignmentMode.kutu:
        return 'Kutu';
    }
  }
}
