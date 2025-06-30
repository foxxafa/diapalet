// lib/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_view_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// ANA DEĞİŞİKLİK: Bu ekran artık hem "Serbest Transfer" hem de "Siparişli Rafa Kaldırma" işlemlerini yönetiyor.
class InventoryTransferScreen extends StatefulWidget {
  // DÜZELTME: Siparişli mod için opsiyonel bir sipariş parametresi eklendi.
  final PurchaseOrder? selectedOrder;
  const InventoryTransferScreen({super.key, this.selectedOrder});

  @override
  State<InventoryTransferScreen> createState() => _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  static const double _gap = 12.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);
  final _formKey = GlobalKey<FormState>();
  late final InventoryTransferViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<InventoryTransferViewModel>();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        _viewModel.init(widget.selectedOrder);
        _viewModel.addListener(_onViewModelUpdate);
      }
    });
  }
  
  void _onViewModelUpdate() {
      if (!mounted) return;
      if (_viewModel.lastError != null) {
        _showErrorSnackBar(_viewModel.lastError!);
        _viewModel.clearError();
      }
      if (_viewModel.navigateBack) {
        // ViewModel'den gelen geri gitme sinyali
        Navigator.of(context).pop(true);
        _viewModel.clearNavigateBack();
      }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelUpdate);
    // ViewModel'in kendisi Provider tarafından yönetildiği için burada dispose edilmez.
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    
    return Consumer<InventoryTransferViewModel>(
      builder: (context, viewModel, child) {
        return Scaffold(
          appBar: SharedAppBar(
            title: viewModel.isPutawayMode 
              ? 'inventory_transfer.putaway_title'.tr() 
              : 'inventory_transfer.title'.tr(),
            showBackButton: true,
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
                          if (viewModel.isPutawayMode && viewModel.selectedOrder != null) ...[
                            OrderInfoCard(order: viewModel.selectedOrder!),
                            const SizedBox(height: _gap),
                          ],
                          _buildModeSelector(viewModel),
                          const SizedBox(height: _gap),
                          
                          if (!viewModel.isPutawayMode) ...[
                            _buildHybridDropdownWithQr<String>(
                              controller: viewModel.sourceLocationController,
                              focusNode: viewModel.sourceLocationFocusNode,
                              label: 'inventory_transfer.label_source_location'.tr(),
                              items: viewModel.availableSourceLocations.keys.toList(),
                              itemToString: (item) => item,
                              onItemSelected: (selection) => viewModel.handleSourceSelection(selection),
                              filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                              validator: (value) => viewModel.validateSourceLocation(value),
                            ),
                            const SizedBox(height: _gap),
                          ],

                          if (viewModel.selectedMode == AssignmentMode.pallet && viewModel.productsInContainer.isNotEmpty) ...[
                            _buildPalletOpeningSwitch(viewModel),
                            const SizedBox(height: _gap),
                          ],

                          _buildHybridDropdownWithQr<TransferableContainer>(
                            controller: viewModel.scannedContainerIdController,
                            focusNode: viewModel.containerFocusNode,
                            label: viewModel.selectedMode == AssignmentMode.pallet 
                                ? 'inventory_transfer.label_pallet'.tr() 
                                : 'inventory_transfer.label_product'.tr(),
                            items: viewModel.availableContainers,
                            itemToString: (item) => item.displayName,
                            onItemSelected: (selection) => viewModel.handleContainerSelection(selection),
                            filterCondition: (item, query) => item.displayName.toLowerCase().contains(query.toLowerCase()),
                            validator: (value) => viewModel.validateContainer(value),
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
                            items: viewModel.availableTargetLocations.keys.toList(),
                            itemToString: (item) => item,
                            onItemSelected: (selection) => viewModel.handleTargetSelection(selection),
                            filterCondition: (item, query) => item.toLowerCase().contains(query.toLowerCase()),
                            validator: (value) => viewModel.validateTargetLocation(value),
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
    );
  }

  Widget _buildModeSelector(InventoryTransferViewModel viewModel) {
    return SegmentedButton<AssignmentMode>(
      segments: <ButtonSegment<AssignmentMode>>[
        ButtonSegment<AssignmentMode>(
          value: AssignmentMode.pallet,
          label: Text('inventory_transfer.mode_pallet'.tr()),
          icon: const Icon(Icons.pallet),
        ),
        ButtonSegment<AssignmentMode>(
          value: AssignmentMode.box,
          label: Text('inventory_transfer.mode_box'.tr()),
          icon: const Icon(Icons.inventory_2_outlined),
        ),
      ],
      selected: {viewModel.selectedMode},
      onSelectionChanged: (Set<AssignmentMode> newSelection) {
        viewModel.changeAssignmentMode(newSelection.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: _borderRadius)),
      ),
    );
  }

  Widget _buildPalletOpeningSwitch(InventoryTransferViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
        borderRadius: _borderRadius,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('inventory_transfer.label_open_pallet'.tr(), style: Theme.of(context).textTheme.bodyLarge),
          Switch(
            value: viewModel.isPalletOpening,
            onChanged: viewModel.togglePalletOpening,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList(InventoryTransferViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          viewModel.isPalletOpening
              ? 'inventory_transfer.header_products_in_pallet_opening'.tr()
              : 'inventory_transfer.header_products_in_container'.tr(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: _smallGap),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: _borderRadius,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: viewModel.productsInContainer.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final product = viewModel.productsInContainer[index];
              final controller = viewModel.productQuantityControllers[product.id];
              return ListTile(
                title: Text(product.name),
                subtitle: Text('Code: ${product.productCode}'),
                trailing: SizedBox(
                  width: 100,
                  child: AbsorbPointer(
                    absorbing: !viewModel.isPalletOpening,
                    child: TextFormField(
                      controller: controller,
                      focusNode: viewModel.productQuantityFocusNodes[product.id],
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                      decoration: InputDecoration(
                        labelText: 'common_labels.quantity'.tr(),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        fillColor: viewModel.isPalletOpening ? null : Colors.grey.withValues(alpha: 0.2),
                        filled: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHybridDropdownWithQr<T extends Object>({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required List<T> items,
    required String Function(T) itemToString,
    required void Function(T) onItemSelected,
    required bool Function(T, String) filterCondition,
    required String? Function(String?)? validator,
  }) {
    return Autocomplete<T>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return Iterable<T>.empty();
        }
        return items.where((T option) {
          return filterCondition(option, textEditingValue.text);
        });
      },
      displayStringForOption: itemToString,
      onSelected: (T selection) {
        onItemSelected(selection);
        controller.text = itemToString(selection);
        FocusScope.of(context).unfocus();
      },
      fieldViewBuilder: (BuildContext context, TextEditingController fieldController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
        // Sync internal controller with the external one.
        if(controller.text != fieldController.text) {
          fieldController.text = controller.text;
        }
        focusNode.addListener(() {
          if (fieldFocusNode.hasFocus != focusNode.hasFocus) {
            if (focusNode.hasFocus) {
              fieldFocusNode.requestFocus();
            } else {
              fieldFocusNode.unfocus();
            }
          }
        });

        return TextFormField(
          controller: fieldController,
          focusNode: fieldFocusNode,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: _borderRadius),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (context) => const QrScannerScreen()),
                );
                if (result != null && result.isNotEmpty) {
                  fieldController.text = result;
                  // Let autocomplete handle the selection or show options
                }
              },
            ),
          ),
          validator: validator,
        );
      },
       optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final T option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: ListTile(
                      title: Text(itemToString(option)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(InventoryTransferViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        icon: viewModel.isSaving ? const SizedBox.shrink() : const Icon(Icons.save),
        label: viewModel.isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : Text('common_buttons.save'.tr()),
        onPressed: viewModel.areFieldsEnabled ? () async {
          if(_formKey.currentState!.validate()){
            final success = await viewModel.confirmAndSave();
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('inventory_transfer.success_transfer_recorded'.tr())),
              );
            }
          }
        } : null,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}