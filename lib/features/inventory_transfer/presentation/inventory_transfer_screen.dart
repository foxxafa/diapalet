import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';

class InventoryTransferScreen extends StatefulWidget {
  const InventoryTransferScreen({super.key});

  @override
  State<InventoryTransferScreen> createState() => _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
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

  static const double _fieldHeight = 56.0;
  static const double _gap = 16.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

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
      if (mounted) _showSnackBar('Hata: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _processScannedData(String field, String data) async {
    switch (field) {
      case 'source':
        final locationName = _availableSourceLocations.keys.firstWhere(
                (k) => k.toLowerCase() == data.toLowerCase(), orElse: () => '');
        if (locationName.isNotEmpty) {
          _handleSourceSelection(locationName);
        } else {
          _sourceLocationController.clear();
          _showSnackBar("Geçersiz kaynak lokasyon kodu: $data", isError: true);
        }
        break;
      case 'container':
        dynamic foundItem;
        if (_selectedMode == AssignmentMode.pallet) {
          foundItem = _availableContainers.cast<String?>().firstWhere((id) => id == data, orElse: () => null);
        } else {
          // GÜNCELLEME: Kutu modunda hem ürün kodu hem de barkod ile ara.
          foundItem = _availableContainers.cast<BoxItem?>().firstWhere(
                  (box) => box?.productCode == data || box?.barcode1 == data,
              orElse: () => null
          );
        }

        if (foundItem != null) {
          _handleContainerSelection(foundItem);
        } else {
          _scannedContainerIdController.clear();
          _showSnackBar("Okutulan ürün/palet listede bulunamadı: $data", isError: true);
        }
        break;
      case 'target':
        final locationName = _availableTargetLocations.keys.firstWhere(
                (k) => k.toLowerCase() == data.toLowerCase(), orElse: () => '');
        if (locationName.isNotEmpty) {
          _handleTargetSelection(locationName);
        } else {
          _targetLocationController.clear();
          _showSnackBar("Geçersiz hedef lokasyon kodu: $data", isError: true);
        }
        break;
    }
  }

