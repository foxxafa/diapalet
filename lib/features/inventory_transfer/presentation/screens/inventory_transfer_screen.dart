// lib/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/box_item.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_view_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class InventoryTransferScreen extends StatefulWidget {
  final PurchaseOrder? selectedOrder;
  const InventoryTransferScreen({super.key, this.selectedOrder});

  @override
  State<InventoryTransferScreen> createState() => _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  // --- Sabitler ve Stil Değişkenleri ---
  static const double _gap = 12.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

  // --- State ve Controller'lar ---
  final _formKey = GlobalKey<FormState>();
  late final InventoryTransferViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = Provider.of<InventoryTransferViewModel>(context, listen: false);
    _viewModel.init(widget.selectedOrder); 
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<InventoryTransferViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.lastError != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showErrorSnackBar(viewModel.lastError!);
              viewModel.clearError();
            });
          }
          
          return Scaffold(
            appBar: SharedAppBar(
              title: _viewModel.isPutawayMode 
                ? 'inventory_transfer.putaway_title'.tr() 
                : 'inventory_transfer.title'.tr()
            ),
            resizeToAvoidBottomInset: true,
            bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(viewModel),
            body: SafeArea(
              child: viewModel.isLoadingInitialData
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.disabled,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_viewModel.isPutawayMode && _viewModel.selectedOrder != null) ...[
                          OrderInfoCard(order: _viewModel.selectedOrder!),
                          const SizedBox(height: _gap),
                        ],
                        _buildModeSelector(viewModel),
                        const SizedBox(height: _gap),
                        if (viewModel.selectedMode == AssignmentMode.pallet) ...[
                          _buildPalletOpeningSwitch(viewModel),
                          const SizedBox(height: _gap),
                        ],
                        _buildHybridDropdownWithQr<String>(
                          controller: viewModel.sourceLocationController,
                          focusNode: viewModel.sourceLocationFocusNode,
                          label: 'inventory_transfer.label_source_location'.tr(),
                          fieldIdentifier: 'source',
                          items: viewModel.availableSourceLocations.keys.toList(),
                          itemToString: (item) => item,
                          onItemSelected: viewModel.handleSourceSelection,
                          filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                          validator: viewModel.validateSourceLocation,
                          viewModel: viewModel,
                        ),
                        const SizedBox(height: _gap),
                        _buildHybridDropdownWithQr<dynamic>(
                          controller: viewModel.scannedContainerIdController,
                          focusNode: viewModel.containerFocusNode,
                          label: viewModel.selectedMode == AssignmentMode.pallet 
                              ? 'inventory_transfer.label_pallet'.tr() 
                              : 'inventory_transfer.label_product'.tr(),
                          fieldIdentifier: 'container',
                          items: viewModel.availableContainers,
                          itemToString: (item) {
                            if (item is String) return item;
                            if (item is BoxItem) return '${item.productName} (${item.productCode})';
                            return '';
                          },
                          onItemSelected: viewModel.handleContainerSelection,
                          filterCondition: (item, query) {
                            final lowerQuery = query.toLowerCase();
                            if (item is String) return item.toLowerCase().contains(lowerQuery);
                            if (item is BoxItem) {
                              return item.productName.toLowerCase().contains(lowerQuery) ||
                                  item.productCode.toLowerCase().contains(lowerQuery) ||
                                  (item.barcode1?.toLowerCase().contains(lowerQuery) ?? false);
                            }
                            return false;
                          },
                          validator: viewModel.validateContainer,
                          viewModel: viewModel,
                        ),
                        const SizedBox(height: _gap),
                        if (viewModel.isLoadingContainerContents)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: _gap), 
                            child: Center(child: CircularProgressIndicator())
                          )
                        else if (viewModel.productsInContainer.isNotEmpty)
                          _buildProductsList(viewModel),
                        const SizedBox(height: _gap),
                        _buildHybridDropdownWithQr<String>(
                          controller: viewModel.targetLocationController,
                          focusNode: viewModel.targetLocationFocusNode,
                          label: 'inventory_transfer.label_target_location'.tr(),
                          fieldIdentifier: 'target',
                          items: viewModel.availableTargetLocations.keys.toList(),
                          itemToString: (item) => item,
                          onItemSelected: viewModel.handleTargetSelection,
                          filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                          validator: viewModel.validateTargetLocation,
                          viewModel: viewModel,
                        ),
                        const SizedBox(height: _gap),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModeSelector(InventoryTransferViewModel viewModel) {
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: [
          ButtonSegment(
              value: AssignmentMode.pallet,
              label: Text('inventory_transfer.mode_pallet'.tr()),
              icon: const Icon(Icons.pallet)),
          ButtonSegment(
              value: AssignmentMode.box,
              label: Text('inventory_transfer.mode_box'.tr()),
              icon: const Icon(Icons.inventory_2_outlined)),
        ],
        selected: {viewModel.selectedMode},
        onSelectionChanged: (newSelection) {
          viewModel.changeMode(newSelection.first);
        },
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.comfortable,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }

  Widget _buildPalletOpeningSwitch(InventoryTransferViewModel viewModel) {
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: _borderRadius,
      color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
      child: SwitchListTile(
        title: Text(
          'inventory_transfer.label_break_pallet'.tr(), 
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        value: viewModel.isPalletOpening,
        onChanged: viewModel.productsInContainer.isNotEmpty ? viewModel.setPalletOpening : null,
        secondary: const Icon(Icons.inventory_2_outlined),
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
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
    required FormFieldValidator<String>? validator,
    required InventoryTransferViewModel viewModel,
    bool isEnabled = true,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            readOnly: true,
            controller: controller,
            focusNode: focusNode,
            enabled: isEnabled && viewModel.areFieldsEnabled,
            decoration: _inputDecoration(
              label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
              enabled: isEnabled && viewModel.areFieldsEnabled,
            ),
            onTap: items.isEmpty ? null : () async {
              FocusScope.of(context).unfocus();

              final T? selectedItem = await _showSearchableDropdownDialog<T>(
                title: label,
                items: items,
                itemToString: itemToString,
                filterCondition: filterCondition,
              );
              if (selectedItem != null) {
                onItemSelected(selectedItem);
              }
            },
            validator: validator,
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(
          onTap: () async {
            final result = await Navigator.push<String>(
              context, 
              MaterialPageRoute(builder: (context) => const QrScannerScreen())
            );
            if (result != null && result.isNotEmpty) {
              viewModel.processScannedData(fieldIdentifier, result);
            }
          },
          isEnabled: isEnabled && viewModel.areFieldsEnabled,
        ),
      ],
    );
  }

  Widget _buildProductsList(InventoryTransferViewModel viewModel) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: _borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              'inventory_transfer.content_title'.tr(namedArgs: {
                'containerId': viewModel.scannedContainerIdController.text
              }),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(_smallGap),
            itemCount: viewModel.productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(
              height: _smallGap, 
              indent: 16, 
              endIndent: 16, 
              thickness: 0.2
            ),
            itemBuilder: (context, index) {
              final product = viewModel.productsInContainer[index];
              final controller = viewModel.productQuantityControllers[product.id]!;
              final focusNode = viewModel.productQuantityFocusNodes[product.id]!;
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name, 
                            style: Theme.of(context).textTheme.bodyLarge, 
                            overflow: TextOverflow.ellipsis
                          ),
                          Text(
                            'inventory_transfer.label_current_quantity'.tr(namedArgs: {
                              'productCode': product.productCode, 
                              'quantity': product.currentQuantity.toStringAsFixed(
                                product.currentQuantity.truncateToDouble() == product.currentQuantity ? 0 : 2
                              )
                            }),
                            style: Theme.of(context).textTheme.bodySmall
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !(viewModel.selectedMode == AssignmentMode.pallet && !viewModel.isPalletOpening),
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        decoration: _inputDecoration('inventory_transfer.label_quantity'.tr()),
                        validator: (value) => viewModel.validateProductQuantity(value, product),
                        onFieldSubmitted: (value) {
                           viewModel.focusNextProductOrTarget(product.id);
                        },
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

  Widget _buildBottomBar(InventoryTransferViewModel viewModel) {
    if (viewModel.isLoadingInitialData) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ElevatedButton.icon(
        onPressed: viewModel.isSaving || viewModel.productsInContainer.isEmpty 
            ? null 
            : () => _onConfirmSave(viewModel),
        icon: viewModel.isSaving
            ? const SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
              )
            : const Icon(Icons.check_circle_outline),
        label: FittedBox(child: Text('inventory_transfer.button_save'.tr())),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _onConfirmSave(InventoryTransferViewModel viewModel) async {
    FocusScope.of(context).unfocus();
    
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showErrorSnackBar('inventory_transfer.error_fill_required_fields'.tr());
      return;
    }

    final items = viewModel.getTransferItems();
    if (items.isEmpty) {
      _showErrorSnackBar('inventory_transfer.error_no_items_to_transfer'.tr());
      return;
    }

    final confirm = await _showConfirmationDialog(items, viewModel.finalOperationMode, viewModel);
    if (confirm != true) return;

    final success = await viewModel.confirmAndSave();
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('inventory_transfer.success_transfer_saved'.tr()),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted && !success) {
      // ViewModel might have set an error message
      if (viewModel.lastError == null) {
        _showErrorSnackBar('inventory_transfer.error_saving'.tr());
      }
    }
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.disabledColor.withAlpha(13),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.error, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 10),
    );
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
  }) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _InventorySearchPage<T>(
          title: title,
          items: items,
          itemToString: itemToString,
          filterCondition: filterCondition,
        ),
      ),
    );
  }

  Future<bool?> _showConfirmationDialog(
    List<TransferItemDetail> items, 
    AssignmentMode mode, 
    InventoryTransferViewModel viewModel
  ) async {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _InventoryConfirmationPage(
          items: items,
          mode: mode,
          sourceLocationName: viewModel.selectedSourceLocationName ?? '',
          targetLocationName: viewModel.selectedTargetLocationName ?? '',
        ),
      ),
    );
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
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isEnabled;

  const _QrButton({required this.onTap, this.isEnabled = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52, 
      width: 56,
      child: ElevatedButton(
        onPressed: isEnabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconSize = constraints.maxHeight * 0.6;
            return Icon(Icons.qr_code_scanner, size: iconSize);
          },
        ),
      ),
    );
  }
}

