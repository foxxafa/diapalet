// core/local/populate_offline_test_data.dart
import 'package:diapalet/core/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class TestDataPopulator {
  static Future<void> populate() async {
    final db = await DatabaseHelper().database;
    debugPrint("Checking if test data needs to be populated...");

    // Check if products table is empty
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products'));
    if (count == 0) {
      debugPrint("Database is empty, populating with test data...");
      await _insertTestData(db);
    } else {
      debugPrint("Database already contains data.");
    }
  }

  static Future<void> _insertTestData(Database db) async {
    await db.transaction((txn) async {
      // Add test data here
    });
  }
}
