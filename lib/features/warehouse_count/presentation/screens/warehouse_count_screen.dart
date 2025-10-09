// lib/features/warehouse_count/presentation/screens/warehouse_count_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/core/widgets/qr_text_field.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_input_decoration.dart';
import 'package:diapalet/features/warehouse_count/constants/warehouse_count_constants.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_mode.dart';
import 'package:diapalet/features/warehouse_count/domain/repositories/warehouse_count_repository.dart';
import 'package:diapalet/features/warehouse_count/presentation/widgets/counted_items_review_table.dart';
import 'package:diapalet/features/warehouse_count/presentation/screens/warehouse_count_review_screen.dart';
import 'package:diapalet/features/goods_receiving/utils/date_validation_utils.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:provider/provider.dart';
import 'dart:async';

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
  static const double _gap = 12;

  CountMode _selectedMode = CountMode.product;
  final TextEditingController _palletBarcodeController = TextEditingController();
  final TextEditingController _productSearchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _shelfController = TextEditingController();
  final TextEditingController _expiryDateController = TextEditingController();

  final FocusNode _palletBarcodeFocusNode = FocusNode();
  final FocusNode _productSearchFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();
  final FocusNode _shelfFocusNode = FocusNode();
  final FocusNode _expiryDateFocusNode = FocusNode();

  List<CountItem> _countedItems = [];
  bool _isLoading = false;

  // Product selection state
  String? _selectedBarcode;
  String? _selectedStokKodu;
  String? _selectedProductName; // Ürün adını sakla
  List<Map<String, dynamic>> _availableUnits = [];
  String? _selectedBirimKey;
  List<Map<String, dynamic>> _productSearchResults = [];

  // Shelf validation state
  bool _isShelfValid = false;

  late BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _barcodeSub;

  @override
  void initState() {
    super.initState();
    _barcodeService = Provider.of<BarcodeIntentService>(context, listen: false);
    _initBarcodeListener();
    _loadExistingItems();
  }

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _palletBarcodeController.dispose();
    _productSearchController.dispose();
    _quantityController.dispose();
    _shelfController.dispose();
    _expiryDateController.dispose();
    _palletBarcodeFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _quantityFocusNode.dispose();
    _shelfFocusNode.dispose();
    _expiryDateFocusNode.dispose();
    super.dispose();
  }

  void _initBarcodeListener() {
    _barcodeSub = _barcodeService.stream.listen((barcode) {
      if (mounted) {
        _handleBarcodeScanned(barcode);
      }
    });
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

  void _handleBarcodeScanned(String barcode) {
    setState(() {
      _productSearchController.text = barcode;
      _selectedBarcode = barcode;
    });
    _searchProduct(barcode);
  }

  Future<void> _searchProduct(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _productSearchResults = [];
      });
      return;
    }

    try {
      // HEM PRODUCT HEM PALLET MODUNDA ürün araması yap
      final searchResults = await widget.repository.searchProductsPartial(query.trim());

      if (mounted) {
        setState(() {
          _productSearchResults = searchResults;
        });
      }
    } catch (e) {
      debugPrint('Error searching product: $e');
      if (mounted) {
        setState(() {
          _productSearchResults = [];
        });
        _showError('warehouse_count.error.search_failed'.tr());
      }
    }
  }

  void _selectProduct(Map<String, dynamic> productInfo) async {
    final stockCode = productInfo['StokKodu'] as String? ?? '';
    final barcode = productInfo['barkod'] as String?;
    final productName = productInfo['UrunAdi'] as String? ?? '';

    setState(() {
      _selectedBarcode = barcode;
      _selectedStokKodu = stockCode;
      _selectedProductName = productName; // Ürün adını sakla
      _productSearchResults = [];

      // Text field'a BARKOD + STOK KODU yaz (goods_receiving gibi)
      // Eğer barkod varsa: "BARKOD (STOKKODU)", yoksa sadece "STOKKODU"
      if (barcode != null && barcode.isNotEmpty) {
        _productSearchController.text = '$barcode ($stockCode)';
      } else {
        _productSearchController.text = stockCode;
      }
    });

    // Ürünün TÜM birimlerini veritabanından getir (Goods Receiving gibi)
    if (stockCode.isNotEmpty) {
      try {
        final dbHelper = DatabaseHelper.instance;
        final units = await dbHelper.getAllUnitsForProduct(stockCode);

        if (mounted) {
          setState(() {
            _availableUnits = units;

            // ARAMA SONUCUNDAN gelen birim_key'i kullan!
            // Eğer kullanıcı ARAMA LİSTESİNDEN belirli bir birimi seçtiyse (BOX veya UNIT)
            // o birimi dropdown'da otomatik seç
            final searchBirimKey = productInfo['birim_key'] as String?;

            if (searchBirimKey != null && units.any((u) => u['birim_key'] == searchBirimKey)) {
              // Arama sonucundan gelen birim mevcut, onu seç
              _selectedBirimKey = searchBirimKey;
              debugPrint('✅ Auto-selected unit from search: $searchBirimKey');
            } else {
              // Arama sonucundan birim yok veya bulunamadı, NULL bırak
              _selectedBirimKey = null;
              debugPrint('⚠️ No unit auto-selected, user must choose manually');
            }

            debugPrint('🔄 Updated _availableUnits: ${units.length} units');
            for (var unit in units) {
              debugPrint('   - ${unit['birimadi']} (key: ${unit['birim_key']})');
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading units: $e');
        if (mounted) {
          setState(() {
            _availableUnits = [];
            _selectedBirimKey = null;
          });
        }
      }
    }

    // Son kullanma tarihi alanına focus yap (hem ürün hem palet modunda)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _expiryDateFocusNode.requestFocus();
      }
    });
  }

  Future<void> _openQrScanner() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const QrScannerScreen(),
      ),
    );

    if (barcode != null && mounted) {
      _handleBarcodeScanned(barcode);
    }
  }

  Future<void> _validateShelf(String shelfCode) async {
    if (shelfCode.trim().isEmpty) {
      setState(() {
        _isShelfValid = false;
      });
      return;
    }

    try {
      // Convert to uppercase for validation (case-insensitive)
      final upperShelfCode = shelfCode.trim().toUpperCase();
      final isValid = await widget.repository.validateShelfCode(upperShelfCode);

      if (mounted) {
        setState(() {
          _isShelfValid = isValid;
        });

        if (!isValid) {
          _showError('warehouse_count.error.invalid_shelf'.tr());
        } else {
          // Update controller with uppercase value
          _shelfController.text = upperShelfCode;

          // Move to Add button - focus stays on shelf but user can press Add
          // No auto-focus to quantity since shelf validation happens on enter
        }
      }
    } catch (e) {
      debugPrint('Error validating shelf: $e');
      if (mounted) {
        setState(() {
          _isShelfValid = false;
        });
        _showError('warehouse_count.error.validation_failed'.tr());
      }
    }
  }

  Future<void> _addCountItem() async {
    // Pallet modunda pallet barkodu zorunlu
    if (_selectedMode.isPallet) {
      final palletBarcode = _palletBarcodeController.text.trim();
      if (palletBarcode.isEmpty) {
        _showError('warehouse_count.error.scan_pallet'.tr());
        return;
      }
    }

    // Validate inputs - Product barkodu zorunlu
    if (_selectedBarcode == null || _selectedBarcode!.isEmpty) {
      _showError('warehouse_count.error.scan_barcode'.tr());
      return;
    }

    final shelfCode = _shelfController.text.trim();
    if (shelfCode.isEmpty) {
      _showError('warehouse_count.error.enter_shelf'.tr());
      return;
    }

    // Raf kodunu doğrula
    final isValidShelf = await widget.repository.validateShelfCode(shelfCode);
    if (!isValidShelf) {
      _showError('warehouse_count.error.invalid_shelf'.tr());
      return;
    }

    final quantityText = _quantityController.text.trim();
    if (quantityText.isEmpty) {
      _showError('warehouse_count.error.enter_quantity'.tr());
      return;
    }

    final quantity = double.tryParse(quantityText);
    if (quantity == null || quantity < WarehouseCountConstants.minQuantity) {
      _showError('warehouse_count.error.invalid_quantity'.tr());
      return;
    }

    if (quantity > WarehouseCountConstants.maxQuantity) {
      _showError('warehouse_count.error.quantity_too_large'.tr());
      return;
    }

    // Expiry date required (hem product hem pallet modunda ürün ekleniyor)
    if (_expiryDateController.text.trim().isEmpty) {
      _showError('warehouse_count.error.expiry_required'.tr());
      return;
    }

    // Unit selection required (hem product hem pallet modunda ürün ekleniyor)
    if (_selectedBirimKey == null || _selectedBirimKey!.isEmpty) {
      _showError('goods_receiving_screen.validator_unit_required'.tr());
      return;
    }

    try {
      final countItem = CountItem(
        countSheetId: widget.countSheet.id!,
        operationUniqueId: widget.countSheet.operationUniqueId,
        itemUuid: const Uuid().v4(),
        // Pallet modunda: palletBarcodeController'dan al
        // Product modunda: null
        palletBarcode: _selectedMode.isPallet ? _palletBarcodeController.text.trim() : null,
        quantityCounted: quantity,
        // Product barkodu her zaman var (hem product hem pallet modunda ürün ekleniyor)
        barcode: _selectedBarcode,
        shelfCode: shelfCode,
        // Birim key her zaman var (ürün ekleniyorsa birim gerekli)
        birimKey: _selectedBirimKey,
        // Expiry date her zaman var (ürün ekleniyorsa gerekli)
        expiryDate: _expiryDateController.text.trim().isNotEmpty ? _expiryDateController.text.trim() : null,
        stokKodu: _selectedStokKodu,
      );

      final savedItem = await widget.repository.addCountItem(countItem);

      if (mounted) {
        setState(() {
          _countedItems.add(savedItem);
          _clearInputs();
        });

        _showSuccess('warehouse_count.success.item_added'.tr());
      }
    } catch (e) {
      debugPrint('Error adding count item: $e');
      if (mounted) {
        _showError('warehouse_count.error.add_item'.tr());
      }
    }
  }

  void _clearInputs() {
    _palletBarcodeController.clear();
    _productSearchController.clear();
    _quantityController.clear();
    _shelfController.clear();
    _expiryDateController.clear();
    _selectedBarcode = null;
    _selectedStokKodu = null;
    _selectedProductName = null;
    _selectedBirimKey = null;
    _availableUnits = [];
    _productSearchResults = [];
    _isShelfValid = false;

    // Focus'u doğru alana ver
    if (_selectedMode.isPallet) {
      _palletBarcodeFocusNode.requestFocus();
    } else {
      _productSearchFocusNode.requestFocus();
    }
  }

  Future<void> _removeCountItem(CountItem item) async {
    try {
      await widget.repository.deleteCountItem(item.id!);
      if (mounted) {
        setState(() {
          _countedItems.remove(item);
        });
        _showSuccess('warehouse_count.success.item_removed'.tr());
      }
    } catch (e) {
      debugPrint('Error removing count item: $e');
      if (mounted) {
        _showError('warehouse_count.error.remove_item'.tr());
      }
    }
  }


  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: widget.countSheet.sheetNumber,
      ),
      bottomNavigationBar: _buildBottomBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mode Selector
                    _buildModeSelector(),
                    const SizedBox(height: _gap),

                    // Pallet Barcode Field (only for pallet mode)
                    if (_selectedMode.isPallet) ...[
                      _buildPalletBarcodeField(),
                      const SizedBox(height: _gap),
                    ],

                    // Product Search with QR (HER ZAMAN VAR - hem product hem pallet modda)
                    _buildProductSearchField(),
                    const SizedBox(height: _gap),

                    // Expiry Date and Unit Row (HER ZAMAN VAR - hem product hem pallet modda)
                    _buildExpiryDateAndUnitRow(),
                    const SizedBox(height: _gap),

                    // Quantity and Shelf Row (yer değiştirdik: önce quantity, sonra shelf)
                    _buildQuantityAndShelfRow(),
                    const SizedBox(height: _gap),

                    // Add Button
                    _buildAddButton(),
                    const SizedBox(height: 24),

                    // Last Added Item Display
                    if (_countedItems.isNotEmpty) ...[
                      Text(
                        '${'warehouse_count.counted_items'.tr()} (${_countedItems.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      CountedItemsReviewTable(
                        items: [_countedItems.last], // Sadece son eklenen item
                        onItemRemoved: _removeCountItem,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<CountMode>(
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
          _clearInputs();
        });
      },
    );
  }

  Widget _buildPalletBarcodeField() {
    return QrTextField(
      controller: _palletBarcodeController,
      focusNode: _palletBarcodeFocusNode,
      labelText: 'warehouse_count.pallet_barcode'.tr(),
      showClearButton: true,
      onQrTap: _openQrScanner,
      validator: (value) {
        if (_selectedMode.isPallet && (value == null || value.isEmpty)) {
          return 'warehouse_count.error.scan_pallet'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildProductSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QrTextField(
          controller: _productSearchController,
          focusNode: _productSearchFocusNode,
          // Label: Ürün seçiliyse "ÜRÜN ADI (STOK KODU)", değilse "Search or Scan Product"
          labelText: _selectedProductName != null && _selectedStokKodu != null
              ? '$_selectedProductName ($_selectedStokKodu)'
              : 'warehouse_count.search_product'.tr(),
          showClearButton: true,
          onQrTap: _openQrScanner,
          onChanged: (value) {
            // Kullanıcı yazmaya başlarsa seçimi temizle
            if (value.isNotEmpty && _selectedProductName != null) {
              setState(() {
                _selectedBarcode = null;
                _selectedStokKodu = null;
                _selectedProductName = null;
                _availableUnits = [];
                _selectedBirimKey = null;
              });
            }
            _searchProduct(value);
          },
        ),
        if (_productSearchResults.isNotEmpty)
          _buildProductSuggestions(),
      ],
    );
  }

  Widget _buildProductSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        children: _productSearchResults.map((product) {
          return ListTile(
            dense: true,
            title: Text(
              product['UrunAdi'] as String? ?? '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stok Kodu: ${product['StokKodu']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Barkod: ${product['barkod']}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                if (product['birimadi'] != null)
                  Text(
                    'Birim: ${product['birimadi']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
            onTap: () {
              _selectProduct(product);
              // Product name zaten _selectProduct içinde set ediliyor, tekrar set etme!
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpiryDateField() {
    return StatefulBuilder(
      builder: (context, setState) {
        return TextFormField(
          controller: _expiryDateController,
          focusNode: _expiryDateFocusNode,
          enabled: _selectedBarcode != null,
          readOnly: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [
            _DateInputFormatter(),
          ],
          decoration: SharedInputDecoration.create(
            context,
            'goods_receiving_screen.label_expiry_date'.tr(),
            enabled: _selectedBarcode != null,
            suffixIcon: _expiryDateController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _selectedBarcode != null
                        ? () {
                            _expiryDateController.clear();
                            setState(() {}); // Rebuild to update suffix icon
                            _expiryDateFocusNode.requestFocus();
                          }
                        : null,
                  )
                : const Icon(Icons.edit_calendar_outlined),
            hintText: 'DD/MM/YYYY',
          ),
          validator: (value) {
            if (_selectedBarcode == null) return null;

            // Expiry date is mandatory
            if (value == null || value.isEmpty) {
              return 'goods_receiving_screen.validator_expiry_date_required'.tr();
            }

            // Use comprehensive validation
            bool isValid = DateValidationUtils.isValidExpiryDate(value);
            if (!isValid) {
              return DateValidationUtils.getDateValidationError(value);
            }

            return null;
          },
          onChanged: (value) {
            setState(() {}); // Rebuild to update suffix icon
            // DD/MM/YYYY formatı tamamlandıysa ve geçerli tarihse quantity field'a geç
            if (value.length == 10) {
              bool isValid = DateValidationUtils.isValidExpiryDate(value);
              if (isValid) {
                _onExpiryDateEntered();
              }
            }
          },
          onFieldSubmitted: (value) {
            if (value.length == 10) {
              if (DateValidationUtils.isValidExpiryDate(value)) {
                _onExpiryDateEntered();
              } else {
                // Show error message
                String errorMessage = DateValidationUtils.getDateValidationError(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  void _onExpiryDateEntered() {
    if (_expiryDateController.text.isNotEmpty && _selectedBarcode != null) {
      // Focus to quantity field
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _quantityFocusNode.requestFocus();
        }
      });
    }
  }

  Widget _buildExpiryDateAndUnitRow() {
    return Row(
      children: [
        // Expiry Date Field
        Expanded(
          child: _buildExpiryDateField(),
        ),
        const SizedBox(width: 8),
        // Unit Dropdown - always visible when product selected
        Expanded(
          child: _buildUnitDropdown(),
        ),
      ],
    );
  }

  Widget _buildUnitDropdown() {
    debugPrint('🎨 Building unit dropdown with ${_availableUnits.length} units, selected: $_selectedBirimKey');

    // ITEMS LİSTESİNİ OLUŞTUR
    final dropdownItems = _availableUnits.isNotEmpty
        ? _availableUnits.map((unit) {
            final unitName = unit['birimadi'] as String? ?? 'Birim';
            final unitKey = unit['birim_key'] as String? ?? unit['_key'] as String?;
            debugPrint('   📋 Dropdown item: $unitName (key: $unitKey)');

            if (unitKey == null) {
              debugPrint('   ⚠️ WARNING: Unit key is NULL for $unitName! Full unit data: $unit');
            }

            return DropdownMenuItem<String>(
              value: unitKey ?? 'unknown_$unitName',
              child: Text(unitName),
            );
          }).toList()
        : <DropdownMenuItem<String>>[]; // Boş liste yerine empty list

    debugPrint('   🎯 Total dropdown items created: ${dropdownItems.length}');

    return DropdownButtonFormField<String>(
      value: _selectedBirimKey,
      hint: Text('goods_receiving_screen.label_unit_selection'.tr()),
      decoration: SharedInputDecoration.create(
        context,
        'goods_receiving_screen.label_unit_selection'.tr(),
        enabled: _availableUnits.isNotEmpty,
      ),
      items: dropdownItems.isEmpty ? null : dropdownItems, // Boşsa NULL ver!
      onChanged: _availableUnits.isNotEmpty
          ? (value) {
              setState(() {
                _selectedBirimKey = value;
                debugPrint('   ✅ Unit selected: $value');
              });
            }
          : null,
      validator: (value) {
        // Eğer product mode'da ve ürün seçiliyse birim zorunlu
        if (_selectedMode.isProduct && _selectedBarcode != null && _availableUnits.isNotEmpty) {
          if (value == null || value.isEmpty) {
            return 'goods_receiving_screen.validator_unit_required'.tr();
          }
        }
        return null;
      },
    );
  }

  Widget _buildQuantityAndShelfRow() {
    return Row(
      children: [
        // Quantity field (önce miktar)
        Expanded(
          child: TextFormField(
            controller: _quantityController,
            focusNode: _quantityFocusNode,
            decoration: SharedInputDecoration.create(
              context,
              'warehouse_count.quantity'.tr(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        const SizedBox(width: 8),
        // Shelf field (sonra raf)
        Expanded(
          child: QrTextField(
            controller: _shelfController,
            focusNode: _shelfFocusNode,
            labelText: 'warehouse_count.shelf'.tr(),
            isValid: _isShelfValid,
            textCapitalization: TextCapitalization.characters, // Otomatik büyük harf
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'warehouse_count.error.enter_shelf'.tr();
              }
              return null;
            },
            onFieldSubmitted: (value) async {
              if (value.trim().isNotEmpty) {
                await _validateShelf(value.trim());
              }
            },
            onQrScanned: (result) async {
              await _validateShelf(result);
            },
            onChanged: (value) {
              // Reset validation state when user types
              if (_isShelfValid) {
                setState(() {
                  _isShelfValid = false;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: _addCountItem,
      icon: const Icon(Icons.add_circle),
      label: Text('warehouse_count.add_item'.tr()),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _countedItems.isEmpty ? null : _openReviewScreen,
          icon: const Icon(Icons.checklist_rtl),
          label: Text('warehouse_count.review_items'.tr()),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
          ),
        ),
      ),
    );
  }

  void _openReviewScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WarehouseCountReviewScreen(
          countSheet: widget.countSheet,
          countedItems: _countedItems,
          repository: widget.repository,
        ),
      ),
    );
  }
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Handle deletion - if user deletes a slash, delete the preceding digit too
    if (newValue.text.length < oldValue.text.length) {
      if (newValue.text.isNotEmpty && oldValue.text.length > newValue.text.length) {
        final deletedChar = oldValue.text[newValue.text.length];
        if (deletedChar == '/' && newValue.text.isNotEmpty) {
          return TextEditingValue(
            text: newValue.text.substring(0, newValue.text.length - 1),
            selection: TextSelection.collapsed(offset: newValue.text.length - 1),
          );
        }
      }
      return newValue;
    }

    // Only allow digits
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    if (text.length > 8) return oldValue;

    // Smart formatting with validation
    String formatted = _smartFormatDate(text);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _smartFormatDate(String digits) {
    String result = '';

    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) result += '/';

      // Add digit with smart validation
      String digit = digits[i];

      // Day validation (position 0-1)
      if (i < 2) {
        if (i == 0 && int.parse(digit) > 3) {
          digit = '3'; // Max day starts with 3
        } else if (i == 1 && result.isNotEmpty) {
          int firstDigit = int.parse(result[0]);
          int dayValue = firstDigit * 10 + int.parse(digit);
          if (dayValue > 31) {
            digit = '1'; // 31 max
          } else if (dayValue == 0) {
            digit = '1'; // Min 01
          }
        }
      }
      // Month validation (position 2-3)
      else if (i < 4) {
        int monthPos = i - 2;
        if (monthPos == 0 && int.parse(digit) > 1) {
          digit = '1'; // Max month starts with 1
        } else if (monthPos == 1) {
          String monthFirstDigit = result.split('/')[1];
          int firstDigit = int.parse(monthFirstDigit);
          int monthValue = firstDigit * 10 + int.parse(digit);
          if (monthValue > 12) {
            digit = '2'; // 12 max
          } else if (monthValue == 0) {
            digit = '1'; // Min 01
          }
        }
      }

      result += digit;
    }

    // Final validation when we have complete date (8 digits)
    if (digits.length == 8) {
      result = _validateCompleteDate(result);
    }

    return result;
  }

  String _validateCompleteDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length != 3) return dateStr;

      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);

      // Create DateTime to check validity
      final date = DateTime(year, month, day);

      // If date was adjusted, use the adjusted values
      if (date.day != day || date.month != month) {
        // DateTime adjusted it, which means original was invalid
        // Use last day of the intended month
        final lastDay = DateTime(year, month + 1, 0).day;
        day = day > lastDay ? lastDay : day;

        return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}';
      }

      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }
}
