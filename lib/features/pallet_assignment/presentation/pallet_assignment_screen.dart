import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late PalletAssignmentRepository _repo;

  // State
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerIds = false;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;

  AssignmentMode _selectedMode = AssignmentMode.pallet;

  List<LocationInfo> _sourceLocations = [];
  LocationInfo? _selectedSourceLocation;

  List<LocationInfo> _targetLocations = [];
  LocationInfo? _selectedTargetLocation;

  List<String> _availableContainerIds = [];
  String? _selectedContainerId;
  Map<String, BoxItem> _boxItemsCache = {}; // Cache for box details

  List<ProductItem> _productsInContainer = [];
  final TextEditingController _scannedContainerIdController = TextEditingController();
  final TextEditingController _transferQuantityController = TextEditingController();

  // --- Lifecycle & Data Loading ---

  @override
  void initState() {
    super.initState();
    // initState'de context kullanmaktan kaçının.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo = Provider.of<PalletAssignmentRepository>(context, listen: false);
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingInitialData = true);
    try {
      final results = await Future.wait([
        _repo.getSourceLocations(),
        _repo.getTargetLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _sourceLocations = results[0];
        _targetLocations = results[1];
      });
    } catch (e) {
      _showErrorSnackbar(tr('pallet_assignment.load_error', args: [e.toString()]));
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _onSourceLocationChanged(LocationInfo? newLocation) async {
    if (newLocation == null) return;
    setState(() {
      _selectedSourceLocation = newLocation;
      _clearContainerSelection();
    });
    await _loadContainerIdsForLocation();
  }

  Future<void> _loadContainerIdsForLocation() async {
    if (_selectedSourceLocation == null) return;
    setState(() {
      _isLoadingContainerIds = true;
      _availableContainerIds = [];
      _selectedContainerId = null;
      _boxItemsCache = {};
    });
    
    try {
      final locationName = _selectedSourceLocation!.name;
      if (_selectedMode == AssignmentMode.box) {
        final boxes = await _repo.getBoxesAtLocation(locationName);
        if (!mounted) return;
        setState(() {
          _boxItemsCache = { for (var b in boxes) b.productId.toString(): b };
          _availableContainerIds = boxes.map((b) => b.productId.toString()).toList();
        });
      } else {
        final ids = await _repo.getContainerIdsByLocation(locationName, _selectedMode);
        if (!mounted) return;
        setState(() {
          _availableContainerIds = ids;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(tr('pallet_assignment.load_error_container', args: [e.toString()]));
      }
    } finally {
      if (mounted) setState(() => _isLoadingContainerIds = false);
    }
  }

  void _onContainerSelected(String? newValue) {
    if (newValue == null || newValue.isEmpty) return;
    setState(() {
      _selectedContainerId = newValue;
      _scannedContainerIdController.text = newValue;
      _loadContainerContents();
    });
  }

  Future<void> _scanContainerId() async {
    // TODO: Localize the title string
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QrScannerScreen(title: 'Scan Container Barcode')),
    );

    if (!mounted || result == null || result.isEmpty) return;

    if (_availableContainerIds.contains(result)) {
      _onContainerSelected(result);
    } else {
      // TODO: Localize the error string
      _showErrorSnackbar('Scanned container is not in the selected location.');
    }
  }

  Future<void> _loadContainerContents() async {
    if (_selectedContainerId == null) return;
    setState(() => _isLoadingContainerContents = true);
    try {
      final contents = await _repo.getContainerContent(_selectedContainerId!, _selectedMode);
      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        if (_selectedMode == AssignmentMode.box && contents.isNotEmpty) {
          _transferQuantityController.text = contents.first.currentQuantity.toString();
        }
      });
    } catch (e) {
      _showErrorSnackbar(tr('pallet_assignment.load_error', args: [e.toString()]));
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }
  
  // --- Actions ---

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final source = _selectedSourceLocation;
    final target = _selectedTargetLocation;
    final containerId = _selectedContainerId;

    if (source == null || target == null || containerId == null) {
       _showErrorSnackbar(tr('pallet_assignment.validation.all_fields_required'));
       return;
    }
    if (source.id == target.id) {
       _showErrorSnackbar(tr('pallet_assignment.validation.source_target_same'));
       return;
    }
    if (_productsInContainer.isEmpty) {
      _showErrorSnackbar(tr('pallet_assignment.validation.no_products'));
      return;
    }

    final header = TransferOperationHeader(
      operationType: _selectedMode,
      sourceLocationId: source.id,
      targetLocationId: target.id,
      containerId: containerId,
      transferDate: DateTime.now(),
    );

    final List<TransferItemDetail> items;
    if (_selectedMode == AssignmentMode.pallet) {
      items = _productsInContainer.map((p) => TransferItemDetail.fromProductItem(p)).toList();
    } else {
      final product = _productsInContainer.first;
      final qty = int.tryParse(_transferQuantityController.text) ?? 0;
      items = [TransferItemDetail.fromProductItem(product, quantity: qty)];
    }
    
    final confirmed = await _showConfirmationDialog(
      header: header, 
      sourceName: source.name, 
      targetName: target.name
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.recordTransferOperation(
        header, 
        items,
        sourceLocationName: source.name,
        targetLocationName: target.name,
      );
      _showSuccessSnackbar(tr('pallet_assignment.save_success'));
      _resetForm();
    } catch (e) {
      _showErrorSnackbar(tr('pallet_assignment.save_error', args: [e.toString()]));
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }

  // --- UI Helpers & State Resets ---
  
  void _resetForm() {
    setState(() {
      _selectedSourceLocation = null;
      _selectedTargetLocation = null;
      _clearContainerSelection();
      _formKey.currentState?.reset();
    });
  }

  void _clearContainerSelection() {
    setState(() {
      _selectedContainerId = null;
      _scannedContainerIdController.clear();
      _transferQuantityController.clear();
      _productsInContainer = [];
      _availableContainerIds = [];
      _boxItemsCache = {};
    });
  }

  void _onModeChanged(Set<AssignmentMode> newSelection) {
    setState(() {
      _selectedMode = newSelection.first;
      _clearContainerSelection();
      if (_selectedSourceLocation != null) {
        _loadContainerIdsForLocation();
      }
    });
  }

  String _getDisplayLabelForContainer(String containerId) {
    if (_selectedMode == AssignmentMode.box) {
      final box = _boxItemsCache[containerId];
      if (box != null) {
        return '${box.productName} • ${box.productCode} • ${tr('pallet_assignment.quantity_label', args: [box.quantity.toString()])}';
      }
    }
    return containerId;
  }
  
  // --- Widgets ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: tr('pallet_assignment.title')),
      body: SafeArea(
        child: _isLoadingInitialData
            ? const Center(child: CircularProgressIndicator())
            : _buildForm(),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildModeSelector(),
          const SizedBox(height: 16),
          _buildLocationCard(),
          const SizedBox(height: 16),
          _buildContainerCard(),
          if (_isLoadingContainerContents)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_productsInContainer.isNotEmpty)
            _buildProductsList(),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: [
          ButtonSegment(value: AssignmentMode.pallet, label: Text(tr('assignment_mode.palet')), icon: const Icon(Icons.pallet)),
          ButtonSegment(value: AssignmentMode.box, label: Text(tr('assignment_mode.kutu')), icon: const Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: _onModeChanged,
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildLocationDropdown(
              label: tr('pallet_assignment.source_location_label'),
              value: _selectedSourceLocation,
              locations: _sourceLocations,
              onChanged: _onSourceLocationChanged,
              validator: (loc) => loc == null ? tr('pallet_assignment.validation.required') : null,
            ),
            const SizedBox(height: 16),
             _buildLocationDropdown(
              label: tr('pallet_assignment.target_location_label'),
              value: _selectedTargetLocation,
              locations: _targetLocations.where((loc) => loc.id != _selectedSourceLocation?.id).toList(),
              onChanged: (LocationInfo? newValue) => setState(() => _selectedTargetLocation = newValue),
              validator: (loc) => loc == null ? tr('pallet_assignment.validation.required') : null,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContainerCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildSearchableDropdown(
                label: tr('pallet_assignment.container_select', namedArgs: {'mode': _selectedMode.displayName}),
                selectedValue: _selectedContainerId,
                items: _availableContainerIds,
                itemLabelBuilder: _getDisplayLabelForContainer,
                onSelected: _onContainerSelected,
                isLoading: _isLoadingContainerIds,
                isEnabled: _selectedSourceLocation != null,
                validator: (val) => val == null || val.isEmpty ? tr('pallet_assignment.validation.required') : null,
              ),
            ),
            const SizedBox(width: 8),
            // TODO: Localize the tooltip string
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _selectedSourceLocation != null ? _scanContainerId : null,
              iconSize: 40,
              tooltip: 'Scan container barcode',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('pallet_assignment.content_of', namedArgs: {'id': _scannedContainerIdController.text}),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            if (_selectedMode == AssignmentMode.box)
              _buildBoxItemEditor()
            else
              _buildPalletItemViewer(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBoxItemEditor() {
    if (_productsInContainer.isEmpty) return const SizedBox.shrink();
    final product = _productsInContainer.first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: Theme.of(context).textTheme.titleMedium),
              Text(tr('pallet_assignment.current_qty', args: [product.currentQuantity.toString()])),
            ],
          ),
        ),
        SizedBox(
          width: 120,
          child: TextFormField(
            controller: _transferQuantityController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('pallet_assignment.amount'), border: const OutlineInputBorder()),
            validator: (value) {
              final qty = int.tryParse(value ?? '');
              if (qty == null) return tr('pallet_assignment.amount_invalid');
              if (qty <= 0) return tr('pallet_assignment.amount_positive');
              if (qty > product.currentQuantity) return tr('pallet_assignment.amount_max', args: [product.currentQuantity.toString()]);
              return null;
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ),
      ],
    );
  }

  Widget _buildPalletItemViewer() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _productsInContainer.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final product = _productsInContainer[index];
        return ListTile(
          title: Text(product.name),
          subtitle: Text(product.productCode),
          trailing: Text(tr('pallet_assignment.quantity_label', args: [product.currentQuantity.toString()])),
        );
      },
    );
  }

  Widget? _buildBottomBar() {
    if (_isLoadingInitialData) return null;
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton.icon(
          onPressed: (_isSaving || _isLoadingContainerIds || _isLoadingContainerContents) ? null : _onConfirmSave,
          icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0,)) : const Icon(Icons.check),
          label: Text(tr('pallet_assignment.save')),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
  
  // --- Dialogs & Snackbars ---

  Future<bool?> _showConfirmationDialog({
    required TransferOperationHeader header,
    required String sourceName,
    required String targetName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('pallet_assignment.confirm_dialog.title')),
        content: Text(tr('pallet_assignment.confirm_dialog.message', namedArgs: {
          'mode': _selectedMode.displayName,
          'id': header.containerId!,
          'source': sourceName,
          'target': targetName,
        })),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('common.cancel'))),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('common.confirm'))),
        ],
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    _showSnackBar(message, isError: true);
  }

  void _showSuccessSnackbar(String message) {
    _showSnackBar(message, isError: false);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // --- Reusable Dropdown Widgets ---
  
  Widget _buildLocationDropdown({
    required String label,
    required LocationInfo? value,
    required List<LocationInfo> locations,
    required ValueChanged<LocationInfo?> onChanged,
    FormFieldValidator<LocationInfo>? validator,
  }) {
    return DropdownButtonFormField<LocationInfo>(
      value: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: locations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc.name))).toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _buildSearchableDropdown({
    required String label,
    required String? selectedValue,
    required List<String> items,
    required String Function(String) itemLabelBuilder,
    required ValueChanged<String?> onSelected,
    required bool isLoading,
    required bool isEnabled,
    FormFieldValidator<String>? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: isLoading ? const Padding(padding: EdgeInsets.all(10.0), child: CircularProgressIndicator(strokeWidth: 2)) : null,
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(itemLabelBuilder(item), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: isEnabled ? onSelected : null,
      validator: validator,
    );
  }
}

// Add these missing extensions to your entity files for cleaner code
extension TransferItemDetailFromProduct on TransferItemDetail {
  static TransferItemDetail fromProductItem(ProductItem item, {int? quantity}) {
    return TransferItemDetail(
      operationId: 0, // Not known at this point
      productId: item.id,
      productCode: item.productCode,
      productName: item.name,
      quantity: quantity ?? item.currentQuantity,
    );
  }
}
