// lib/features/warehouse_count/presentation/screens/warehouse_count_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/warehouse_count/constants/warehouse_count_constants.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_mode.dart';
import 'package:diapalet/features/warehouse_count/domain/repositories/warehouse_count_repository.dart';
import 'package:diapalet/features/warehouse_count/presentation/widgets/counted_items_review_table.dart';

class WarehouseCountScreen extends StatefulWidget {
  final WarehouseCountRepository repository;
  final CountSheet countSheet;

  const WarehouseCountScreen({
    super.key,
    required this.repository,
    required this.countSheet,
  });

  @override
  State<WarehouseCountScreen> createState() => _WarehouseCountScreenState();
}

class _WarehouseCountScreenState extends State<WarehouseCountScreen> {
  CountMode _selectedMode = CountMode.product;
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _shelfController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  List<CountItem> _countedItems = [];
  String? _scannedBarcode;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingItems();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _shelfController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await widget.repository.getCountItemsBySheetId(widget.countSheet.id!);
      if (mounted) {
        setState(() => _countedItems = items);
      }
    } catch (e) {
      debugPrint('Error loading count items: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onBarcodeScanned(String barcode) {
    setState(() {
      _scannedBarcode = barcode;
    });
  }

  Future<void> _addCountItem() async {
    // Validate inputs
    if (_scannedBarcode == null || _scannedBarcode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.scan_barcode'.tr())),
      );
      return;
    }

    if (_shelfController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.enter_shelf'.tr())),
      );
      return;
    }

    final quantityText = _quantityController.text.trim();
    if (quantityText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.enter_quantity'.tr())),
      );
      return;
    }

    final quantity = double.tryParse(quantityText);
    if (quantity == null || quantity < WarehouseCountConstants.minQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.invalid_quantity'.tr())),
      );
      return;
    }

    if (quantity > WarehouseCountConstants.maxQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.quantity_too_large'.tr())),
      );
      return;
    }

    try {
      // In a real implementation, you would:
      // 1. Look up shelf by code to get location_id
      // 2. For product mode: look up product info by barcode
      // 3. For pallet mode: validate pallet exists

      // For now, using placeholder values
      // TODO: Implement proper lookup logic

      final countItem = CountItem(
        countSheetId: widget.countSheet.id!,
        operationUniqueId: widget.countSheet.operationUniqueId,
        itemUuid: const Uuid().v4(),
        palletBarcode: _selectedMode.isPallet ? _scannedBarcode : null,
        locationId: 1, // TODO: Look up actual location_id from shelf code
        quantityCounted: quantity,
        barcode: _selectedMode.isProduct ? _scannedBarcode : null,
        shelfCode: _shelfController.text.trim(),
        // TODO: Add urunKey, birimKey, StokKodu from product lookup
      );

      final savedItem = await widget.repository.addCountItem(countItem);

      if (mounted) {
        setState(() {
          _countedItems.add(savedItem);
          // Clear inputs
          _scannedBarcode = null;
          _quantityController.clear();
          _shelfController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.success.item_added'.tr())),
        );
      }
    } catch (e) {
      debugPrint('Error adding count item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.error.add_item'.tr())),
        );
      }
    }
  }

  Future<void> _removeCountItem(CountItem item) async {
    try {
      await widget.repository.deleteCountItem(item.id!);
      if (mounted) {
        setState(() {
          _countedItems.remove(item);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.success.item_removed'.tr())),
        );
      }
    } catch (e) {
      debugPrint('Error removing count item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.error.remove_item'.tr())),
        );
      }
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _isSaving = true);
    try {
      final success = await widget.repository.saveCountSheetToServer(
        widget.countSheet,
        _countedItems,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('warehouse_count.success.saved_online'.tr())),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('warehouse_count.warning.saved_local_only'.tr())),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving count sheet: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.error.save_failed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndFinish() async {
    if (_countedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('warehouse_count.error.no_items'.tr())),
      );
      return;
    }

    // Confirm action
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('warehouse_count.confirm_finish.title'.tr()),
        content: Text('warehouse_count.confirm_finish.message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      // Complete the count sheet
      await widget.repository.completeCountSheet(widget.countSheet.id!);

      // Queue for sync
      final completedSheet = widget.countSheet.copyWith(
        status: WarehouseCountConstants.statusCompleted,
        completeDate: DateTime.now(),
      );

      await widget.repository.queueCountSheetForSync(completedSheet, _countedItems);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.success.completed'.tr())),
        );
        Navigator.pop(context); // Return to list screen
      }
    } catch (e) {
      debugPrint('Error finishing count sheet: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('warehouse_count.error.finish_failed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: widget.countSheet.sheetNumber,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Count Mode Segmented Button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<CountMode>(
                    segments: [
                      ButtonSegment(
                        value: CountMode.product,
                        label: Text('warehouse_count.mode.product'.tr()),
                        icon: const Icon(Icons.inventory_2),
                      ),
                      ButtonSegment(
                        value: CountMode.pallet,
                        label: Text('warehouse_count.mode.pallet'.tr()),
                        icon: const Icon(Icons.widgets),
                      ),
                    ],
                    selected: {_selectedMode},
                    onSelectionChanged: (Set<CountMode> newSelection) {
                      setState(() {
                        _selectedMode = newSelection.first;
                        _scannedBarcode = null;
                      });
                    },
                  ),
                ),

                // Scanner Section
                Container(
                  height: 200,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _scannedBarcode == null
                      ? MobileScanner(
                          controller: _scannerController,
                          onDetect: (capture) {
                            final List<Barcode> barcodes = capture.barcodes;
                            if (barcodes.isNotEmpty) {
                              final barcode = barcodes.first.rawValue;
                              if (barcode != null) {
                                _onBarcodeScanned(barcode);
                              }
                            }
                          },
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle, size: 48, color: Colors.green),
                              const SizedBox(height: 8),
                              Text(
                                'warehouse_count.scanned'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(_scannedBarcode!),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () => setState(() => _scannedBarcode = null),
                                icon: const Icon(Icons.refresh),
                                label: Text('warehouse_count.scan_again'.tr()),
                              ),
                            ],
                          ),
                        ),
                ),

                const SizedBox(height: 16),

                // Input Fields
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _shelfController,
                          decoration: InputDecoration(
                            labelText: 'warehouse_count.shelf'.tr(),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.location_on),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _quantityController,
                          decoration: InputDecoration(
                            labelText: 'warehouse_count.quantity'.tr(),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.numbers),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _addCountItem,
                        icon: const Icon(Icons.add_circle),
                        iconSize: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Items Review Table
                Expanded(
                  child: CountedItemsReviewTable(
                    items: _countedItems,
                    onItemRemoved: _removeCountItem,
                  ),
                ),

                // Action Buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _saveAndContinue,
                          icon: const Icon(Icons.cloud_upload),
                          label: Text('warehouse_count.save_continue'.tr()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveAndFinish,
                          icon: const Icon(Icons.check_circle),
                          label: Text('warehouse_count.save_finish'.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
