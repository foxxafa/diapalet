import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/product_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';

// DÜZELTME: Sınıf adı "InventoryTransferScreen" olarak değiştirildi ve gereksiz "syncService" kaldırıldı.
class InventoryTransferScreen extends StatefulWidget {
  const InventoryTransferScreen({
    super.key,
  });

  @override
  State<InventoryTransferScreen> createState() => _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  late InventoryTransferRepository _repo;
  bool _isRepoInitialized = false;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;

  List<String> _availableSourceLocations = [];
  String? _selectedSourceLocation;
  final TextEditingController _sourceLocationController = TextEditingController();

  List<String> _availableContainerIds = [];
  bool _isLoadingContainerIds = false;
  Map<String, BoxItem> _boxItems = {}; // boxId -> BoxItem mapping
  String? _selectedContainerId; // stores the actual container ID

  final TextEditingController _scannedContainerIdController = TextEditingController();
  List<ProductItem> _productsInContainer = [];
  final TextEditingController _transferQuantityController = TextEditingController();

  List<String> _availableTargetLocations = [];
  String? _selectedTargetLocation;
  final TextEditingController _targetLocationController = TextEditingController();

  static const double _fieldHeight = 56.0;
  static const double _gap = 16.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

  @override
  void initState() {
    super.initState();
    _scannedContainerIdController.addListener(_onScannedIdChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
    });
  }

  void _onScannedIdChange() {
    if (_scannedContainerIdController.text.isEmpty && _productsInContainer.isNotEmpty) {
      if (mounted) {
        setState(() {
          _productsInContainer = [];
          _transferQuantityController.clear();
          _selectedContainerId = null;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      _loadInitialData();
      _isRepoInitialized = true;
    }
  }

  @override
  void dispose() {
    _scannedContainerIdController.removeListener(_onScannedIdChange);
    _scannedContainerIdController.dispose();
    _sourceLocationController.dispose();
    _targetLocationController.dispose();
    _transferQuantityController.dispose();
    super.dispose();
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
        _availableSourceLocations = List<String>.from(results[0]);
        _availableTargetLocations = List<String>.from(results[1]);
      });
      await _loadContainerIdsForLocation();
    } catch (e) {
      if (mounted) _showSnackBar(tr('pallet_assignment.load_error', namedArgs: {'error': e.toString()}), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialData = false);
      }
    }
  }

  Future<void> _loadContainerIdsForLocation() async {
    if (_selectedSourceLocation == null) {
      if (mounted) {
        setState(() {
          _availableContainerIds = [];
          _boxItems = {};
        });
      }
      return;
    }
    setState(() => _isLoadingContainerIds = true);
    try {
      if (_selectedMode == AssignmentMode.box) {
        final boxes = await _repo.getBoxesAtLocation(_selectedSourceLocation!);
        if (mounted) {
          setState(() {
            _availableContainerIds =
                boxes.map((b) => b.boxId.toString()).toList();
            _boxItems = {for (var b in boxes) b.boxId.toString(): b};
          });
        }
      } else {
        final ids = await _repo.getPalletIdsAtLocation(_selectedSourceLocation!);
        if (mounted) {
          setState(() {
            _availableContainerIds = ids;
            _boxItems = {};
          });
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar(tr('pallet_assignment.load_error', namedArgs: {'error': e.toString()}), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingContainerIds = false);
      }
    }
  }

  Future<void> _fetchContainerContents() async {
    FocusScope.of(context).unfocus();
    final containerId = _selectedContainerId ?? '';
    if (containerId.isEmpty) {
      _showSnackBar(tr('pallet_assignment.container_empty', namedArgs: {
        'mode': _selectedMode.displayName
      }), isError: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
    });
    try {
      if (_selectedMode == AssignmentMode.box) {
        final box = _boxItems[containerId];
        if (box == null) {
          _showSnackBar(tr('pallet_assignment.contents_empty', namedArgs: {
            'mode': _selectedMode.displayName
          }), isError: true);
        } else {
          setState(() {
            _productsInContainer = [
              ProductItem(
                id: box.productId,
                name: box.productName,
                productCode: box.productCode,
                currentQuantity: box.quantity,
              )
            ];
            _transferQuantityController.text = box.quantity.toString();
            _scannedContainerIdController.text =
            '${box.productName} • ${box.productCode} • ${box.quantity} pcs';
          });
        }
      } else {
        final contents = await _repo.getPalletContents(containerId);
        if (!mounted) return;
        setState(() {
          _productsInContainer = contents;
          _transferQuantityController.clear();
          if (contents.isEmpty && containerId.isNotEmpty) {
            _showSnackBar(tr('pallet_assignment.contents_empty', namedArgs: {
              'mode': _selectedMode.displayName
            }), isError: true);
          }
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar(tr('pallet_assignment.load_error', namedArgs: {'error': e.toString()}), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingContainerContents = false);
      }
    }
  }

  void _resetForm({bool resetAll = true}) {
    _formKey.currentState?.reset();
    _scannedContainerIdController.clear();
    if (mounted) {
      setState(() {
        _productsInContainer = [];
        _transferQuantityController.clear();
        _selectedContainerId = null;
        _boxItems = {};
        if (resetAll) {
          _selectedMode = AssignmentMode.pallet;
          _selectedSourceLocation = null;
          _sourceLocationController.clear();
          _selectedTargetLocation = null;
          _targetLocationController.clear();
          _availableContainerIds = [];
        }
      });
    }
  }

  Future<void> _scanQrAndUpdateField(String fieldIdentifier) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      String successMessage = "";
      bool found = false;
      if (fieldIdentifier == 'source') {
        if (_availableSourceLocations.contains(result)) {
          setState(() {
            _selectedSourceLocation = result;
            _sourceLocationController.text = result;
            _scannedContainerIdController.clear();
            _selectedContainerId = null;
          });
          successMessage = tr('pallet_assignment.qr_source_selected', namedArgs: {'val': result});
          found = true;
          await _loadContainerIdsForLocation();
        } else {
          _showSnackBar(tr('pallet_assignment.invalid_source_qr', namedArgs: {'qr': result}), isError: true);
        }
      } else if (fieldIdentifier == 'scannedId') {
        _selectedContainerId = result;
        setState(() {
          _scannedContainerIdController.text = _selectedMode == AssignmentMode.box
              ? (_boxItems[result] != null
              ? '${_boxItems[result]!.productName} • ${_boxItems[result]!.productCode} • ${_boxItems[result]!.quantity} pcs'
              : result)
              : result;
        });
        successMessage = tr('pallet_assignment.qr_container_selected', namedArgs: {'mode': _selectedMode.displayName, 'val': result});
        found = true;
        await _fetchContainerContents();
      } else if (fieldIdentifier == 'target') {
        if (_availableTargetLocations.contains(result)) {
          setState(() {
            _selectedTargetLocation = result;
            _targetLocationController.text = result;
          });
          successMessage = tr('pallet_assignment.qr_target_selected', namedArgs: {'val': result});
          found = true;
        } else {
          _showSnackBar(tr('pallet_assignment.invalid_target_qr', namedArgs: {'qr': result}), isError: true);
        }
      }
      if (found && successMessage.isNotEmpty) _showSnackBar(successMessage);
      _formKey.currentState?.validate();
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar(tr('pallet_assignment.form_invalid'), isError: true);
      return;
    }

    List<TransferItemDetail> itemsToTransferDetails;
    if (_selectedMode == AssignmentMode.box) {
      if (_productsInContainer.isEmpty) {
        _showSnackBar(tr('pallet_assignment.contents_empty', namedArgs: {'mode': _selectedMode.displayName}), isError: true);
        return;
      }
      final product = _productsInContainer.first; // Kutu modunda listede tek ürün olmalı
      final qty = int.tryParse(_transferQuantityController.text) ?? 0;

      // Transfer edilecek miktar sıfırdan büyük olmalı
      if (qty <= 0) {
        _showSnackBar(tr('pallet_assignment.amount_positive'), isError: true);
        return;
      }
      // Transfer edilecek miktar mevcut miktarı aşmamalı
      if (qty > product.currentQuantity) {
        _showSnackBar(tr('pallet_assignment.amount_max', namedArgs: {'max': product.currentQuantity.toString()}), isError: true);
        return;
      }

      itemsToTransferDetails = [
        TransferItemDetail(
          operationId: 0,
          productId: product.id, // ProductItem'ın 'id' alanı productId'yi temsil eder
          productCode: product.productCode,
          productName: product.name,
          quantity: qty,
        )
      ];
    } else { // Palet modu
      itemsToTransferDetails = _productsInContainer
          .map((p) => TransferItemDetail(
        operationId: 0,
        productId: p.id, // ProductItem'ın 'id' alanı productId'yi temsil eder
        productCode: p.productCode,
        productName: p.name,
        quantity: p.currentQuantity,
      ))
          .toList();
    }

    if (itemsToTransferDetails.isEmpty) {
      _showSnackBar(tr('pallet_assignment.contents_empty', namedArgs: {'mode': _selectedMode.displayName}), isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      final header = TransferOperationHeader(
        operationType: _selectedMode,
        sourceLocationName: _selectedSourceLocation!,
        targetLocationName: _selectedTargetLocation!,
        containerId: _selectedContainerId!,
        transferDate: DateTime.now(),
      );

      await _repo.recordTransferOperation(header, itemsToTransferDetails);

      if (mounted) {
        String msg;
        if (_selectedMode == AssignmentMode.box && _productsInContainer.isNotEmpty) {
          msg = tr('pallet_assignment.transfer_saved_box', namedArgs: {'product': _productsInContainer.first.name});
        } else {
          msg = tr('pallet_assignment.transfer_saved', namedArgs: {'mode': _selectedMode.displayName});
        }
        _showSnackBar(msg);
        _resetForm(resetAll: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar(tr('pallet_assignment.load_error', namedArgs: {'error': e.toString()}), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
      ),
    );
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
      errorStyle: const TextStyle(fontSize: 0, height: 0.01),
      helperText: ' ',
      helperStyle: const TextStyle(fontSize: 0, height: 0.01),
    );
  }


  Future<T?> _showSearchableDropdownDialog<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
    T? initialValue,
  }) async {
    return showDialog<T>(
      context: context,
      builder: (BuildContext dialogContext) {
        String searchText = '';
        List<T> filteredItems = List.from(items);

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            if (searchText.isNotEmpty) {
              filteredItems = items.where((item) => filterCondition(item, searchText)).toList();
            } else {
              filteredItems = List.from(items);
            }

            return AlertDialog(
              title: Text(title),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr('goods_receiving.search_hint'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: _borderRadius),
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          searchText = value;
                        });
                      },
                    ),
                    const SizedBox(height: _gap),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(child: Text('goods_receiving.search_no_result'.tr()))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        itemBuilder: (BuildContext context, int index) {
                          final item = filteredItems[index];
                          return ListTile(
                            title: Text(itemToString(item)),
                            onTap: () {
                              Navigator.of(dialogContext).pop(item);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('common.cancel'.tr()),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomNavHeight = (screenHeight * 0.09).clamp(70.0, 90.0);

    return Scaffold(
      appBar: SharedAppBar(
        title: 'pallet_assignment.title'.tr(),
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _isLoadingInitialData || _isSaving
          ? null
          : Container(
        margin: const EdgeInsets.all(20).copyWith(top:0),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _onConfirmSave,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_alt_outlined),
          label: Text(_isSaving ? 'pallet_assignment.saving'.tr() : 'pallet_assignment.save'.tr()),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoadingInitialData
            ? const Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeSelector(),
                const SizedBox(height: _gap),
                _buildSearchableDropdownWithQr(
                    controller: _sourceLocationController,
                    label: tr('pallet_assignment.select_source'),
                    value: _selectedSourceLocation,
                    items: _availableSourceLocations,
                    onSelected: (val) {
                      if (mounted) {
                        setState(() {
                          _selectedSourceLocation = val;
                          _sourceLocationController.text = val ?? "";
                          _scannedContainerIdController.clear();
                          _selectedContainerId = null;
                          _boxItems = {};
                        });
                        _loadContainerIdsForLocation();
                      }
                    },
                    onQrTap: () => _scanQrAndUpdateField('source'),
                    validator: (val) {
                      if (val == null || val.isEmpty) return tr('pallet_assignment.source_required');
                      return null;
                    }
                ),
                const SizedBox(height: _gap),
                _buildScannedIdSection(),
                if (_isLoadingContainerIds)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: _smallGap),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: _smallGap),
                if (_isLoadingContainerContents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: _gap),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!_isLoadingContainerContents && _productsInContainer.isNotEmpty)
                        Expanded(child: _buildProductsList())
                      else if (!_isLoadingContainerContents && _scannedContainerIdController.text.isNotEmpty && !_isLoadingInitialData)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: _gap),
                            child: Center(child: Text(tr('pallet_assignment.no_items_for_id', namedArgs: {'id': _scannedContainerIdController.text, 'mode': _selectedMode.displayName}), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor))),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(height: _gap),
                      _buildSearchableDropdownWithQr(
                          controller: _targetLocationController,
                          label: tr('pallet_assignment.select_target'),
                          value: _selectedTargetLocation,
                          items: _availableTargetLocations,
                          onSelected: (val) {
                            if (mounted) {
                              setState(() {
                                _selectedTargetLocation = val;
                                _targetLocationController.text = val ?? "";
                              });
                            }
                          },
                          onQrTap: () => _scanQrAndUpdateField('target'),
                          validator: (val) {
                            if (val == null || val.isEmpty) return tr('pallet_assignment.target_required');
                            return null;
                          }
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: [
          ButtonSegment(value: AssignmentMode.pallet, label: Text('assignment_mode.palet'.tr()), icon: const Icon(Icons.pallet)),
          ButtonSegment(value: AssignmentMode.box, label: Text('assignment_mode.kutu'.tr()), icon: const Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<AssignmentMode> newSelection) {
          if (mounted) {
            setState(() {
              _selectedMode = newSelection.first;
              _scannedContainerIdController.clear();
              _selectedContainerId = null;
              _productsInContainer = [];
              _transferQuantityController.clear();
              _boxItems = {};
              _formKey.currentState?.reset();
            });
            _loadContainerIdsForLocation();
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildSearchableDropdownWithQr({
    required TextEditingController controller,
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onSelected,
    String Function(String)? itemLabelBuilder,
    bool Function(String, String)? filterFn,
    required VoidCallback onQrTap,
    required FormFieldValidator<String>? validator,
  }) {
    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              readOnly: true,
              decoration: _inputDecoration(label, filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
              onTap: () async {
                final String? selected = await _showSearchableDropdownDialog<String>(
                  context: context,
                  title: label,
                  items: items,
                  itemToString: (item) => itemLabelBuilder != null ? itemLabelBuilder(item) : item,
                  filterCondition: (item, query) => filterFn != null
                      ? filterFn(item, query)
                      : item.toLowerCase().contains(query.toLowerCase()),
                  initialValue: value,
                );
                onSelected(selected);
              },
              validator: validator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(onTap: onQrTap, size: _fieldHeight),
        ],
      ),
    );
  }

  Widget _buildScannedIdSection() {
    return _buildSearchableDropdownWithQr(
      controller: _scannedContainerIdController,
      label: tr('pallet_assignment.container_select', namedArgs: {'mode': _selectedMode.displayName}),
      value: _selectedContainerId,
      items: _availableContainerIds,
      itemLabelBuilder: (id) => _selectedMode == AssignmentMode.box
          ? (_boxItems[id] != null
          ? '${_boxItems[id]!.productName} • ${_boxItems[id]!.productCode} • ${_boxItems[id]!.quantity} pcs'
          : id)
          : id,
      filterFn: (id, query) {
        final label = _selectedMode == AssignmentMode.box
            ? (_boxItems[id] != null
            ? '${_boxItems[id]!.productName} ${_boxItems[id]!.productCode} ${_boxItems[id]!.quantity}'
            : id)
            : id;
        return label.toLowerCase().contains(query.toLowerCase()) ||
            id.toLowerCase().contains(query.toLowerCase());
      },
      onSelected: (val) async {
        if (mounted) {
          _selectedContainerId = val;
          setState(() {
            _scannedContainerIdController.text = val == null
                ? ''
                : _selectedMode == AssignmentMode.box
                ? (_boxItems[val] != null
                ? '${_boxItems[val]!.productName} • ${_boxItems[val]!.productCode} • ${_boxItems[val]!.quantity} pcs'
                : val)
                : val;
          });
          if (val != null) await _fetchContainerContents();
        }
      },
      onQrTap: () => _scanQrAndUpdateField('scannedId'),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return tr('pallet_assignment.container_empty', namedArgs: {'mode': _selectedMode.displayName});
        }
        return null;
      },
    );
  }

  Widget _buildProductsList() {
    final bool isBox = _selectedMode == AssignmentMode.box;
    final ProductItem? boxProduct = isBox && _productsInContainer.isNotEmpty ? _productsInContainer.first : null;

    return Container(
      margin: const EdgeInsets.only(top: _smallGap),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha((255 * 0.5).round())),
        borderRadius: _borderRadius,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.2).round()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(_smallGap),
            child: Text(
              isBox
                  ? tr('pallet_assignment.content_of', namedArgs: {'id': boxProduct?.name ?? _scannedContainerIdController.text})
                  : tr('pallet_assignment.content_of_count', namedArgs: {
                'id': _scannedContainerIdController.text,
                'count': _productsInContainer.length.toString()
              }),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Flexible(
            child: _productsInContainer.isEmpty
                ? Padding(
              padding: const EdgeInsets.all(_gap),
              child: Center(
                  child: Text(tr('pallet_assignment.contents_empty', namedArgs: {'mode': _selectedMode.displayName}),
                      style: TextStyle(color: Theme.of(context).hintColor))),
            )
                : isBox && boxProduct != null
                ? Padding(
              padding: const EdgeInsets.all(_smallGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, // Ensure Column takes minimum space
                      children: [
                        Text(boxProduct.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        Text(tr('pallet_assignment.current_qty', namedArgs: {'qty': boxProduct.currentQuantity.toString()}),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: _smallGap),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller: _transferQuantityController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('pallet_assignment.amount'.tr(), filled: true),
                      validator: (value) {
                        if (!isBox) return null;
                        if (value == null || value.isEmpty) {
                          return tr('pallet_assignment.amount_required');
                        }
                        final qty = int.tryParse(value);
                        if (qty == null) return tr('pallet_assignment.amount_invalid');
                        if (qty <= 0) return tr('pallet_assignment.amount_positive');
                        if (boxProduct.currentQuantity < qty ) { // Check against the current quantity of the product in the box
                          return tr('pallet_assignment.amount_max', namedArgs: {'max': boxProduct.currentQuantity.toString()});
                        }
                        return null;
                      },
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
            )
                : ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: _smallGap),
              itemCount: _productsInContainer.length,
              separatorBuilder: (context, index) => const Divider(
                  height: 1, indent: 16, endIndent: 16, thickness: 0.5),
              itemBuilder: (context, index) {
                final product = _productsInContainer[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: _smallGap, vertical: _smallGap / 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w500)),
                            Text(tr('pallet_assignment.current_qty', namedArgs: {'qty': product.currentQuantity.toString()}),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
