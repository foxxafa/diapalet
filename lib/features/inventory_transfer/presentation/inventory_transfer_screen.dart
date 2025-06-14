// lib/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';

class InventoryTransferScreen extends StatefulWidget {
  const InventoryTransferScreen({super.key});

  @override
  State<InventoryTransferScreen> createState() =>
      _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  // --- Sabitler ve Stil Değişkenleri ---
  static const double _gap = 12.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

  // --- State ve Controller'lar ---
  final _formKey = GlobalKey<FormState>();
  late InventoryTransferRepository _repo;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;

  Map<String, int> _availableSourceLocations = {};
  String? _selectedSourceLocationName;
  final _sourceLocationController = TextEditingController();
  final _sourceLocationFocusNode = FocusNode();

  Map<String, int> _availableTargetLocations = {};
  String? _selectedTargetLocationName;
  final _targetLocationController = TextEditingController();
  final _targetLocationFocusNode = FocusNode();

  List<dynamic> _availableContainers = [];
  dynamic _selectedContainer;
  final _scannedContainerIdController = TextEditingController();
  final _containerFocusNode = FocusNode();

  List<ProductItem> _productsInContainer = [];
  final Map<int, TextEditingController> _productQuantityControllers = {};
  final Map<int, FocusNode> _productQuantityFocusNodes = {};


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _sourceLocationController.dispose();
    _targetLocationController.dispose();
    _scannedContainerIdController.dispose();
    _sourceLocationFocusNode.dispose();
    _targetLocationFocusNode.dispose();
    _containerFocusNode.dispose();
    _clearProductControllers();
    super.dispose();
  }

  void _clearProductControllers() {
    _productQuantityControllers.forEach((_, controller) => controller.dispose());
    _productQuantityFocusNodes.forEach((_, focusNode) => focusNode.dispose());
    _productQuantityControllers.clear();
    _productQuantityFocusNodes.clear();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoadingInitialData = true);
    try {
      final results = await Future.wait([
        _repo.getSourceLocations(),
        _repo.getTargetLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _availableSourceLocations = results[0];
        _availableTargetLocations = results[1];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_sourceLocationFocusNode);
      });
    } catch (e) {
      if (mounted) _showErrorSnackBar('Hata: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _processScannedData(String field, String data) async {
    switch (field) {
      case 'source':
        final locationName = _availableSourceLocations.keys.firstWhere(
                (k) => k.toLowerCase() == data.toLowerCase(),
            orElse: () => '');
        if (locationName.isNotEmpty) {
          _handleSourceSelection(locationName);
        } else {
          _sourceLocationController.clear();
          _showErrorSnackBar("Geçersiz kaynak lokasyon kodu: $data");
        }
        break;
      case 'container':
        dynamic foundItem;
        if (_selectedMode == AssignmentMode.pallet) {
          foundItem = _availableContainers
              .cast<String?>()
              .firstWhere((id) => id == data, orElse: () => null);
        } else {
          foundItem = _availableContainers.cast<BoxItem?>().firstWhere(
                  (box) => box?.productCode == data || box?.barcode1 == data,
              orElse: () => null);
        }

        if (foundItem != null) {
          _handleContainerSelection(foundItem);
        } else {
          _scannedContainerIdController.clear();
          _showErrorSnackBar(
              "Okutulan ürün/palet listede bulunamadı: $data");
        }
        break;
      case 'target':
        final locationName = _availableTargetLocations.keys.firstWhere(
                (k) => k.toLowerCase() == data.toLowerCase(),
            orElse: () => '');
        if (locationName.isNotEmpty) {
          _handleTargetSelection(locationName);
        } else {
          _targetLocationController.clear();
          _showErrorSnackBar("Geçersiz hedef lokasyon kodu: $data");
        }
        break;
    }
  }

  void _handleSourceSelection(String? locationName) {
    if (locationName == null || locationName == _selectedSourceLocationName) {
      return;
    }
    setState(() {
      _selectedSourceLocationName = locationName;
      _sourceLocationController.text = locationName;
    });
    _loadContainersForLocation();
    _containerFocusNode.requestFocus();
  }

  Future<void> _handleContainerSelection(dynamic selectedItem) async {
    if (selectedItem == null) return;
    setState(() {
      _selectedContainer = selectedItem;
      _scannedContainerIdController.text = (selectedItem is BoxItem)
          ? '${selectedItem.productName} (${selectedItem.productCode})'
          : selectedItem.toString();
    });
    await _fetchContainerContents();
    if (_productsInContainer.isNotEmpty &&
        _productQuantityFocusNodes.isNotEmpty) {
      _productQuantityFocusNodes[_productsInContainer.first.id]
          ?.requestFocus();
    } else {
      _targetLocationFocusNode.requestFocus();
    }
  }

  void _handleTargetSelection(String? locationName) {
    if (locationName == null) return;
    setState(() {
      _selectedTargetLocationName = locationName;
      _targetLocationController.text = locationName;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _loadContainersForLocation() async {
    if (_selectedSourceLocationName == null) return;
    final locationId = _availableSourceLocations[_selectedSourceLocationName];
    if (locationId == null) return;

    setState(() {
      _isLoadingContainerContents = true;
      _resetContainerAndProducts();
    });
    try {
      if (_selectedMode == AssignmentMode.pallet) {
        _availableContainers = await _repo.getPalletIdsAtLocation(locationId);
      } else {
        _availableContainers = await _repo.getBoxesAtLocation(locationId);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Konteynerler yüklenemedi: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }

  Future<void> _fetchContainerContents() async {
    final container = _selectedContainer;
    if (container == null) return;

    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
      _clearProductControllers();
    });

    try {
      List<ProductItem> contents = [];
      if (_selectedMode == AssignmentMode.pallet && container is String) {
        contents = await _repo.getPalletContents(container);
      } else if (_selectedMode == AssignmentMode.box && container is BoxItem) {
        contents = [ProductItem.fromBoxItem(container)];
      }

      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        for (var product in contents) {
          final initialQty = _selectedMode == AssignmentMode.pallet
              ? product.currentQuantity
              : 1.0;
          _productQuantityControllers[product.id] =
              TextEditingController(text: initialQty.toString());
          _productQuantityFocusNodes[product.id] = FocusNode();
        }
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('İçerik yüklenemedi: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showErrorSnackBar('Lütfen tüm zorunlu alanları doldurun.');
      return;
    }

    final List<TransferItemDetail> itemsToTransfer = [];
    bool isFullPalletTransfer = _selectedMode == AssignmentMode.pallet;

    for (var product in _productsInContainer) {
      final qtyText = _productQuantityControllers[product.id]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;

      if (qty > 0) {
        if (qty.toStringAsFixed(2) !=
            product.currentQuantity.toStringAsFixed(2)) {
          isFullPalletTransfer = false;
        }
        itemsToTransfer.add(TransferItemDetail(
          productId: product.id,
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          sourcePalletBarcode: _selectedMode == AssignmentMode.pallet
              ? (_selectedContainer as String)
              : null,
        ));
      }
    }

    if (itemsToTransfer.isEmpty) {
      _showErrorSnackBar('Transfer edilecek ürün veya miktar seçilmedi.');
      return;
    }

    final finalOperationMode = _selectedMode == AssignmentMode.pallet
        ? (isFullPalletTransfer
        ? AssignmentMode.pallet
        : AssignmentMode.box_from_pallet)
        : AssignmentMode.box;

    final confirm =
    await _showConfirmationDialog(itemsToTransfer, finalOperationMode);
    if (confirm != true) return;

    final sourceId = _availableSourceLocations[_selectedSourceLocationName!];
    final targetId = _availableTargetLocations[_selectedTargetLocationName!];

    if (sourceId == null || targetId == null) {
      _showErrorSnackBar(
          "Lokasyon ID'leri bulunamadı. İşlem iptal edildi.");
      return;
    }

    setState(() => _isSaving = true);
    try {
      final header = TransferOperationHeader(
        operationType: finalOperationMode,
        sourceLocationName: _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
        containerId: (_selectedContainer is String)
            ? _selectedContainer
            : (_selectedContainer as BoxItem?)?.productCode,
        transferDate: DateTime.now(),
      );

      await _repo.recordTransferOperation(
          header, itemsToTransfer, sourceId, targetId);

      if (mounted) {
        _showSuccessSnackBar('Transfer başarıyla kaydedildi.');
        _resetForm(resetAll: true);
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Kaydetme hatası: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetContainerAndProducts() {
    _scannedContainerIdController.clear();
    _productsInContainer = [];
    _selectedContainer = null;
    _clearProductControllers();
    _availableContainers = [];
  }

  void _resetForm({bool resetAll = false}) {
    setState(() {
      _resetContainerAndProducts();
      if (resetAll) {
        _selectedSourceLocationName = null;
        _sourceLocationController.clear();
        _selectedTargetLocationName = null;
        _targetLocationController.clear();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.reset();
        FocusScope.of(context).requestFocus(_sourceLocationFocusNode);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // --- Responsive Boyutlandırma ---
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final bool isKeyboardVisible = mediaQuery.viewInsets.bottom > 0;

    // YÜKSEKLİKLER (Mal Kabul ile aynı)
    final appBarHeight = screenHeight * 0.07;
    final inputRowHeight = screenHeight * 0.075;
    final segmentedButtonHeight = screenHeight * 0.07;
    final buttonHeight = screenHeight * 0.09;

    // Dinamik Font ve Ikon Boyutları
    final sizeFactor = (screenWidth / 480.0).clamp(0.9, 1.3);

    final appBarFontSize = 19.0 * sizeFactor;
    final labelFontSize = 15.0 * sizeFactor;
    final buttonFontSize = 16.0 * sizeFactor;
    final contentTitleFontSize = 15.0 * sizeFactor;
    final contentTextFontSize = 13.0 * sizeFactor;
    final segmentedButtonFontSize = 13.0 * sizeFactor;
    final errorFontSize = 11.0 * sizeFactor;

    final baseIconSize = 24.0 * sizeFactor;
    final qrIconSize = 28.0 * sizeFactor;
    final segmentedButtonIconSize = 20.0 * sizeFactor;

    return Scaffold(
      appBar: SharedAppBar(
        title: 'Stok Transferi',
        preferredHeight: appBarHeight,
        titleFontSize: appBarFontSize,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: isKeyboardVisible
          ? null
          : _buildBottomBar(
          height: buttonHeight,
          fontSize: buttonFontSize,
          iconSize: baseIconSize),
      body: SafeArea(
        child: _isLoadingInitialData
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: _gap),
                  _buildModeSelector(
                    height: segmentedButtonHeight,
                    fontSize: segmentedButtonFontSize,
                    iconSize: segmentedButtonIconSize,
                  ),
                  const SizedBox(height: _gap),
                  _buildHybridDropdownWithQr<String>(
                    controller: _sourceLocationController,
                    focusNode: _sourceLocationFocusNode,
                    label: "1. Kaynak Lokasyon",
                    fieldIdentifier: 'source',
                    items: _availableSourceLocations.keys.toList(),
                    itemToString: (item) => item,
                    onItemSelected: _handleSourceSelection,
                    height: inputRowHeight,
                    labelFontSize: labelFontSize,
                    errorFontSize: errorFontSize,
                    qrIconSize: qrIconSize,
                    filterCondition: (item, query) => item
                        .toLowerCase()
                        .contains(query.toLowerCase()),
                  ),
                  const SizedBox(height: _gap),
                  _buildHybridDropdownWithQr<dynamic>(
                    controller: _scannedContainerIdController,
                    focusNode: _containerFocusNode,
                    label:
                    "2. ${_selectedMode == AssignmentMode.pallet ? 'Palet' : 'Ürün'}",
                    fieldIdentifier: 'container',
                    items: _availableContainers,
                    itemToString: (item) {
                      if (item is String) return item;
                      if (item is BoxItem) {
                        return '${item.productName} (${item.productCode})';
                      }
                      return '';
                    },
                    onItemSelected: _handleContainerSelection,
                    height: inputRowHeight,
                    labelFontSize: labelFontSize,
                    errorFontSize: errorFontSize,
                    qrIconSize: qrIconSize,
                    filterCondition: (item, query) {
                      final lowerQuery = query.toLowerCase();
                      if (item is String) {
                        return item.toLowerCase().contains(lowerQuery);
                      }
                      if (item is BoxItem) {
                        return item.productName
                            .toLowerCase()
                            .contains(lowerQuery) ||
                            item.productCode
                                .toLowerCase()
                                .contains(lowerQuery) ||
                            (item.barcode1
                                ?.toLowerCase()
                                .contains(lowerQuery) ??
                                false);
                      }
                      return false;
                    },
                  ),
                  const SizedBox(height: _gap),
                  if (_isLoadingContainerContents)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: _gap),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_productsInContainer.isNotEmpty)
                    _buildProductsList(
                      titleFontSize: contentTitleFontSize,
                      textFontSize: contentTextFontSize,
                      labelFontSize: labelFontSize,
                      errorFontSize: errorFontSize,
                      inputHeight: inputRowHeight,
                    ),
                  const SizedBox(height: _gap),
                  _buildHybridDropdownWithQr<String>(
                    controller: _targetLocationController,
                    focusNode: _targetLocationFocusNode,
                    label: "3. Hedef Lokasyon",
                    fieldIdentifier: 'target',
                    items: _availableTargetLocations.keys.toList(),
                    itemToString: (item) => item,
                    onItemSelected: _handleTargetSelection,
                    height: inputRowHeight,
                    labelFontSize: labelFontSize,
                    errorFontSize: errorFontSize,
                    qrIconSize: qrIconSize,
                    filterCondition: (item, query) => item
                        .toLowerCase()
                        .contains(query.toLowerCase()),
                  ),
                  const SizedBox(height: _gap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector(
      {required double height,
        required double fontSize,
        required double iconSize}) {
    return SizedBox(
      height: height,
      child: Center(
        child: SegmentedButton<AssignmentMode>(
          segments: [
            ButtonSegment(
                value: AssignmentMode.pallet,
                label: Text('Palet', style: TextStyle(fontSize: fontSize)),
                icon: Icon(Icons.pallet, size: iconSize)),
            ButtonSegment(
                value: AssignmentMode.box,
                label: Text('Kutu', style: TextStyle(fontSize: fontSize)),
                icon: Icon(Icons.inventory_2_outlined, size: iconSize)),
          ],
          selected: {_selectedMode},
          onSelectionChanged: (newSelection) {
            setState(() {
              _selectedMode = newSelection.first;
              _resetContainerAndProducts();
              if (_selectedSourceLocationName != null) {
                _loadContainersForLocation();
              }
            });
          },
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.comfortable,
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withAlpha(75),
            selectedBackgroundColor: Theme.of(context).colorScheme.primary,
            selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          ),
        ),
      ),
    );
  }

  Widget _buildHybridDropdownWithQr<T>({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String fieldIdentifier,
    required List<T> items,
    required String Function(T item) itemToString,
    required void Function(T? item) onItemSelected,
    required bool Function(T item, String query) filterCondition,
    required double height,
    required double labelFontSize,
    required double errorFontSize,
    required double qrIconSize,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(fontSize: labelFontSize),
              textAlignVertical: TextAlignVertical.center,
              decoration: _inputDecoration(
                label,
                labelFontSize: labelFontSize,
                errorFontSize: errorFontSize,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  tooltip: 'Listeden Seç',
                  onPressed: () async {
                    final T? selectedItem =
                    await _showSearchableDropdownDialog<T>(
                      title: label,
                      items: items,
                      itemToString: itemToString,
                      filterCondition: filterCondition,
                    );
                    if (selectedItem != null) {
                      onItemSelected(selectedItem);
                    }
                  },
                ),
              ),
              onFieldSubmitted: (value) {
                if (value.isNotEmpty) {
                  _processScannedData(fieldIdentifier, value);
                }
              },
              validator: (val) {
                if (val == null || val.isEmpty) return 'Bu alan zorunludur.';
                if (fieldIdentifier == 'target' &&
                    val == _sourceLocationController.text) {
                  return 'Kaynak ile aynı olamaz!';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () async {
              final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const QrScannerScreen()));
              if (result != null && result.isNotEmpty) {
                controller.text = result;
                _processScannedData(fieldIdentifier, result);
              }
            },
            size: height,
            iconSize: qrIconSize,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList({
    required double titleFontSize,
    required double textFontSize,
    required double labelFontSize,
    required double errorFontSize,
    required double inputHeight,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: _smallGap),
      decoration: BoxDecoration(
        border:
        Border.all(color: Theme.of(context).dividerColor.withAlpha(120)),
        borderRadius: _borderRadius,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withAlpha((255 * 0.2).round()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'İçerik: ${_scannedContainerIdController.text}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, fontSize: titleFontSize),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(_smallGap),
            itemCount: _productsInContainer.length,
            separatorBuilder: (context, index) =>
            const Divider(height: _smallGap, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final product = _productsInContainer[index];
              final controller = _productQuantityControllers[product.id]!;
              final focusNode = _productQuantityFocusNodes[product.id]!;
              return Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: SizedBox(
                  height: inputHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: textFontSize),
                                overflow: TextOverflow.ellipsis),
                            Text(
                                '${product.productCode} - Mevcut: ${product.currentQuantity}',
                                style:
                                TextStyle(fontSize: textFontSize * 0.9)),
                          ],
                        ),
                      ),
                      const SizedBox(width: _gap),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.25,
                        child: TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: labelFontSize),
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          decoration: _inputDecoration('Miktar',
                              labelFontSize: labelFontSize,
                              errorFontSize: errorFontSize),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Gerekli';
                            }
                            final qty = double.tryParse(value);
                            if (qty == null) return 'Geçersiz';
                            if (qty > product.currentQuantity) return 'Max!';
                            if (qty < 0) return 'Negatif!';
                            return null;
                          },
                          onFieldSubmitted: (value) {
                            final productIds =
                            _productQuantityFocusNodes.keys.toList();
                            final currentIndex = productIds.indexOf(product.id);
                            if (currentIndex < productIds.length - 1) {
                              _productQuantityFocusNodes[
                              productIds[currentIndex + 1]]
                                  ?.requestFocus();
                            } else {
                              _targetLocationFocusNode.requestFocus();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
      {required double height,
        required double fontSize,
        required double iconSize}) {
    if (_isLoadingInitialData) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: SizedBox(
        height: height,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _onConfirmSave,
          icon: _isSaving
              ? const SizedBox(
              width: 20,
              height: 20,
              child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(Icons.check_circle_outline, size: iconSize),
          label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet',
              style: TextStyle(fontSize: fontSize)),
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, height),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle:
            TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      String label, {
        Widget? suffixIcon,
        bool enabled = true,
        required double labelFontSize,
        required double errorFontSize,
      }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: labelFontSize),
      filled: true,
      fillColor: enabled
          ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(75)
          : Colors.grey.shade200,
      errorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide:
        BorderSide(color: Theme.of(context).colorScheme.error, width: 2.0),
      ),
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide:
        BorderSide(color: Theme.of(context).dividerColor.withAlpha(180)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      errorStyle: const TextStyle(height: 0, fontSize: 0),
    );
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
  }) {
    String searchQuery = '';

    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredItems =
            items.where((item) => filterCondition(item, searchQuery)).toList();

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 40,
                  left: 16,
                  right: 16),
              child: Center(
                child: Material(
                  borderRadius: _borderRadius,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    height: MediaQuery.of(context).size.height * 0.7,
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(title,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: _gap),
                        TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Ara...',
                            prefixIcon: const Icon(Icons.search),
                            border:
                            OutlineInputBorder(borderRadius: _borderRadius),
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              searchQuery = value;
                            });
                          },
                        ),
                        const SizedBox(height: _gap),
                        Expanded(
                          child: filteredItems.isEmpty
                              ? const Center(child: Text('Sonuç bulunamadı.'))
                              : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return ListTile(
                                title: Text(itemToString(item)),
                                onTap: () =>
                                    Navigator.of(dialogContext).pop(item),
                              );
                            },
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            child: const Text('İptal'),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showConfirmationDialog(
      List<TransferItemDetail> items, AssignmentMode mode) async {
    return showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Transferi Onayla (${mode.name})'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Aşağıdaki ürünler ${_selectedSourceLocationName} -> ${_selectedTargetLocationName} arasına transfer edilecek:'),
                const Divider(height: 20),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Text(
                          '• ${item.productName} (x${item.quantity})');
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                child: const Text('İptal'),
                onPressed: () => Navigator.of(ctx).pop(false)),
            ElevatedButton(
                child: const Text('Onayla'),
                onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        ));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool isEnabled;
  final double iconSize;

  const _QrButton(
      {required this.onTap,
        required this.size,
        this.isEnabled = true,
        required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: isEnabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade300;
            }
            return Theme.of(context).colorScheme.secondaryContainer;
          }),
        ),
        child: Icon(Icons.qr_code_scanner, size: iconSize),
      ),
    );
  }
}
