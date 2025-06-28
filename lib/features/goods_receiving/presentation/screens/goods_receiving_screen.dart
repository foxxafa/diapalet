// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'dart:io';
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
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// Onay ekranından hangi aksiyonun seçildiğini belirtmek için.
enum ConfirmationAction { save, complete }

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
  final List<ReceiptItemDraft> _addedItems = [];

  final _palletIdController = TextEditingController();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();

  final _palletIdFocusNode = FocusNode();
  final _productFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  // Barcode service
  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;
  StreamSubscription<SyncStatus>? _syncStatusSub;

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    final syncService = Provider.of<SyncService>(context, listen: false);

    _selectedOrder = widget.selectedOrder;
    _isFreeReceiveMode = widget.selectedOrder == null;

    _palletIdFocusNode.addListener(_onFocusChange);
    _productFocusNode.addListener(_onFocusChange);

    _loadInitialData();
    _initBarcode();

    _syncStatusSub = syncService.syncStatusStream.listen((status) {
      if (status == SyncStatus.upToDate && mounted && isOrderBased) {
        debugPrint("Sync completed on goods receiving screen, refreshing order details...");
        _loadOrderDetails(_selectedOrder!.id);
      }
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _syncStatusSub?.cancel();
    _palletIdFocusNode.removeListener(_onFocusChange);
    _productFocusNode.removeListener(_onFocusChange);
    _palletIdController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    _palletIdFocusNode.dispose();
    _productFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_palletIdFocusNode.hasFocus && _palletIdController.text.isNotEmpty) {
      _palletIdController.selection = TextSelection(baseOffset: 0, extentOffset: _palletIdController.text.length);
    }
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_receivingMode == ReceivingMode.palet) {
              _palletIdFocusNode.requestFocus();
            } else {
              _productFocusNode.requestFocus();
            }
          });
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

  Future<void> _processScannedData(String field, String data) async {
    if (data.isEmpty) return;

    switch (field) {
      case 'pallet':
        _palletIdController.text = data;
        _productFocusNode.requestFocus();
        break;
      case 'product':
        final productSource = isOrderBased
            ? _orderItems.map((item) => item.product).whereType<ProductInfo>().toList()
            : _availableProducts;

        ProductInfo? foundProduct;
        try {
          foundProduct = productSource.firstWhere((p) =>
          p.stockCode.toLowerCase() == data.toLowerCase() ||
              (p.barcode1?.toLowerCase() == data.toLowerCase()),
          );
        } catch(e) {
          foundProduct = null;
        }

        if (foundProduct != null) {
          _selectProduct(foundProduct);
        } else {
          _productController.clear();
          _selectedProduct = null;
          _showErrorSnackBar('goods_receiving_screen.error_product_not_found'.tr(namedArgs: {'scannedData': data}));
        }
        break;
    }
  }

  void _selectProduct(ProductInfo product) {
    setState(() {
      _selectedProduct = product;
      _productController.text = "${product.name} (${product.stockCode})";
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quantityFocusNode.requestFocus();
    });
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
      final orderItem = _orderItems.firstWhere((item) => item.product?.id == currentProduct.id, orElse: () => throw Exception("Item not found in order"));
      final alreadyAddedInUI = _addedItems
          .where((item) => item.product.id == currentProduct.id)
          .map((item) => item.quantity)
          .fold(0.0, (prev, qty) => prev + qty);
      final totalPreviouslyReceived = orderItem.receivedQuantity;
      final remainingQuantity = orderItem.expectedQuantity - totalPreviouslyReceived - alreadyAddedInUI;

      if (quantity > remainingQuantity + 0.001) { // Adding a small tolerance for double comparisons
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _productFocusNode.requestFocus();
    });
  }

  void _removeItemFromList(int index) {
    if (!mounted) return;
    final removedItemName = _addedItems[index].product.name;
    setState(() => _addedItems.removeAt(index));
    _showSuccessSnackBar('goods_receiving_screen.success_item_removed'.tr(namedArgs: {'removedItemName': removedItemName}), isError: true);
  }

  Future<void> _saveAndConfirm() async {
    if (_addedItems.isEmpty && (_selectedOrder == null || _orderItems.every((item) => item.receivedQuantity >= item.expectedQuantity))) {
      _showErrorSnackBar('goods_receiving_screen.error_at_least_one_item'.tr());
      return;
    }

    // Gözden geçirme ve onaylama ekranını göster
    final result = await _showConfirmationListDialog();

    if (result == null) return; // Kullanıcı dialogu kapattı

    setState(() => _isSaving = true);
    try {
      if (result == ConfirmationAction.save) {
        // SADECE KAYDETME İŞLEMİ
        if (_addedItems.isEmpty) {
          _showErrorSnackBar('goods_receiving_screen.error_no_new_items_to_save'.tr());
          return;
        }
        await _executeSave();
        if (mounted) {
          _handleSuccessfulSave();
          context.read<SyncService>().uploadPendingOperations(); // TEK SENKRONİZASYON ÇAĞRISI
        }
      } else if (result == ConfirmationAction.complete && _selectedOrder != null) {
        // KAYDET VE TAMAMLA İŞLEMİ
        // Adım 1: Varsa, yeni eklenen ürünleri yerel olarak kaydet.
        if (_addedItems.isNotEmpty) {
          await _executeSave(); // Bu fonksiyon artık sync tetiklemiyor.
        }

        // Adım 2: Siparişi tamamlama işlemini yerel olarak kuyruğa ekle.
        await _repository.markOrderAsComplete(_selectedOrder!.id);

        // Adım 3: Tüm yerel işlemler bittikten sonra, TEK BİR senkronizasyon başlat.
        if (mounted) {
          context.read<SyncService>().uploadPendingOperations();
          _showSuccessSnackBar('orders.dialog.success_message'.tr(namedArgs: {'poId': _selectedOrder!.poId ?? ''}));
          Navigator.of(context).pop(true); // Liste ekranına dön ve yenile.
        }
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('goods_receiving_screen.error_saving'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _executeSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');

      if (employeeId == null) throw Exception('common_labels.user_id_not_found'.tr());

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

    } catch (e) {
      rethrow;
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
                    _buildPalletIdField(areFieldsEnabled: areFieldsEnabled),
                    const SizedBox(height: _gap),
                  ],
                  _buildHybridDropdownWithQr<ProductInfo>(
                    controller: _productController,
                    focusNode: _productFocusNode,
                    label: isOrderBased
                        ? 'goods_receiving_screen.label_select_product_in_order'.tr()
                        : 'goods_receiving_screen.label_select_product'.tr(),
                    fieldIdentifier: 'product',
                    isEnabled: areFieldsEnabled,
                    items: isOrderBased
                        ? _orderItems.map((orderItem) => orderItem.product).whereType<ProductInfo>().toList()
                        : _availableProducts,
                    itemToString: (product) => "${product.name} (${product.stockCode})",
                    onItemSelected: (product) {
                      if (product != null) {
                        _selectProduct(product);
                      }
                    },
                    filterCondition: (product, query) {
                      final lowerQuery = query.toLowerCase();
                      return product.name.toLowerCase().contains(lowerQuery) ||
                          product.stockCode.toLowerCase().contains(lowerQuery) ||
                          (product.barcode1?.toLowerCase().contains(lowerQuery) ?? false);
                    },
                    validator: (value) {
                      if (!areFieldsEnabled) return null;
                      return (value == null || value.isEmpty || _selectedProduct == null) ? 'goods_receiving_screen.validator_select_product'.tr() : null;
                    },
                  ),
                  const SizedBox(height: _gap),
                  if (_selectedProduct != null) ...[
                    _buildQuantityAndStatusRow(isEnabled: areFieldsEnabled),
                    const SizedBox(height: _gap),
                  ],
                  _buildAddedItemsSection(textTheme, colorScheme),
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
          FocusScope.of(context).unfocus();
          setState(() {
            _clearEntryFields(clearPallet: true);
            _receivingMode = newSelection.first;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
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

  Widget _buildPalletIdField({required bool areFieldsEnabled}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: _palletIdController,
            focusNode: _palletIdFocusNode,
            enabled: areFieldsEnabled,
            decoration: _inputDecoration(
              'goods_receiving_screen.label_pallet_barcode'.tr(),
              enabled: areFieldsEnabled,
            ),
            onFieldSubmitted: (value) {
              if (value.isNotEmpty) {
                _processScannedData('pallet', value);
              }
            },
            validator: (value) {
              if (!areFieldsEnabled) return null;
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
            if (result != null && result.isNotEmpty) {
              _processScannedData('pallet', result);
            }
          },
          isEnabled: areFieldsEnabled,
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
            readOnly: true, // Make it readonly to force selection from dialog
            controller: controller,
            focusNode: focusNode,
            enabled: isEnabled,
            decoration: _inputDecoration(
              label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
              enabled: isEnabled,
            ),
            onTap: items.isEmpty ? null : () async {
              // Always show search dialog on tap
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
              _processScannedData(fieldIdentifier, result);
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

    PurchaseOrderItem? orderItem;
    if (_selectedProduct != null && isOrderBased) {
      try {
        orderItem = _orderItems.firstWhere((item) => item.product?.id == _selectedProduct!.id);
      } catch (e) {
        orderItem = null;
      }
    }

    double alreadyAddedInUI = 0.0;
    if (orderItem != null && orderItem.product != null) {
      for (final item in _addedItems) {
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
        const SizedBox(width: _smallGap),
        Expanded(
          flex: 4,
          child: InputDecorator(
            decoration: _inputDecoration('goods_receiving_screen.label_order_status'.tr(), enabled: false),
            child: Center(
              child: (!isOrderBased || _selectedProduct == null)
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
                    TextSpan(text: '/ ', style: TextStyle(color: textTheme.bodyLarge?.color?.withOpacity(0.7))),
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

  Widget _buildAddedItemsSection(TextTheme textTheme, ColorScheme colorScheme) {
    if (_addedItems.isEmpty) {
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

    final item = _addedItems.first; // This is the most recently added item.
    String unitText = '';
    if (isOrderBased) {
      try {
        final orderItem = _orderItems.firstWhere((oi) => oi.product?.id == item.product.id);
        unitText = orderItem.unit ?? '';
      } catch (e) {
        // Safe fallback. Unit will be empty.
      }
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
            subtitle: Text(
              item.palletBarcode != null
                  ? 'goods_receiving_screen.label_pallet_barcode_display'.tr(namedArgs: {'barcode': item.palletBarcode!})
                  : 'goods_receiving_screen.mode_box'.tr(),
              style: textTheme.bodySmall,
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
                  onPressed: () => _removeItemFromList(0), // Always removes the last added item
                  tooltip: 'common_labels.delete'.tr(),
                ),
              ],
            ),
          ),
        ),
      ],
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
      enabledBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: _borderRadius, borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: true,
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(height: 0.8, fontSize: 10),
    );
  }

  Future<ConfirmationAction?> _showConfirmationListDialog() {
    return Navigator.push<ConfirmationAction>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullscreenConfirmationPage(
          order: _selectedOrder,
          orderItems: _orderItems,
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

  // --- Barcode Handling ---
  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;

    _barcodeService = BarcodeIntentService();

    try {
      final first = await _barcodeService.getInitialBarcode();
      if (first != null && first.isNotEmpty) _handleBarcode(first);
    } catch(e) {
      // ignore
    }

    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _showErrorSnackBar('common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()})));
  }

  void _handleBarcode(String code) {
    if (!mounted) return;

    if (_palletIdFocusNode.hasFocus) {
      _processScannedData('pallet', code);
    } else if (_productFocusNode.hasFocus) {
      _processScannedData('product', code);
    } else {
      if (_receivingMode == ReceivingMode.palet && _palletIdController.text.isEmpty) {
        _processScannedData('pallet', code);
      } else if (_selectedProduct == null) {
        _productFocusNode.requestFocus();
        _processScannedData('product', code);
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
  final PurchaseOrder? order;
  final List<PurchaseOrderItem> orderItems;
  final List<ReceiptItemDraft> items;
  final ValueChanged<ReceiptItemDraft> onItemRemoved;

  const _FullscreenConfirmationPage({
    super.key,
    this.order,
    required this.orderItems,
    required this.items,
    required this.onItemRemoved,
  });

  @override
  State<_FullscreenConfirmationPage> createState() => _FullscreenConfirmationPageState();
}

class _FullscreenConfirmationPageState extends State<_FullscreenConfirmationPage> {
  late final List<ReceiptItemDraft> _currentItems;
  bool get isOrderBased => widget.order != null;

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.items);
  }

  void _handleRemoveItem(ReceiptItemDraft item) {
    widget.onItemRemoved(item);
    setState(() => _currentItems.remove(item));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    // --- BUTON GÖRÜNÜRLÜK MANTIĞI ---
    bool areAllItemsFullyReceived = false;
    if (isOrderBased) {
      // Harita: urun_id -> bu ekranda eklenen toplam miktar
      final currentAdditionMap = <int, double>{};
      for (var item in _currentItems) {
        currentAdditionMap.update(item.product.id, (value) => value + item.quantity, ifAbsent: () => item.quantity);
      }

      // Her bir sipariş kaleminin tamamlanıp tamamlanmadığını kontrol et
      areAllItemsFullyReceived = widget.orderItems.every((orderItem) {
        final expected = orderItem.expectedQuantity;
        final previouslyReceived = orderItem.receivedQuantity;
        final currentlyAdding = currentAdditionMap[orderItem.product!.id] ?? 0;
        // Küçük bir tolerans payı ile karşılaştır
        return previouslyReceived + currentlyAdding >= expected - 0.001;
      });
    }

    // "Fişi Kaydet" butonu, sadece tüm ürünler tamamlanMAMIŞSA gösterilir.
    final bool showSaveReceiptButton = !areAllItemsFullyReceived;
    // "Tamamla" butonu, sipariş bazlı modda her zaman bir seçenek olmalı.
    final bool showCompleteButton = isOrderBased;
    // --- BİTTİ: BUTON GÖRÜNÜRLÜK MANTIĞI ---

    return Scaffold(
      appBar: AppBar(
        title: Text('goods_receiving_screen.dialog_confirmation_title'.tr()),
        backgroundColor: appBarTheme.backgroundColor,
        foregroundColor: appBarTheme.foregroundColor,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: isOrderBased
          ? _buildOrderBasedConfirmationList(theme)
          : _buildFreeReceiveConfirmationList(theme),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "Fişi Kaydet" butonu, sadece hala kabul edilecek ürün varsa mantıklıdır.
            if (showSaveReceiptButton)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _currentItems.isEmpty ? null : () => Navigator.of(context).pop(ConfirmationAction.save),
                child: Text('goods_receiving_screen.dialog_button_save_receipt'.tr()),
              ),
            
            // Eğer her şey tamsa, "Kaydet ve Tamamla" birincil aksiyon olmalı.
            // Değilse, ikincil aksiyon olarak görünmeli.
            if (showCompleteButton) ...[
              if (showSaveReceiptButton) const SizedBox(height: 8), // Eğer üstteki buton varsa boşluk bırak
              
              areAllItemsFullyReceived
                  ? ElevatedButton( // Birincil Buton stili
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: _currentItems.isEmpty ? null : () => Navigator.of(context).pop(ConfirmationAction.complete),
                child: Text('orders.menu.mark_as_complete'.tr()),
              )
                  : OutlinedButton( // İkincil Buton stili
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: theme.colorScheme.primary),
                ),
                onPressed: _currentItems.isEmpty ? null : () => Navigator.of(context).pop(ConfirmationAction.complete),
                child: Text('orders.menu.mark_as_complete'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFreeReceiveConfirmationList(ThemeData theme) {
    final groupedItems = <int, List<ReceiptItemDraft>>{};
    for (final item in _currentItems) {
      groupedItems.putIfAbsent(item.product.id, () => []).add(item);
    }
    final productIds = groupedItems.keys.toList();

    if (_currentItems.isEmpty) {
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
                            child: Text(
                              item.palletBarcode != null
                                  ? 'goods_receiving_screen.label_pallet_barcode_display_short'.tr(namedArgs: {'barcode': item.palletBarcode!})
                                  : 'goods_receiving_screen.mode_box'.tr(),
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
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
                                  onPressed: () => _handleRemoveItem(item),
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
                  }).toList(),
                ],
              ),
            )
        );
      },
    );
  }

  Widget _buildOrderBasedConfirmationList(ThemeData theme) {
    if (widget.orderItems.isEmpty && _currentItems.isEmpty) {
      return Center(child: Text('goods_receiving_screen.dialog_list_empty'.tr()));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.orderItems.length,
      itemBuilder: (context, index) {
        final orderItem = widget.orderItems[index];
        final product = orderItem.product;
        if (product == null) return const SizedBox.shrink();

        final itemsBeingAdded = _currentItems.where((item) => item.product.id == product.id).toList();
        final quantityBeingAdded = itemsBeingAdded.fold<double>(0.0, (sum, item) => sum + item.quantity);

        if (itemsBeingAdded.isEmpty && orderItem.expectedQuantity - orderItem.receivedQuantity <= 0) {
           return const SizedBox.shrink();
        }

        return _OrderProductConfirmationCard(
          orderItem: orderItem,
          itemsBeingAdded: itemsBeingAdded,
          quantityBeingAdded: quantityBeingAdded,
          onRemoveItem: _handleRemoveItem,
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
                Text(
                  "(${product.stockCode})",
                  style: textTheme.bodyMedium?.copyWith(color: textTheme.bodySmall?.color)
                ),
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
                        child: Text(
                          item.palletBarcode != null
                              ? 'goods_receiving_screen.label_pallet_barcode_display_short'.tr(namedArgs: {'barcode': item.palletBarcode!})
                              : 'goods_receiving_screen.mode_box'.tr(),
                          style: textTheme.bodyMedium,
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

class _OrderSummaryCard extends StatelessWidget {
  final PurchaseOrder order;
  final List<PurchaseOrderItem> orderItems;
  final List<ReceiptItemDraft> addedItems;

  const _OrderSummaryCard({required this.order, required this.orderItems, required this.addedItems});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    double totalOrdered = orderItems.fold(0.0, (sum, item) => sum + item.expectedQuantity);
    double totalPreviouslyReceived = orderItems.fold(0.0, (sum, item) => sum + item.receivedQuantity);
    double totalCurrentlyAdding = addedItems.fold(0.0, (sum, item) => sum + item.quantity);

    final totalAfterThisReceipt = totalPreviouslyReceived + totalCurrentlyAdding;
    final remainingAfterThisReceipt = (totalOrdered - totalAfterThisReceipt).clamp(0, double.infinity).toDouble();

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('goods_receiving_screen.order_summary_title'.tr(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildStatusRow(context, 'goods_receiving_screen.order_info.ordered'.tr(), totalOrdered),
            const Divider(height: 24),
            _buildStatusRow(context, 'goods_receiving_screen.order_info.total_received'.tr(), totalAfterThisReceipt, highlight: true),
            const Divider(height: 24),
            _buildStatusRow(context, 'goods_receiving_screen.order_info.remaining'.tr(), remainingAfterThisReceipt),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, String label, double value, {bool highlight = false}) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: textTheme.bodyLarge),
        Text(
          value.toStringAsFixed(0),
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight ? colorScheme.primary : textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }
}
