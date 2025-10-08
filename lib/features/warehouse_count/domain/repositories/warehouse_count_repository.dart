// lib/features/warehouse_count/domain/repositories/warehouse_count_repository.dart

import '../entities/count_sheet.dart';
import '../entities/count_item.dart';

/// Repository interface for warehouse count operations.
///
/// Following Clean Architecture, this defines the contract that the data layer must implement.
abstract class WarehouseCountRepository {
  /// Fetch all count sheets for a specific warehouse
  Future<List<CountSheet>> getCountSheetsByWarehouse(String warehouseCode);

  /// Fetch a single count sheet with all its items
  Future<CountSheet?> getCountSheetById(int id);

  /// Fetch all items for a specific count sheet
  Future<List<CountItem>> getCountItemsBySheetId(int countSheetId);

  /// Create a new count sheet (returns the created sheet with ID)
  Future<CountSheet> createCountSheet(CountSheet sheet);

  /// Update an existing count sheet (for Save & Continue)
  Future<void> updateCountSheet(CountSheet sheet);

  /// Complete a count sheet (change status to 'completed')
  Future<void> completeCountSheet(int countSheetId);

  /// Add a new count item to a sheet
  Future<CountItem> addCountItem(CountItem item);

  /// Update an existing count item
  Future<void> updateCountItem(CountItem item);

  /// Delete a count item
  Future<void> deleteCountItem(int itemId);

  /// Delete all items for a specific sheet (used when full replace on update)
  Future<void> deleteAllItemsForSheet(int countSheetId);

  /// Save count sheet to server (for Save & Continue - direct API call)
  /// Returns true if saved successfully online
  Future<bool> saveCountSheetToServer(CountSheet sheet, List<CountItem> items);

  /// Queue count sheet for sync (for Save & Finish - pending operation)
  Future<void> queueCountSheetForSync(CountSheet sheet, List<CountItem> items);

  /// Generate a unique sheet number in format: COUNT-YYYYMMDD-EMPLOYEEID-UUID4
  String generateSheetNumber(int employeeId);
}
