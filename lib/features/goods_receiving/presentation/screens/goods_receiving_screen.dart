// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/purchase_order_list_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late final GoodsReceivingRepository _repository;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOrderDetailsLoading = false;

  late final bool _isFreeReceiveMode;
  PurchaseOrder? _selectedOrder;

  bool get isOrderBased => _selectedOrder != null;

  ReceivingMode _receivingMode = ReceivingMode.palet;
  List<PurchaseOrderItem> _orderItems = [];
  List<ProductInfo> _availableProducts = [];
  ProductInfo? _selectedProduct;
  List<ReceiptItemDraft> _addedItems = [];

  final _palletIdController = TextEditingController();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();

  final _palletIdFocusNode = FocusNode();
  final _productFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _selectedOrder = widget.selectedOrder;
    _isFreeReceiveMode = widget.selectedOrder == null;

    _productFocusNode.addListener(_onProductFocusChange);
    _loadInitialData();
  }

  @override
  void dispose() {
    _productFocusNode.removeListener(_onProductFocusChange);
    _palletIdController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    _palletIdFocusNode.dispose();
    _productFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onProductFocusChange() {
    if (_productFocusNode.hasFocus && _productController.text.isNotEmpty) {
      _productController.selection = TextSelection(
          baseOffset: 0, extentOffset: _productController.text.length);
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_isFreeReceiveMode) {
        _availableProducts = await _repository.searchProducts('');
      }

      if (mounted) {
        setState(() => _isLoading = false);
        if (isOrderBased) {
          _onOrderSelected(_selectedOrder!);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) => _palletIdFocusNode.requestFocus());
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('goods_receiving_screen.error_loading_initial'.tr(namedArgs: {'error': e.toString()}));
        setState(() => _isLoading = false);
      }
    }
  }

  void _onOrderSelected(PurchaseOrder order) {
    setState(() {
      _selectedOrder = order;
      _addedItems.clear();
      _orderItems = [];
      _isOrderDetailsLoading = true;
      _clearEntryFields(clearPallet: true);
    });
    _loadOrderDetails(order.id);
  }

  Future<void> _loadOrderDetails(int orderId) async {
    try {
      final items = await _repository.getPurchaseOrderItems(orderId);
      if (!mounted) return;
      setState(() => _orderItems = items);
    } catch (e) {
      if (mounted) _showErrorSnackBar('goods_receiving_screen.error_loading_details'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) {
        setState(() => _isOrderDetailsLoading = false);
        _setInitialFocusAfterOrderLoad();
      }
    }
  }

  void _setInitialFocusAfterOrderLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_receivingMode == ReceivingMode.palet) {
        _palletIdFocusNode.requestFocus();
      } else {
        _productFocusNode.requestFocus();
      }
    });
  }

  void _processScannedProduct(String scannedData) {
    if (scannedData.isEmpty) return;

    final productSource = isOrderBased
        ? _orderItems.map((item) => item.product).whereNotNull().toList()
        : _availableProducts;

    final foundProduct = productSource.firstWhereOrNull((p) =>
    p.stockCode.toLowerCase() == scannedData.toLowerCase() ||
        (p.barcode1?.toLowerCase() == scannedData.toLowerCase()),
    );

    if (foundProduct != null) {
      _selectProduct(foundProduct);
    } else {
      _productController.clear();
      _selectedProduct = null;
      _showErrorSnackBar('goods_receiving_screen.error_product_not_found'.tr(namedArgs: {'scannedData': scannedData}));
    }
  }

  void _selectProduct(ProductInfo product) {
    setState(() {
      _selectedProduct = product;
      _productController.text = "${product.name} (${product.stockCode})";
    });
    _quantityFocusNode.requestFocus();
  }

  void _addItemToList() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final quantity = double.tryParse(_quantityController.text);
    final currentProduct = _selectedProduct;

    if (currentProduct == null || quantity == null || quantity <= 0) {
      _showErrorSnackBar('goods_receiving_screen.error_select_product_and_quantity'.tr());
      return;
    }

    if (isOrderBased) {
      if (_isOrderDetailsLoading) {
        _showErrorSnackBar('goods_receiving_screen.error_loading_order_details'.tr());
        return;
      }
      final orderItem = _orderItems.firstWhereOrNull((item) => item.product?.id == currentProduct.id);
      if (orderItem == null) {
        _showErrorSnackBar('goods_receiving_screen.error_product_not_in_order'.tr());
        return;
      }
      final alreadyAddedInUI = _addedItems
          .where((item) => item.product.id == currentProduct.id && (_receivingMode == ReceivingMode.palet ? item.palletBarcode == _palletIdController.text : true))
          .map((item) => item.quantity)
          .fold(0.0, (prev, qty) => prev + qty);
      final totalPreviouslyReceived = orderItem.receivedQuantity;
      final remainingQuantity = orderItem.expectedQuantity - totalPreviouslyReceived - alreadyAddedInUI;

      if (quantity > remainingQuantity + 0.001) {
        _showErrorSnackBar('goods_receiving_screen.error_quantity_exceeds_order'.tr(namedArgs: {
          'remainingQuantity': remainingQuantity.toStringAsFixed(2),
          'unit': orderItem.unit ?? ''
        }));
        return;
      }
    }

    setState(() {
      _addedItems.insert(0, ReceiptItemDraft(
        product: currentProduct,
        quantity: quantity,
        palletBarcode: _receivingMode == ReceivingMode.palet && _palletIdController.text.isNotEmpty ? _palletIdController.text : null,
      ));
      _clearEntryFields(clearPallet: false);
    });

    FocusScope.of(context).unfocus();
    _showSuccessSnackBar('goods_receiving_screen.success_item_added'.tr(namedArgs: {'productName': currentProduct.name}));
    _productFocusNode.requestFocus();
  }

  void _removeItemFromList(int index) {
    if (!mounted) return;
    final removedItemName = _addedItems[index].product.name;
    setState(() => _addedItems.removeAt(index));
    _showSuccessSnackBar('goods_receiving_screen.success_item_removed'.tr(namedArgs: {'removedItemName': removedItemName}), isError: true);
  }

  Future<void> _saveAndConfirm() async {
    if (_addedItems.isEmpty) {
      _showErrorSnackBar('goods_receiving_screen.error_at_least_one_item'.tr());
      return;
    }
    final bool? confirmed = await _showConfirmationListDialog();
    if (confirmed != true) return;
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');

      if (employeeId == null) {
        throw Exception('User ID not found. Please log in again.');
      }

      final payload = GoodsReceiptPayload(
        header: GoodsReceiptHeader(
          siparisId: _selectedOrder?.id,
          invoiceNumber: _selectedOrder?.poId,
          receiptDate: DateTime.now(),
          employeeId: employeeId,
        ),
        items: _addedItems.map((draft) => GoodsReceiptItemPayload(
          urunId: draft.product.id,
          quantity: draft.quantity,
          palletBarcode: draft.palletBarcode,
        )).toList(),
      );

      await _repository.saveGoodsReceipt(payload);

      if (mounted) {
        _showSuccessSnackBar('goods_receiving_screen.success_receipt_saved'.tr());
        context.read<SyncService>().performFullSync(force: true);
        _handleSuccessfulSave();
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('goods_receiving_screen.error_saving'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleSuccessfulSave() {
    if (isOrderBased) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _addedItems.clear();
        _clearEntryFields(clearPallet: true);
        _productFocusNode.requestFocus();
      });
    }
  }

  void _clearEntryFields({required bool clearPallet}) {
    _productController.clear();
    _quantityController.clear();
    _selectedProduct = null;
    if (clearPallet) {
      _palletIdController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    final areFieldsEnabled = !_isOrderDetailsLoading && !_isSaving;

    return Scaffold(
      appBar: SharedAppBar(
        title: 'goods_receiving_screen.title'.tr(),
        showBackButton: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: isKeyboardVisible ? null : _buildBottomBar(),
      body: SafeArea(
        child: _isLoading
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
                  if (isOrderBased) ...[
                    OrderInfoCard(order: _selectedOrder!),
                    const SizedBox(height: _gap),
                  ],
                  _buildModeSelector(),
                  const SizedBox(height: _gap),
                  if (_receivingMode == ReceivingMode.palet) ...[
                    _buildPalletIdInput(isEnabled: areFieldsEnabled),
                    const SizedBox(height: _gap),
                  ],
                  _buildSearchableProductInputRow(isEnabled: areFieldsEnabled),
                  const SizedBox(height: _gap),
                  _buildQuantityAndStatusRow(isEnabled: areFieldsEnabled),
                  const SizedBox(height: _gap),
                  _buildLastAddedItemSummary(textTheme, colorScheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
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
        selected: {_receivingMode},
        onSelectionChanged: (newSelection) {
          if (_isSaving) return;
          setState(() {
            _clearEntryFields(clearPallet: true);
            _receivingMode = newSelection.first;

            if (_receivingMode == ReceivingMode.palet) {
              _palletIdFocusNode.requestFocus();
            } else {
              _productFocusNode.requestFocus();
            }
          });
        },
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.comfortable,
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }

  Widget _buildPalletIdInput({required bool isEnabled}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: _palletIdController,
            focusNode: _palletIdFocusNode,
            enabled: isEnabled,
            decoration: _inputDecoration('goods_receiving_screen.label_pallet_barcode'.tr(), enabled: isEnabled),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) _productFocusNode.requestFocus();
            },
            validator: (value) {
              if (!isEnabled) return null;
              if (_receivingMode == ReceivingMode.palet && (value == null || value.isEmpty)) {
                return 'goods_receiving_screen.validator_pallet_barcode'.tr();
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(
          onTap: () async {
            final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
            if (result != null && result.isNotEmpty && mounted) {
              _palletIdController.text = result;
              _productFocusNode.requestFocus();
            }
          },
          isEnabled: isEnabled,
        ),
      ],
    );
  }

  Widget _buildSearchableProductInputRow({required bool isEnabled}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            enabled: isEnabled,
            controller: _productController,
            focusNode: _productFocusNode,
            readOnly: true,
            decoration: _inputDecoration(
              isOrderBased
                  ? 'goods_receiving_screen.label_select_product_in_order'.tr()
                  : 'goods_receiving_screen.label_select_product'.tr(),
              suffixIcon: const Icon(Icons.arrow_drop_down),
              enabled: isEnabled,
            ),
            onTap: !isEnabled ? null : () async {
              final productList = isOrderBased
                  ? _orderItems.map((orderItem) => orderItem.product).whereNotNull().toList()
                  : _availableProducts;
              final ProductInfo? selected = await _showSearchableDropdownDialog<ProductInfo>(
                title: 'goods_receiving_screen.label_select_product'.tr(),
                items: productList,
                itemToString: (product) => "${product.name} (${product.stockCode})",
                filterCondition: (product, query) {
                  final lowerQuery = query.toLowerCase();
                  return product.name.toLowerCase().contains(lowerQuery) ||
                      product.stockCode.toLowerCase().contains(lowerQuery) ||
                      (product.barcode1?.toLowerCase().contains(lowerQuery) ?? false);
                },
              );
              if (selected != null) {
                _selectProduct(selected);
              }
            },
            validator: (value) {
              if (!isEnabled) return null;
              return (value == null || value.isEmpty) ? 'goods_receiving_screen.validator_select_product'.tr() : null;
            },
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(
          onTap: () async {
            final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
            if (result != null && result.isNotEmpty && mounted) {
              _processScannedProduct(result);
            }
          },
          isEnabled: isEnabled,
        ),
      ],
    );
  }

  Widget _buildQuantityAndStatusRow({required bool isEnabled}) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final orderItem = _selectedProduct == null || !isOrderBased
        ? null
        : _orderItems.firstWhereOrNull((item) => item.product?.id == _selectedProduct!.id);

    double totalReceived = 0;
    double expectedQty = 0;

    if (orderItem != null) {
      final alreadyAddedInUI = _addedItems
          .where((item) => item.product.id == orderItem.product!.id)
          .map((item) => item.quantity)
          .fold(0.0, (prev, qty) => prev + qty);
      final receivedQty = orderItem.receivedQuantity;
      expectedQty = orderItem.expectedQuantity;
      totalReceived = receivedQty + alreadyAddedInUI;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: TextFormField(
            controller: _quantityController,
            focusNode: _quantityFocusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            enabled: isEnabled,
            decoration: _inputDecoration('goods_receiving_screen.label_quantity'.tr(), enabled: isEnabled),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) _addItemToList();
            },
            validator: (value) {
              if (!isEnabled) return null;
              if (value == null || value.isEmpty) return 'goods_receiving_screen.validator_enter_quantity'.tr();
              final number = double.tryParse(value);
              if (number == null || number <= 0) return 'goods_receiving_screen.validator_enter_valid_quantity'.tr();
              return null;
            },
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          flex: 1,
          child: InputDecorator(
            decoration: _inputDecoration('goods_receiving_screen.label_order_status'.tr(), enabled: false),
            child: Center(
              child: (!isOrderBased || _selectedProduct == null)
                  ? Text("- / -", style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.hintColor))
                  : RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: '${totalReceived.toStringAsFixed(0)} ',
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900),
                    ),
                    TextSpan(text: '/ ', style: TextStyle(color: textTheme.bodyLarge?.color)),
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

  Widget _buildLastAddedItemSummary(TextTheme textTheme, ColorScheme colorScheme) {
    final lastItem = _addedItems.isNotEmpty ? _addedItems.first : null;
    return Container(
      padding: const EdgeInsets.all(_smallGap),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: _borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(_smallGap),
            child: Text(
              'goods_receiving_screen.header_added_items'.tr(namedArgs: {'count': _addedItems.length.toString()}),
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          if (lastItem == null)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  'goods_receiving.no_items'.tr(),
                  style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                ),
              ),
            )
          else
            ListTile(
              dense: true,
              title: Text(lastItem.product.name, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              subtitle: Text(
                lastItem.palletBarcode != null
                    ? 'goods_receiving_screen.label_pallet_barcode_display'.tr(namedArgs: {'barcode': lastItem.palletBarcode!})
                    : 'goods_receiving_screen.mode_box'.tr(),
                style: textTheme.bodySmall,
              ),

              trailing: Text(
                'goods_receiving_screen.label_quantity_display'.tr(namedArgs: {'quantity': lastItem.quantity.toStringAsFixed(0)}),
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_isLoading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ElevatedButton.icon(
        onPressed: _addedItems.isEmpty || _isSaving ? null : _saveAndConfirm,
        icon: _isSaving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check_circle_outline),
        label: FittedBox(
          child: Text('goods_receiving_screen.button_save_and_confirm'.tr()),
        ),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: enabled ? theme.inputDecorationTheme.fillColor : theme.colorScheme.onSurface.withOpacity(0.04),
      border: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 10),
    );
  }

  Future<bool?> _showConfirmationListDialog() {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullscreenConfirmationPage(
          items: _addedItems,
          onItemRemoved: (item) {
            final index = _addedItems.indexOf(item);
            if (index != -1) {
              _removeItemFromList(index);
            }
          },
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

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.orangeAccent : Colors.green,
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
      height: 48,
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
      _filteredItems = widget.items
          .where((item) => widget.filterCondition(item, _searchQuery))
          .toList();
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

class _FullscreenConfirmationPage extends StatefulWidget {
  final List<ReceiptItemDraft> items;
  final ValueChanged<ReceiptItemDraft> onItemRemoved;

  const _FullscreenConfirmationPage({
    required this.items,
    required this.onItemRemoved,
  });

  @override
  State<_FullscreenConfirmationPage> createState() => _FullscreenConfirmationPageState();
}

class _FullscreenConfirmationPageState extends State<_FullscreenConfirmationPage> {
  late final List<ReceiptItemDraft> _currentItems;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.items);
  }

  void _handleRemoveItem(ReceiptItemDraft item) {
    widget.onItemRemoved(item);
    setState(() {
      _currentItems.remove(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('goods_receiving_screen.dialog_confirmation_title'.tr()),
        backgroundColor: appBarTheme.backgroundColor,
        foregroundColor: appBarTheme.foregroundColor,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _currentItems.isEmpty
          ? Center(child: Text('goods_receiving_screen.dialog_list_empty'.tr()))
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _currentItems.length,
        itemBuilder: (context, index) {
          final item = _currentItems[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ListTile(
              title: Text(item.product.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.palletBarcode != null
                  ? 'goods_receiving_screen.label_pallet_barcode_display'.tr(namedArgs: {'barcode': item.palletBarcode!})
                  : 'goods_receiving.not_specified'.tr()),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(item.quantity.toStringAsFixed(0),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: Icon(
                      Icons.delete_outline, color: theme.colorScheme.error),
                  onPressed: () => _handleRemoveItem(item),
                ),
              ]),
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _currentItems.isEmpty ? null : () =>
              Navigator.of(context).pop(true),
          child: Text('goods_receiving_screen.dialog_button_confirm_and_save'.tr()),
        ),
      ),
    );
  }
}
