// lib/features/pallet_assignment/domain/entities/assignment_mode.dart
import 'package:easy_localization/easy_localization.dart';
enum AssignmentMode { palet, kutu }

extension AssignmentModeExtension on AssignmentMode {
  String get displayName => tr('assignment_mode.$name');
}