class _InventorySearchPage<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemToString;
  final bool Function(T, String) filterCondition;

  const _InventorySearchPage({
    required this.title,
    required this.items,
    required this.itemToString,
    required this.filterCondition,
  });

  @override
  State<_InventorySearchPage<T>> createState() => _InventorySearchPageState<T>();
}

class _InventorySearchPageState<T> extends State<_InventorySearchPage<T>> {
  String _searchQuery = '';
  late List<T> _filteredItems;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query;
      _filteredItems = widget.items
          .where((item) => widget.filterCondition(item, _searchQuery))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.appBarTheme.titleTextStyle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'inventory_transfer.dialog_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: _filterItems,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(child: Text('inventory_transfer.dialog_search_no_results'.tr()))
                  : ListView.separated(
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return ListTile(
                    title: Text(widget.itemToString(item)),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryConfirmationPage extends StatelessWidget {
  final List<TransferItemDetail> items;
  final AssignmentMode mode;
  final String sourceLocationName;
  final String targetLocationName;

  const _InventoryConfirmationPage({
    required this.items,
    required this.mode,
    required this.sourceLocationName,
    required this.targetLocationName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('inventory_transfer.dialog_confirm_transfer_title'.tr(namedArgs: {'mode': mode.apiName})),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            'inventory_transfer.dialog_confirm_transfer_body'.tr(
              namedArgs: {'source': sourceLocationName, 'target': targetLocationName},
            ),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const Divider(height: 24),
          ...items.map((item) => ListTile(
            title: Text(item.productName),
            subtitle: Text(item.productCode),
            trailing: Text(
              item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 2),
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          )),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 24.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('inventory_transfer.dialog_button_confirm'.tr()),
        ),
      ),
    );
  }
}