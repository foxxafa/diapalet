// lib/features/pallet_assignment/presentation/pallet_assignment_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:collection/collection.dart';

// Corrected entity and repository imports using your project name 'diapalet'
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart'; // Assuming 'diapalet'
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';


class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late PalletAssignmentRepository _repo;
  bool _isRepoInitialized = false;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;

  List<LocationInfo> _availableSourceLocations = [];
  LocationInfo? _selectedSourceLocation;
  final TextEditingController _sourceLocationController = TextEditingController();

  List<String> _availableContainerIds = [];
  bool _isLoadingContainerIds = false;
  Map<String, BoxItem> _boxItems = {}; // boxId -> BoxItem mapping
  String? _selectedContainerId; // stores the actual container ID

  final TextEditingController _scannedContainerIdController = TextEditingController();
  List<ProductItem> _productsInContainer = [];
  final TextEditingController _transferQuantityController = TextEditingController();

  List<LocationInfo> _availableTargetLocations = [];
  LocationInfo? _selectedTargetLocation;
  final TextEditingController _targetLocationController = TextEditingController();

  static const double _fieldHeight = 56.0;
  static const double _gap = 16.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

  @override
  void initState() {
    super.initState();
    _scannedContainerIdController.addListener(_onScannedIdChange);
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
      _repo = Provider.of<PalletAssignmentRepository>(context, listen: false);
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
        _availableSourceLocations = results[0];
        _availableTargetLocations = results[1];
      });
      // We don't load container IDs initially, but after a source location is selected.
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
      if (mounted) setState(() => _availableContainerIds = []);
      return;
    }
    setState(() => _isLoadingContainerIds = true);
    try {
      final locationId = _selectedSourceLocation!.id;
      if (_selectedMode == AssignmentMode.box) {
        final boxes = await _repo.getBoxesAtLocation(locationId);
        if (mounted) {
          setState(() {
            _availableContainerIds = boxes.map((b) => b.boxId.toString()).toList();
            _boxItems = {for (var b in boxes) b.boxId.toString(): b};
          });
        }
      } else {
        final ids = await _repo.getContainerIdsByLocation(locationId);
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
      if (mounted) setState(() => _isLoadingContainerIds = false);
    }
  }

  Future<void> _fetchContainerContents() async {
    FocusScope.of(context).unfocus();
    final containerId = _selectedContainerId ?? '';
    if (containerId.isEmpty) return;
    
    setState(() => _isLoadingContainerContents = true);
    try {
      final contents = await _repo.getContainerContent(containerId);
      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        _transferQuantityController.clear();
        if (_selectedMode == AssignmentMode.box && contents.isNotEmpty) {
           _transferQuantityController.text = contents.first.currentQuantity.toString();
           _scannedContainerIdController.text = '${contents.first.name} • ${contents.first.productCode} • ${contents.first.currentQuantity} pcs';
        } else if (contents.isEmpty) {
          _showSnackBar(tr('pallet_assignment.contents_empty', namedArgs: {'mode': _selectedMode.displayName}), isError: true);
        }
      });
    } catch (e) {
      if (mounted) _showSnackBar(tr('pallet_assignment.load_error', namedArgs: {'error': e.toString()}), isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
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

    if (result == null || result.isEmpty || !mounted) return;

    bool found = false;
    String successMessage = "";

    if (fieldIdentifier == 'source') {
      final foundLocation = _availableSourceLocations.where((loc) => loc.name == result || loc.code == result).firstOrNull;
      if (foundLocation != null) {
        setState(() {
          _selectedSourceLocation = foundLocation;
          _sourceLocationController.text = foundLocation.name;
        });
        found = true;
        successMessage = tr('pallet_assignment.scan_success.source', namedArgs: {'location': result});
      }
    } else if (fieldIdentifier == 'target') {
      final foundLocation = _availableTargetLocations.where((loc) => loc.name == result || loc.code == result).firstOrNull;
      if (foundLocation != null) {
        setState(() {
          _selectedTargetLocation = foundLocation;
          _targetLocationController.text = foundLocation.name;
        });
        found = true;
        successMessage = tr('pallet_assignment.scan_success.target', namedArgs: {'location': result});
      }
    } else if (fieldIdentifier == 'container') {
      setState(() {
        _selectedContainerId = result;
        _scannedContainerIdController.text = result;
      });
      await _fetchContainerContents();
      found = true;
      successMessage = tr('pallet_assignment.scan_success.container', namedArgs: {'id': result});
    }

    _showSnackBar(found ? successMessage : tr('pallet_assignment.scan_error', namedArgs: {'value': result}));
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar(tr('pallet_assignment.form_invalid'), isError: true);
      return;
    }

    if (_selectedSourceLocation == null || _selectedTargetLocation == null || _selectedContainerId == null) {
       _showSnackBar(tr('pallet_assignment.validation.all_fields_required'), isError: true);
       return;
    }

    if (_selectedSourceLocation!.id == _selectedTargetLocation!.id) {
       _showSnackBar(tr('pallet_assignment.validation.source_target_same'), isError: true);
       return;
    }
    
    if (_productsInContainer.isEmpty) {
      _showSnackBar(tr('pallet_assignment.validation.no_products'), isError: true);
      return;
    }
    
    // For Box mode, validate quantity
    if (_selectedMode == AssignmentMode.box) {
      final qty = int.tryParse(_transferQuantityController.text) ?? 0;
      final maxQty = _productsInContainer.first.currentQuantity;
      if (qty <= 0 || qty > maxQty) {
        _showSnackBar(tr('pallet_assignment.validation.invalid_quantity', namedArgs: {'max': maxQty.toString()}), isError: true);
        return;
      }
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(tr('pallet_assignment.confirm_dialog.title')),
          content: Text(tr('pallet_assignment.confirm_dialog.message', namedArgs: {
            'mode': _selectedMode.displayName,
            'id': _selectedContainerId!,
            'source': _selectedSourceLocation!.name,
            'target': _selectedTargetLocation!.name,
          })),
          actions: <Widget>[
            TextButton(
              child: Text(tr('common.cancel')),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: Text(tr('common.confirm')),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final transferDate = DateTime.now();
      final header = TransferOperationHeader(
        operationType: _selectedMode,
        sourceLocationId: _selectedSourceLocation!.id,
        targetLocationId: _selectedTargetLocation!.id,
        containerId: _selectedContainerId,
        transferDate: transferDate,
      );

      final List<TransferItemDetail> items;
      if (_selectedMode == AssignmentMode.pallet) {
        // For pallets, transfer all items
        items = _productsInContainer.map((p) => TransferItemDetail(
          operationId: 0, // temp
          productId: p.id,
          productCode: p.productCode,
          productName: p.name,
          quantity: p.currentQuantity,
        )).toList();
      } else {
        // For boxes, transfer one item with specified quantity
        final product = _productsInContainer.first;
        items = [
          TransferItemDetail(
            operationId: 0, // temp
            productId: product.id,
            productCode: product.productCode,
            productName: product.name,
            quantity: int.parse(_transferQuantityController.text),
          )
        ];
      }
      
      await _repo.recordTransferOperation(header, items);
      _showSnackBar(tr('pallet_assignment.save_success'));
      _resetForm(resetAll: true);

    } catch (e) {
      if(mounted) _showSnackBar(tr('pallet_assignment.save_error', namedArgs: {'error': e.toString()}), isError: true);
    } finally {
      if(mounted) setState(() => _isSaving = false);
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

  /// Builds a [TextFormField] that opens a searchable dropdown dialog and supports QR scanning via a suffix icon.
  ///
  /// [T] is the type of the list item (e.g. `String`). You must provide a way to convert the item to a label
  /// with [itemLabelBuilder].
  Widget _buildSearchableDropdownWithQr<T>({
    required TextEditingController controller,
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabelBuilder,
    required bool Function(T, String) filterFn,
    required ValueChanged<T?> onSelected,
    required VoidCallback onQrTap,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: _inputDecoration(label, filled: true, suffixIcon: IconButton(
        icon: const Icon(Icons.qr_code_scanner),
        onPressed: onQrTap,
      )),
      onTap: () async {
        final T? selected = await _showSearchableDropdownDialog<T>(
          context: context,
          title: label,
          items: items,
          itemToString: itemLabelBuilder,
          filterCondition: filterFn,
          initialValue: value,
        );
        onSelected(selected);
      },
      validator: validator,
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
                _buildSourceLocationDropdown(),
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
                      _buildTargetLocationDropdown(),
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

  Widget _buildSourceLocationDropdown() {
    return DropdownButtonFormField<LocationInfo>(
      value: _selectedSourceLocation,
      decoration: _inputDecoration(
        'pallet_assignment.source_location_label'.tr(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: () => _scanQrAndUpdateField('source'),
        ),
      ),
      items: _availableSourceLocations.map((location) {
        return DropdownMenuItem<LocationInfo>(
          value: location,
          child: Text(location.name),
        );
      }).toList(),
      onChanged: (LocationInfo? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedSourceLocation = newValue;
            _sourceLocationController.text = newValue.name;
            _selectedContainerId = null;
            _scannedContainerIdController.clear();
            _productsInContainer = [];
          });
          _loadContainerIdsForLocation();
        }
      },
      validator: (value) => value == null ? tr('pallet_assignment.validation.required') : null,
      isExpanded: true,
    );
  }

  Widget _buildTargetLocationDropdown() {
    return DropdownButtonFormField<LocationInfo>(
      value: _selectedTargetLocation,
      decoration: _inputDecoration(
        'pallet_assignment.target_location_label'.tr(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: () => _scanQrAndUpdateField('target'),
        ),
      ),
      items: _availableTargetLocations
          .where((loc) => loc.id != _selectedSourceLocation?.id)
          .map((location) {
            return DropdownMenuItem<LocationInfo>(
              value: location,
              child: Text(location.name),
            );
          }).toList(),
      onChanged: (LocationInfo? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedTargetLocation = newValue;
            _targetLocationController.text = newValue.name;
          });
        }
      },
      validator: (value) => value == null ? tr('pallet_assignment.validation.required') : null,
      isExpanded: true,
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
      onQrTap: () => _scanQrAndUpdateField('container'),
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