  void _handleSourceSelection(String? locationName) {
    if (locationName == null || locationName == _selectedSourceLocationName) return;
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
    if(_productsInContainer.isNotEmpty && _productQuantityFocusNodes.isNotEmpty) {
      _productQuantityFocusNodes[_productsInContainer.first.id]?.requestFocus();
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
      if (mounted) _showSnackBar('Konteynerler yüklenemedi: ${e.toString()}', isError: true);
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
          final initialQty = _selectedMode == AssignmentMode.pallet ? product.currentQuantity : 1.0;
          _productQuantityControllers[product.id] = TextEditingController(text: initialQty.toString());
          _productQuantityFocusNodes[product.id] = FocusNode();
        }
      });
    } catch (e) {
      if (mounted) _showSnackBar('İçerik yüklenemedi: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar('Lütfen tüm zorunlu alanları doldurun.', isError: true);
      return;
    }

    final List<TransferItemDetail> itemsToTransfer = [];
    bool isFullPalletTransfer = _selectedMode == AssignmentMode.pallet;

    for (var product in _productsInContainer) {
      final qtyText = _productQuantityControllers[product.id]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;

      if (qty > 0) {
        if (qty.toStringAsFixed(2) != product.currentQuantity.toStringAsFixed(2)) {
          isFullPalletTransfer = false;
        }
        itemsToTransfer.add(TransferItemDetail(
          productId: product.id,
          productName: product.name,
          productCode: product.productCode,
          quantity: qty,
          sourcePalletBarcode: _selectedMode == AssignmentMode.pallet ? (_selectedContainer as String) : null,
        ));
      }
    }

    if (itemsToTransfer.isEmpty) {
      _showSnackBar('Transfer edilecek ürün veya miktar seçilmedi.', isError: true);
      return;
    }

    final finalOperationMode = _selectedMode == AssignmentMode.pallet
        ? (isFullPalletTransfer ? AssignmentMode.pallet : AssignmentMode.box_from_pallet)
        : AssignmentMode.box;

    final confirm = await _showConfirmationDialog(itemsToTransfer, finalOperationMode);
    if (confirm != true) return;

    final sourceId = _availableSourceLocations[_selectedSourceLocationName!];
    final targetId = _availableTargetLocations[_selectedTargetLocationName!];

    if (sourceId == null || targetId == null) {
      _showSnackBar("Lokasyon ID'leri bulunamadı. İşlem iptal edildi.", isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final header = TransferOperationHeader(
        operationType: finalOperationMode,
        sourceLocationName: _selectedSourceLocationName!,
        targetLocationName: _selectedTargetLocationName!,
        containerId: (_selectedContainer is String) ? _selectedContainer : (_selectedContainer as BoxItem?)?.productCode,
        transferDate: DateTime.now(),
      );

      await _repo.recordTransferOperation(header, itemsToTransfer, sourceId, targetId);

      if (mounted) {
        _showSnackBar('Transfer başarıyla kaydedildi.');
        _resetForm(resetAll: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Kaydetme hatası: ${e.toString()}', isError: true);
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
    return Scaffold(
      appBar: SharedAppBar(title: 'Stok Transferi'),
      bottomNavigationBar: _buildBottomBar(),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: _isLoadingInitialData
              ? const Center(child: CircularProgressIndicator())
              : Padding(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildModeSelector(),
                    const SizedBox(height: _gap),
                    _buildHybridDropdownWithQr<String>(
                      controller: _sourceLocationController,
                      focusNode: _sourceLocationFocusNode,
                      label: "1. Kaynak Lokasyon",
                      fieldIdentifier: 'source',
                      items: _availableSourceLocations.keys.toList(),
                      itemToString: (item) => item,
                      onItemSelected: _handleSourceSelection,
                    ),
                    const SizedBox(height: _gap),
                    _buildHybridDropdownWithQr<dynamic>(
                      controller: _scannedContainerIdController,
                      focusNode: _containerFocusNode,
                      label: "2. ${_selectedMode == AssignmentMode.pallet ? 'Palet' : 'Ürün'}",
                      fieldIdentifier: 'container',
                      items: _availableContainers,
                      itemToString: (item) {
                        if (item is String) return item;
                        if (item is BoxItem) return '${item.productName} (${item.productCode})';
                        return '';
                      },
                      onItemSelected: _handleContainerSelection,
                    ),
                    const SizedBox(height: _smallGap),
                    if (_isLoadingContainerContents)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: _gap),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_productsInContainer.isNotEmpty)
                      _buildProductsList()
                    else
                      const SizedBox.shrink(),

                    const SizedBox(height: _gap),
                    _buildHybridDropdownWithQr<String>(
                      controller: _targetLocationController,
                      focusNode: _targetLocationFocusNode,
                      label: "3. Hedef Lokasyon",
                      fieldIdentifier: 'target',
                      items: _availableTargetLocations.keys.toList(),
                      itemToString: (item) => item,
                      onItemSelected: _handleTargetSelection,
                    ),
                  ],
                ),
              ),
            ),
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
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            decoration: _inputDecoration(label, suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              tooltip: 'Listeden Seç',
              onPressed: () async {
                final T? selectedItem = await _showSearchableDropdownDialog<T>(
                  title: label,
                  items: items,
                  itemToString: itemToString,
                );
                if (selectedItem != null) {
                  onItemSelected(selectedItem);
                }
              },
            )),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) {
                _processScannedData(fieldIdentifier, value);
              }
            },
            validator: (val) {
              if (val == null || val.isEmpty) return 'Bu alan zorunludur.';
              if (fieldIdentifier == 'target' && val == _sourceLocationController.text) {
                return 'Kaynak ile aynı olamaz!';
              }
              return null;
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(
            onTap: () async {
              final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
              if (result != null && result.isNotEmpty) {
                controller.text = result;
                _processScannedData(fieldIdentifier, result);
              }
            },
            size: _fieldHeight
        ),
      ],
    );
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
  }) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        final filteredItems = ValueNotifier<List<T>>(items);
        return AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 5),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15.0),
                  child: TextField(
                    autofocus: true,
                    decoration: _inputDecoration('Ara...').copyWith(prefixIcon: const Icon(Icons.search)),
                    onChanged: (value) {
                      filteredItems.value = items
                          .where((item) => itemToString(item)
                          .toLowerCase()
                          .contains(value.toLowerCase()))
                          .toList();
                    },
                  ),
                ),
                const SizedBox(height: _gap),
                Flexible(
                  child: ValueListenableBuilder<List<T>>(
                    valueListenable: filteredItems,
                    builder: (context, value, child) {
                      return value.isEmpty
                          ? const Center(child: Text('Sonuç bulunamadı.'))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: value.length,
                        itemBuilder: (context, index) {
                          final item = value[index];
                          return ListTile(
                            title: Text(itemToString(item)),
                            onTap: () => Navigator.of(dialogContext).pop(item),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('İptal'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: const [
          ButtonSegment(value: AssignmentMode.pallet, label: Text('Palet'), icon: Icon(Icons.pallet)),
          ButtonSegment(value: AssignmentMode.box, label: Text('Kutu'), icon: Icon(Icons.inventory_2_outlined)),
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
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(75),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    return Container(
      margin: const EdgeInsets.only(top: _smallGap),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(120)),
        borderRadius: _borderRadius,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.2).round()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'İçerik: ${_scannedContainerIdController.text}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(_smallGap),
            itemCount: _productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(height: _smallGap, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final product = _productsInContainer[index];
              final controller = _productQuantityControllers[product.id]!;
              final focusNode = _productQuantityFocusNodes[product.id]!;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                          Text('${product.productCode} - Mevcut: ${product.currentQuantity}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: _gap),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        decoration: _inputDecoration('Miktar', filled: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Gerekli';
                          final qty = double.tryParse(value);
                          if (qty == null) return 'Geçersiz';
                          if (qty > product.currentQuantity) return 'Max!';
                          if (qty < 0) return 'Negatif!';
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          final productIds = _productQuantityFocusNodes.keys.toList();
                          final currentIndex = productIds.indexOf(product.id);
                          if (currentIndex < productIds.length - 1) {
                            _productQuantityFocusNodes[productIds[currentIndex + 1]]?.requestFocus();
                          } else {
                            _targetLocationFocusNode.requestFocus();
                          }
                        },
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final double bottomNavHeight = (MediaQuery.of(context).size.height * 0.09).clamp(70.0, 90.0);
    return _isLoadingInitialData
        ? const SizedBox.shrink()
        : Container(
      padding: const EdgeInsets.all(20).copyWith(top: 10),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _onConfirmSave,
        icon: _isSaving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle_outline),
        label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
        style: ElevatedButton.styleFrom(
          minimumSize: Size(double.infinity, bottomNavHeight - 20),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green[600],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
      margin: const EdgeInsets.all(20),
    ));
  }

  Future<bool?> _showConfirmationDialog(List<TransferItemDetail> items, AssignmentMode mode) async {
    return showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Transferi Onayla (${mode.name})'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aşağıdaki ürünler ${_selectedSourceLocationName} -> ${_selectedTargetLocationName} arasına transfer edilecek:'),
            const Divider(height: 20),
            SizedBox(
              height: 150,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Text('• ${item.productName} (x${item.quantity})');
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(child: const Text('İptal'), onPressed: () => Navigator.of(ctx).pop(false)),
        ElevatedButton(child: const Text('Onayla'), onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    ));
  }

  InputDecoration _inputDecoration(String labelText, {Widget? suffixIcon, bool filled = false}) {
    return InputDecoration(
      labelText: labelText,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2.0),
      ),
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: (_fieldHeight - 24) / 2),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(fontSize: 10, height: 0.8),
      helperText: ' ',
      helperStyle: const TextStyle(fontSize: 0, height: 0.01),
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const _QrButton({required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }
}
