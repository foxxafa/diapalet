// core/local/populate_offline_test_data.dart
import 'package:diapalet/core/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class TestDataPopulator {
  static Future<void> populate() async {
    // DÜZELTME: DatabaseHelper'ın singleton örneğine .instance ile erişilir.
    final db = await DatabaseHelper.instance.database;
    debugPrint("Checking if test data needs to be populated...");

    final countResult = await db.rawQuery('SELECT COUNT(*) FROM product');
    final count = Sqflite.firstIntValue(countResult);

    if ((count ?? 0) == 0) {
      debugPrint("Database is empty, populating with test data...");
      await _insertTestData(db);
    } else {
      debugPrint("Database already contains data.");
    }
  }

  static Future<void> _insertTestData(Database db) async {
    await db.transaction((txn) async {
      // Test verileri buraya eklenebilir.
    });
  }
}
