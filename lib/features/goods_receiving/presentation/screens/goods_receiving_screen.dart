// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_view_model.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';

class GoodsReceivingScreen extends StatefulWidget {
  final PurchaseOrder? selectedOrder;

  const GoodsReceivingScreen({super.key, this.selectedOrder});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  // --- Sabitler ve Stil Değişkenleri ---
  static const double _gap = 12;
  static const double _smallGap = 8;
  final _borderRadius = BorderRadius.circular(12);

  // --- State ve Controller'lar ---
  late final GoodsReceivingViewModel _viewModel;
  final _formKey = GlobalKey<FormState>();
  
  // --- Barcode Service ---
  late BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    final repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    final syncService = Provider.of<SyncService>(context, listen: false);
    final barcodeService = Provider.of<BarcodeIntentService>(context, listen: false);
    
    _barcodeService = barcodeService;
    
    _viewModel = GoodsReceivingViewModel(
      repository: repository,
      syncService: syncService,
      barcodeService: barcodeService,
      initialOrder: widget.selectedOrder,
    );
    
    _viewModel.init();
    _viewModel.addListener(_onViewModelUpdate);
    _initBarcode();
  }

  void _onViewModelUpdate() {
    if (!mounted) return;
    
    if (_viewModel.error != null) {
      _showErrorSnackBar(_viewModel.error!);
      _viewModel.clearError();
    }
    if (_viewModel.successMessage != null) {
      _showSuccessSnackBar(_viewModel.successMessage!);
      _viewModel.clearSuccessMessage();
    }
    if (_viewModel.navigateBack) {
      Navigator.of(context).pop(true);
      _viewModel.clearNavigateBack();
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _viewModel.removeListener(_onViewModelUpdate);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<GoodsReceivingViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            appBar: SharedAppBar(
              title: 'goods_receiving_screen.title'.tr(),
              showBackButton: true,
            ),
            bottomNavigationBar: _buildBottomBar(viewModel),
            body: SafeArea(
              child: viewModel.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            if (viewModel.isOrderBased) ...[
                              OrderInfoCard(order: viewModel.selectedOrder!),
                              const SizedBox(height: _gap),
                            ],
                            _buildModeSelector(viewModel),
                            const SizedBox(height: _gap),
                            if (viewModel.receivingMode == ReceivingMode.palet) ...[
                              _buildPalletIdField(viewModel),
                              const SizedBox(height: _gap),
                            ],
                            _buildHybridDropdownWithQr<ProductInfo>(
                              controller: viewModel.productController,
                              focusNode: viewModel.productFocusNode,
                              label: viewModel.isOrderBased
                                  ? 'goods_receiving_screen.label_select_product_in_order'.tr()
                                  : 'goods_receiving_screen.label_select_product'.tr(),
                              fieldIdentifier: 'product',
                              isEnabled: viewModel.areFieldsEnabled,
                              items: viewModel.isOrderBased
                                  ? viewModel.orderItems.map((orderItem) => orderItem.product).whereType<ProductInfo>().toList()
                                  : viewModel.availableProducts,
                              itemToString: (product) => "${product.name} (${product.stockCode})",
                              onItemSelected: (product) {
                                if (product != null) {
                                  viewModel.selectProduct(product);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) {
                                      _showDatePicker(viewModel);
                                    }
                                  });
                                }
                              },
                              filterCondition: (product, query) {
                                final lowerQuery = query.toLowerCase();
                                return product.name.toLowerCase().contains(lowerQuery) ||
                                    product.stockCode.toLowerCase().contains(lowerQuery) ||
                                    (product.barcode1?.toLowerCase().contains(lowerQuery) ?? false);
                              },
                              validator: viewModel.validateProduct,
                            ),
                            const SizedBox(height: _gap),
                            _buildExpiryDateField(viewModel),
                            const SizedBox(height: _gap),
                            if (viewModel.selectedProduct != null) ...[
                              _buildQuantityAndStatusRow(viewModel),
                              const SizedBox(height: _gap),
                            ],
                            _buildAddedItemsSection(viewModel, textTheme, colorScheme),
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

  Widget _buildModeSelector(GoodsReceivingViewModel viewModel) {
    return Center(
      child: SegmentedButton<ReceivingMode>(
        segments: [
          ButtonSegment(
              value: ReceivingMode.palet,
              label: Text('goods_receiving_screen.mode_pallet'.tr()),
              icon: const Icon(Icons.pallet)),
          ButtonSegment(
              value: ReceivingMode.kutu,
              label: Text('goods_receiving_screen.mode_box'.tr()),
              icon: const Icon(Icons.inventory_2_outlined)),
        ],
        selected: {viewModel.receivingMode},
        onSelectionChanged: (newSelection) {
          viewModel.changeReceivingMode(newSelection.first);
        },
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.comfortable,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }

  Widget _buildPalletIdField(GoodsReceivingViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: viewModel.palletIdController,
            focusNode: viewModel.palletIdFocusNode,
            enabled: viewModel.areFieldsEnabled,
            decoration: _inputDecoration(
              'goods_receiving_screen.label_pallet_barcode'.tr(),
              enabled: viewModel.areFieldsEnabled,
            ),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) {
                viewModel.processScannedData('pallet', value);
              }
            },
            validator: viewModel.validatePalletId,
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(
          onTap: () async {
            final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
            if (result != null && result.isNotEmpty) {
              viewModel.processScannedData('pallet', result);
            }
          },
          isEnabled: viewModel.areFieldsEnabled,
        ),
      ],
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
            enabled: isEnabled,
            decoration: _inputDecoration(
              label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
              enabled: isEnabled,
            ),
            onTap: items.isEmpty ? null : () async {
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
            final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
            if (result != null && result.isNotEmpty) {
              _viewModel.processScannedData(fieldIdentifier, result);
            }
          },
          isEnabled: isEnabled,
        ),
      ],
    );
  }

  Widget _buildQuantityAndStatusRow(GoodsReceivingViewModel viewModel) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    PurchaseOrderItem? orderItem;
    if (viewModel.selectedProduct != null && viewModel.isOrderBased) {
      try {
        orderItem = viewModel.orderItems.firstWhere((item) => item.product?.id == viewModel.selectedProduct!.id);
      } catch (e) {
        orderItem = null;
      }
    }

    double alreadyAddedInUI = 0.0;
    if (orderItem != null && orderItem.product != null) {
      for (final item in viewModel.addedItems) {
        if (item.product.id == orderItem.product!.id) {
          alreadyAddedInUI += item.quantity;
        }
      }
    }

    final totalReceived = (orderItem?.receivedQuantity ?? 0.0) + alreadyAddedInUI;
    final expectedQty = orderItem?.expectedQuantity ?? 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: viewModel.quantityController,
            focusNode: viewModel.quantityFocusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            enabled: viewModel.isQuantityEnabled,
            decoration: _inputDecoration('goods_receiving_screen.label_quantity'.tr(), enabled: viewModel.isQuantityEnabled),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) {
                if (_formKey.currentState?.validate() ?? false) {
                  viewModel.addItemToList();
                }
              }
            },
            validator: viewModel.validateQuantity,
          ),
        ),
        const SizedBox(width: _smallGap),
        Expanded(
          flex: 4,
          child: InputDecorator(
            decoration: _inputDecoration('goods_receiving_screen.label_order_status'.tr(), enabled: false),
            child: Center(
              child: (!viewModel.isOrderBased || viewModel.selectedProduct == null)
                  ? Text(
                      'common_labels.not_available'.tr(),
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).hintColor),
                      textAlign: TextAlign.center,
                    )
                  : RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                        children: [
                          TextSpan(
                            text: '${totalReceived.toStringAsFixed(0)} ',
                            style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          TextSpan(text: '/ ', style: TextStyle(color: textTheme.bodyLarge?.color?.withAlpha(179))),
                          TextSpan(text: expectedQty.toStringAsFixed(0), style: TextStyle(color: textTheme.bodyLarge?.color)),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpiryDateField(GoodsReceivingViewModel viewModel) {
    return TextFormField(
      controller: viewModel.expiryDateController,
      focusNode: viewModel.expiryDateFocusNode,
      enabled: viewModel.isExpiryDateEnabled,
      readOnly: true, // Klavyeyi engelle, sadece tarih seçicisi açılsın
      decoration: _inputDecoration(
        'goods_receiving_screen.label_expiry_date'.tr(),
        enabled: viewModel.isExpiryDateEnabled,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      validator: viewModel.validateExpiryDate,
      onTap: () => _showDatePicker(viewModel),
    );
  }

  Future<void> _showDatePicker(GoodsReceivingViewModel viewModel) async {
    if (!viewModel.isExpiryDateEnabled) return; // Don't show picker if disabled
    
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)), // 10 years from now
      helpText: 'goods_receiving_screen.label_expiry_date'.tr(),
    );
    
    if (selectedDate != null) {
      final formattedDate = DateFormat('dd/MM/yyyy').format(selectedDate);
      viewModel.expiryDateController.text = formattedDate;
      viewModel.onExpiryDateEntered(); // Trigger the next field enable
    }
  }

  Widget _buildAddedItemsSection(GoodsReceivingViewModel viewModel, TextTheme textTheme, ColorScheme colorScheme) {
    if (viewModel.addedItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32.0),
          child: Text(
            'goods_receiving_screen.no_items'.tr(),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

    final item = viewModel.addedItems.first;
    String unitText = '';
    if (viewModel.isOrderBased) {
      try {
        final orderItem = viewModel.orderItems.firstWhere((oi) => oi.product?.id == item.product.id);
        unitText = orderItem.unit ?? '';
      } catch (e) {
        // Safe fallback.
      }
    }

    // Format expiry date
    String expiryText = '';
    if (item.expiryDate != null) {
      expiryText = DateFormat('dd/MM/yyyy').format(item.expiryDate!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _smallGap, vertical: 8.0),
          child: Text(
            'goods_receiving_screen.header_last_added_item'.tr(),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: _smallGap),
        Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
          child: ListTile(
            dense: true,
            title: Text(
              item.product.name,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.palletBarcode != null
                      ? 'goods_receiving_screen.label_pallet_barcode_display'.tr(namedArgs: {'barcode': item.palletBarcode!})
                      : 'goods_receiving_screen.mode_box'.tr(),
                  style: textTheme.bodySmall,
                ),
                if (expiryText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Expires: $expiryText',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.quantity.toStringAsFixed(0)} $unitText',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.secondary),
                ),
                const SizedBox(width: _smallGap),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  onPressed: () => viewModel.removeItemFromList(0),
                  tooltip: 'common_labels.delete'.tr(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(GoodsReceivingViewModel viewModel) {
    if (viewModel.isLoading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ElevatedButton.icon(
        onPressed: viewModel.addedItems.isEmpty || viewModel.isSaving ? null : () async {
          final result = await _showConfirmationListDialog(viewModel);
          if (result != null) {
            await viewModel.saveAndConfirm(result);
          }
        },
        icon: viewModel.isSaving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check_circle_outline),
        label: FittedBox(
          child: Text('goods_receiving_screen.button_review_items'.tr()),
        ),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.disabledColor.withAlpha(13),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.dividerColor.withAlpha(128))),
      focusedBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 10),
    );
  }

  Future<ConfirmationAction?> _showConfirmationListDialog(GoodsReceivingViewModel viewModel) {
    FocusScope.of(context).unfocus(); // Klavyeyi gizle
    return Navigator.push<ConfirmationAction>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ChangeNotifierProvider.value(
          value: viewModel,
          child: _FullscreenConfirmationPage(
            onItemRemoved: (item) {
              final index = viewModel.addedItems.indexOf(item);
              if (index != -1) {
                viewModel.removeItemFromList(index);
              }
            },
          ),
        ),
      ),
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
        builder: (context) => _FullscreenSearchPage<T>(
          title: title,
          items: items,
          itemToString: itemToString,
          filterCondition: filterCondition,
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

  // Barcode service setup
  Future<void> _initBarcode() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    try {
      _barcodeService = BarcodeIntentService();
      _intentSub = _barcodeService.stream.listen((code) {
        _handleBarcode(code);
      }, onError: (error) {
        _showErrorSnackBar(
            'common_labels.barcode_reading_error'.tr(namedArgs: {'error': error.toString()}));
      });
    } catch (e) {
      _showErrorSnackBar(
          'common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  // Barcode data handler
  void _handleBarcode(String code) {
    if (!mounted) return;
    final viewModel = context.read<GoodsReceivingViewModel>();

    if (viewModel.palletIdFocusNode.hasFocus) {
      viewModel.processScannedData('pallet', code);
    } else if (viewModel.productFocusNode.hasFocus) {
      viewModel.processScannedData('product', code);
    } else {
      if (viewModel.receivingMode == ReceivingMode.palet &&
          viewModel.palletIdController.text.isEmpty) {
        viewModel.processScannedData('pallet', code);
      } else {
        viewModel.productFocusNode.requestFocus();
        viewModel.processScannedData('product', code);
      }
    }
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

class _FullscreenSearchPage<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemToString;
  final bool Function(T, String) filterCondition;

  const _FullscreenSearchPage({
    super.key,
    required this.title,
    required this.items,
    required this.itemToString,
    required this.filterCondition,
  });

  @override
  State<_FullscreenSearchPage<T>> createState() => _FullscreenSearchPageState<T>();
}

class _FullscreenSearchPageState<T> extends State<_FullscreenSearchPage<T>> {
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
      _filteredItems = widget.items.where((item) => widget.filterCondition(item, _searchQuery)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: appBarTheme.titleTextStyle),
        backgroundColor: appBarTheme.backgroundColor,
        foregroundColor: appBarTheme.foregroundColor,
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
                hintText: 'goods_receiving_screen.dialog_search_hint'.tr(),
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
                  ? Center(child: Text('goods_receiving_screen.dialog_search_no_results'.tr()))
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

class _FullscreenConfirmationPage extends StatelessWidget {
  final ValueChanged<ReceiptItemDraft> onItemRemoved;

  const _FullscreenConfirmationPage({
    required this.onItemRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = context.watch<GoodsReceivingViewModel>();

    final isCompletingOrder = viewModel.isReceiptCompletingOrder;
    
    // Calculate total accepted items count
    final totalAcceptedItems = viewModel.addedItems.fold<int>(0, (sum, item) => sum + item.quantity.toInt());
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Text(
          'goods_receiving_screen.dialog_confirmation_title'.tr(),
        ),
      ),
      body: Column(
        children: [
          _buildTotalItemsSummary(context, totalAcceptedItems),
          Expanded(
            child: viewModel.isOrderBased
                ? _buildOrderBasedConfirmationList(context, theme)
                : _buildFreeReceiveConfirmationList(context, theme),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isCompletingOrder)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: viewModel.addedItems.isEmpty ? null : () => Navigator.of(context).pop(ConfirmationAction.saveAndComplete),
                child: Text('goods_receiving_screen.dialog_button_finish_receiving'.tr()),
              )
            else ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  onPressed: viewModel.addedItems.isEmpty ? null : () => Navigator.of(context).pop(ConfirmationAction.saveAndContinue),
                  child: Text('goods_receiving_screen.dialog_button_save_continue'.tr()),
                ),
                if (viewModel.isOrderBased)...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: theme.colorScheme.error),
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => Navigator.of(context).pop(ConfirmationAction.forceClose),
                    child: Text('goods_receiving_screen.dialog_button_force_close'.tr()),
                  ),
                ]
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTotalItemsSummary(BuildContext context, int totalAcceptedItems) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primaryContainer),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '${'goods_receiving_screen.dialog_confirmation_title'.tr()}:',
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              totalAcceptedItems.toString(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'goods_receiving_screen.items_to_receive'.tr(),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeReceiveConfirmationList(BuildContext context, ThemeData theme) {
    final viewModel = context.watch<GoodsReceivingViewModel>();
    final groupedItems = <int, List<ReceiptItemDraft>>{};
    for (final item in viewModel.addedItems) {
      groupedItems.putIfAbsent(item.product.id, () => []).add(item);
    }
    final productIds = groupedItems.keys.toList();

    if (viewModel.addedItems.isEmpty) {
      return Center(child: Text('goods_receiving_screen.dialog_list_empty'.tr()));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: productIds.length,
      itemBuilder: (context, index) {
        final productId = productIds[index];
        final itemsForProduct = groupedItems[productId]!;
        final product = itemsForProduct.first.product;
        final totalQuantity = itemsForProduct.fold<double>(0.0, (sum, item) => sum + item.quantity);

        return Card(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${'goods_receiving_screen.dialog_total_quantity'.tr()}: ${totalQuantity.toStringAsFixed(0)}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  ...itemsForProduct.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.palletBarcode != null
                                      ? 'goods_receiving_screen.label_pallet_barcode_display_short'.tr(namedArgs: {'barcode': item.palletBarcode!})
                                      : 'goods_receiving_screen.mode_box'.tr(),
                                  style: theme.textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.expiryDate != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Exp: ${DateFormat('dd/MM/yyyy').format(item.expiryDate!)}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  item.quantity.toStringAsFixed(0),
                                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 22),
                                  onPressed: () => onItemRemoved(item),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'common_labels.delete'.tr(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ));
      },
    );
  }

  Widget _buildOrderBasedConfirmationList(BuildContext context, ThemeData theme) {
    final viewModel = context.watch<GoodsReceivingViewModel>();
    if (viewModel.orderItems.isEmpty && viewModel.addedItems.isEmpty) {
      return Center(child: Text('goods_receiving_screen.dialog_list_empty'.tr()));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: viewModel.orderItems.length,
      itemBuilder: (context, index) {
        final orderItem = viewModel.orderItems[index];
        final product = orderItem.product;
        if (product == null) return const SizedBox.shrink();

        final itemsBeingAdded = viewModel.addedItems.where((item) => item.product.id == product.id).toList();
        final quantityBeingAdded = itemsBeingAdded.fold<double>(0.0, (sum, item) => sum + item.quantity);

        if (itemsBeingAdded.isEmpty && orderItem.expectedQuantity - orderItem.receivedQuantity <= 0) {
          return const SizedBox.shrink();
        }

        return _OrderProductConfirmationCard(
          orderItem: orderItem,
          itemsBeingAdded: itemsBeingAdded,
          quantityBeingAdded: quantityBeingAdded,
          onRemoveItem: onItemRemoved,
        );
      },
    );
  }
}

class _OrderProductConfirmationCard extends StatelessWidget {
  final PurchaseOrderItem orderItem;
  final List<ReceiptItemDraft> itemsBeingAdded;
  final double quantityBeingAdded;
  final ValueChanged<ReceiptItemDraft> onRemoveItem;

  const _OrderProductConfirmationCard({
    required this.orderItem,
    required this.itemsBeingAdded,
    required this.quantityBeingAdded,
    required this.onRemoveItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final product = orderItem.product!;
    final unit = orderItem.unit ?? '';

    final totalReceivedAfter = orderItem.receivedQuantity + quantityBeingAdded;
    final remaining = (orderItem.expectedQuantity - totalReceivedAfter).clamp(0.0, double.infinity);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text("(${product.stockCode})", style: textTheme.bodyMedium?.copyWith(color: textTheme.bodySmall?.color)),
              ],
            ),
            const Divider(height: 16),
            _buildStatRow(context, 'goods_receiving_screen.confirmation.ordered'.tr(), orderItem.expectedQuantity, unit),
            _buildStatRow(context, 'goods_receiving_screen.confirmation.previously_received'.tr(), orderItem.receivedQuantity, unit),
            _buildStatRow(context, 'goods_receiving_screen.confirmation.currently_adding'.tr(), quantityBeingAdded, unit, highlight: true),
            const Divider(thickness: 1, height: 24, color: Colors.black12),
            _buildStatRow(context, 'goods_receiving_screen.confirmation.remaining_after'.tr(), remaining, unit, bold: true),
            if (itemsBeingAdded.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...itemsBeingAdded.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      const Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.palletBarcode != null
                                  ? 'goods_receiving_screen.label_pallet_barcode_display_short'.tr(namedArgs: {'barcode': item.palletBarcode!})
                                  : 'goods_receiving_screen.mode_box'.tr(),
                              style: textTheme.bodyMedium,
                            ),
                            if (item.expiryDate != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Expires: ${DateFormat('dd/MM/yyyy').format(item.expiryDate!)}',
                                style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text('${item.quantity.toStringAsFixed(0)} $unit', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 22),
                        onPressed: () => onRemoveItem(item),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'common_labels.delete'.tr(),
                      )
                    ],
                  ),
                );
              }),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, double value, String unit, {bool highlight = false, bool bold = false}) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final valueStyle = textTheme.titleMedium?.copyWith(
      fontWeight: bold ? FontWeight.w900 : FontWeight.bold,
      color: highlight ? colorScheme.primary : (bold ? colorScheme.onSurface : textTheme.bodyLarge?.color),
      fontSize: bold ? 18 : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodyLarge),
          Text('${value.toStringAsFixed(0)} $unit', style: valueStyle),
        ],
      ),
    );
  }
}

