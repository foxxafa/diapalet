// lib/features/warehouse_count/presentation/screens/warehouse_count_list_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/core/services/telegram_logger_service.dart';
import 'package:diapalet/features/warehouse_count/constants/warehouse_count_constants.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';
import 'package:diapalet/features/warehouse_count/domain/repositories/warehouse_count_repository.dart';
import 'package:diapalet/features/warehouse_count/presentation/widgets/count_info_card.dart';
import 'package:diapalet/features/warehouse_count/presentation/screens/warehouse_count_screen.dart';

class WarehouseCountListScreen extends StatefulWidget {
  final WarehouseCountRepository repository;

  const WarehouseCountListScreen({
    super.key,
    required this.repository,
  });

  @override
  State<WarehouseCountListScreen> createState() => _WarehouseCountListScreenState();
}

class _WarehouseCountListScreenState extends State<WarehouseCountListScreen> {
  final TextEditingController _notesController = TextEditingController();
  String? _selectedWarehouseCode;
  List<Map<String, dynamic>> _warehouses = [];
  List<CountSheet> _existingSheets = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWarehousesAndSheets();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehousesAndSheets() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load warehouse list from SharedPreferences
      final warehousesJson = prefs.getString('warehouses_list');
      if (warehousesJson != null) {
        final warehousesList = jsonDecode(warehousesJson) as List<dynamic>;
        _warehouses = warehousesList.map((w) => w as Map<String, dynamic>).toList();

        // Set first warehouse as default selection
        if (_warehouses.isNotEmpty && _selectedWarehouseCode == null) {
          _selectedWarehouseCode = _warehouses.first['warehouse_code'] as String;
          await _loadExistingSheets();
        }
      }
    } catch (e) {
      debugPrint('Error loading warehouses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.error.load_warehouses'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExistingSheets() async {
    if (_selectedWarehouseCode == null) return;

    try {
      final sheets = await widget.repository.getCountSheetsByWarehouse(_selectedWarehouseCode!);
      if (mounted) {
        setState(() => _existingSheets = sheets);
      }
    } catch (e) {
      debugPrint('Error loading count sheets: $e');
    }
  }

  Future<void> _createNewCountSheet() async {
    if (_selectedWarehouseCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.select_warehouse'.tr())),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('employee_id');

      if (employeeId == null) {
        throw Exception('Employee ID not found');
      }

      // Generate unique IDs
      const uuid = Uuid();
      final operationUniqueId = uuid.v4();
      final sheetNumber = widget.repository.generateSheetNumber(employeeId);

      // Create new count sheet
      final now = DateTime.now().toUtc();
      final newSheet = CountSheet(
        operationUniqueId: operationUniqueId,
        sheetNumber: sheetNumber,
        employeeId: employeeId,
        warehouseCode: _selectedWarehouseCode!,
        status: WarehouseCountConstants.statusInProgress,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        startDate: now,
        createdAt: now,
        updatedAt: now,
      );

      // Save to database
      final createdSheet = await widget.repository.createCountSheet(newSheet);

      if (mounted) {
        // Clear notes field
        _notesController.clear();

        // Navigate to count screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WarehouseCountScreen(
              repository: widget.repository,
              countSheet: createdSheet,
            ),
          ),
        );

        // Reload sheets after returning
        await _loadExistingSheets();
      }
    } catch (e, stackTrace) {
      debugPrint('Error creating count sheet: $e');

      // Log to Telegram
      TelegramLoggerService.logError(
        'Warehouse Count Sheet Creation Failed',
        e.toString(),
        stackTrace: stackTrace,
        context: {
          'screen': 'WarehouseCountListScreen',
          'method': '_createNewCountSheet',
          'warehouse_code': _selectedWarehouseCode ?? 'null',
          'employee_id': (await SharedPreferences.getInstance()).getInt('employee_id')?.toString() ?? 'null',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.error.create_sheet'.tr())),
        );
      }
    }
  }

  Future<void> _openExistingSheet(CountSheet sheet) async {
    if (sheet.isCompleted) {
      // Show read-only view
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.info.sheet_completed'.tr())),
      );
      return;
    }

    // Navigate to edit existing sheet
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WarehouseCountScreen(
          repository: widget.repository,
          countSheet: sheet,
        ),
      ),
    );

    // Reload sheets after returning
    await _loadExistingSheets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'warehouse_count.title'.tr(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // New Count Sheet Section
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'warehouse_count.new_count'.tr(),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 16),

                          // Warehouse Dropdown
                          DropdownButtonFormField<String>(
                            value: _selectedWarehouseCode,
                            decoration: InputDecoration(
                              labelText: 'warehouse_count.select_warehouse'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.warehouse),
                            ),
                            items: _warehouses.map((warehouse) {
                              return DropdownMenuItem<String>(
                                value: warehouse['warehouse_code'] as String,
                                child: Text(warehouse['name'] as String),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedWarehouseCode = value;
                                });
                                _loadExistingSheets();
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // Notes TextField
                          TextField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'warehouse_count.notes_optional'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.note_alt),
                              counterText: '${_notesController.text.length}/${WarehouseCountConstants.maxNotesLength}',
                            ),
                            maxLines: 3,
                            maxLength: WarehouseCountConstants.maxNotesLength,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),

                          // Start Count Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _createNewCountSheet,
                              icon: const Icon(Icons.add_circle),
                              label: Text('warehouse_count.start_counting'.tr()),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Existing Sheets Section
                  Text(
                    'warehouse_count.previous_counts'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),

                  if (_existingSheets.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'warehouse_count.no_previous_counts'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._existingSheets.map((sheet) {
                      return CountInfoCard(
                        countSheet: sheet,
                        onTap: () => _openExistingSheet(sheet),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
