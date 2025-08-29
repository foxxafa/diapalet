// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/order_info_card.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/qr_text_field.dart';
import 'package:diapalet/core/utils/keyboard_utils.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_view_model.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                  : KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (KeyEvent event) {
                            // F3 tuşu veya Ctrl+S kombinasyonu ile barkod okuma tetikle
                            if (event is KeyDownEvent) {
                              final isCtrl = HardwareKeyboard.instance.isControlPressed;
                              if (event.logicalKey == LogicalKeyboardKey.f3 ||
                                  (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS)) {
                                _triggerBarcodeScanning(viewModel);
                              }
                            }
                          },
                      child: GestureDetector(
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
                            // Mode selector sadece mixed modda göster
                            FutureBuilder<bool>(
                              future: viewModel.shouldShowModeSelector,
                              builder: (context, snapshot) {
                                if (snapshot.data == true) {
                                  return Column(
                                    children: [
                                      _buildModeSelector(viewModel),
                                      const SizedBox(height: _gap),
                                    ],
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            // Delivery note number for free receipt
                            if (!viewModel.isOrderBased) ...[
                              TextFormField(
                                controller: viewModel.deliveryNoteController,
                                focusNode: viewModel.deliveryNoteFocusNode,
                                decoration: _inputDecoration(
                                  'goods_receiving_screen.label_delivery_note'.tr(),
                                  enabled: viewModel.isDeliveryNoteEnabled,
                                ),
                                validator: viewModel.validateDeliveryNote,
                                enabled: viewModel.isDeliveryNoteEnabled,
                              ),
                              const SizedBox(height: _gap),
                            ],
                            if (viewModel.receivingMode == ReceivingMode.palet) ...[
                              _buildPalletIdField(viewModel),
                              const SizedBox(height: _gap),
                            ],
                            _buildProductTextAreaWithScan(viewModel),
                            const SizedBox(height: _gap),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildExpiryDateField(viewModel),
                                if (viewModel.selectedProduct != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4.0, top: 4.0),
                                    child: Text(
                                      'goods_receiving_screen.date_input_helper'.tr(),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).hintColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
            ),
          );
        },
      ),
    );
  }

  void _triggerBarcodeScanning(GoodsReceivingViewModel viewModel) async {
    // İlk önce manuel scan'i dene (mevcut metni işle)
    await viewModel.triggerManualScan();

    // Eğer hala bir sonuç yoksa, QR scanner'ı aç
    await Future.delayed(const Duration(milliseconds: 100)); // Kısa bir gecikme

    if (viewModel.productFocusNode.hasFocus && viewModel.selectedProduct == null) {
  final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QrScannerScreen())
      );
  if (!mounted) return;
  if (result != null && result.isNotEmpty) {
        await viewModel.processScannedData('product', result, context: context);
      }
    } else if (viewModel.palletIdFocusNode.hasFocus && viewModel.palletIdController.text.isEmpty) {
  final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QrScannerScreen())
      );
  if (!mounted) return;
  if (result != null && result.isNotEmpty) {
        await viewModel.processScannedData('pallet', result, context: context);
      }
    }
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
              value: ReceivingMode.product,
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

  Widget _buildProductTextAreaWithScan(GoodsReceivingViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QrTextField(
          controller: viewModel.productController,
          focusNode: viewModel.productFocusNode,
          enabled: viewModel.areFieldsEnabled,
          maxLines: 1,
          labelText: viewModel.selectedProduct == null 
            ? (viewModel.isOrderBased
                ? 'goods_receiving_screen.label_select_product_in_order'.tr()
                : 'goods_receiving_screen.label_select_product'.tr())
            : '${viewModel.selectedProduct!.name} (${viewModel.selectedProduct!.stockCode})',
          onChanged: (value) {
            // Auto-search and select product as user types
            viewModel.onProductTextChanged(value);

            // Focus expiry date field when product is selected
            if (value.length > 5 && viewModel.selectedProduct != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && viewModel.selectedProduct != null && viewModel.isExpiryDateEnabled) {
                  viewModel.expiryDateFocusNode.requestFocus();
                }
              });
            }
          },
          onFieldSubmitted: (value) async {
            // Enter'a basıldığında ürünü ara ve seç
            if (value.isNotEmpty) {
              // Eğer search sonuçları varsa ilk sonucu seç
              if (viewModel.productSearchResults.isNotEmpty) {
                viewModel.selectProduct(viewModel.productSearchResults.first);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && viewModel.selectedProduct != null && viewModel.isExpiryDateEnabled) {
                    viewModel.expiryDateFocusNode.requestFocus();
                  }
                });
              } else {
                // Search sonuçları yoksa barkod olarak işle
                await viewModel.processScannedData('product', value, context: context);
                // UI güncellemesi tamamlandıktan sonra çalıştır
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && viewModel.selectedProduct != null && viewModel.isExpiryDateEnabled) {
                    viewModel.expiryDateFocusNode.requestFocus();
                  }
                });
              }
            }
          },
          textInputAction: TextInputAction.search,
          validator: viewModel.validateProduct,
          // Karmaşık QR buton mantığı için özel callback
          onQrTap: () async {
            if (viewModel.areFieldsEnabled) {
              // İlk önce manuel scan'i dene
              viewModel.triggerManualScan();

              // Eğer hala sonuç yoksa QR scanner'ı aç
              await Future.delayed(const Duration(milliseconds: 100));
              if (viewModel.selectedProduct == null) {
                // Klavyeyi kapat
                await KeyboardUtils.prepareForQrScanner(context, 
                  focusNodes: [viewModel.productFocusNode]);
                
                final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (context) => const QrScannerScreen())
                );
                if (!mounted) return;
                if (result != null && result.isNotEmpty) {
                  await viewModel.processScannedData('product', result, context: context);
                }
              }
            }
          },
        ),
        if (viewModel.productSearchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: _borderRadius,
            ),
            child: Column(
              children: viewModel.productSearchResults.take(5).map((product) {
                return ListTile(
                  dense: true,
                  title: Text(
                    product.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    "Barkod: ${product.productBarcode ?? 'N/A'} | Stok Kodu: ${product.stockCode} | Birim: ${product.displayUnitName ?? 'N/A'}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () async {
                    await viewModel.selectProduct(product, context: context);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && viewModel.isExpiryDateEnabled) {
                        viewModel.expiryDateFocusNode.requestFocus();
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPalletIdField(GoodsReceivingViewModel viewModel) {
    return QrTextField(
      controller: viewModel.palletIdController,
      focusNode: viewModel.palletIdFocusNode,
      labelText: 'goods_receiving_screen.label_pallet_barcode'.tr(),
      enabled: viewModel.areFieldsEnabled,
      onFieldSubmitted: (value) async {
        if (value.isNotEmpty) {
          await viewModel.processScannedData('pallet', value, context: context);
        }
      },
      onQrScanned: (result) async {
        // Karmaşık mantığı callback'te işle
        final currentText = viewModel.palletIdController.text.trim();
        if (currentText.isNotEmpty) {
          await viewModel.processScannedData('pallet', currentText, context: context);
        } else {
          await viewModel.processScannedData('pallet', result, context: context);
        }
      },
      validator: viewModel.validatePalletId,
    );
  }

  Widget _buildQuantityAndStatusRow(GoodsReceivingViewModel viewModel) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    PurchaseOrderItem? orderItem;
    if (viewModel.selectedProduct != null && viewModel.isOrderBased) {
      // Sipariş dışı ürünler için orderItem arama yapma
      if (viewModel.selectedProduct!.isOutOfOrder) {
        debugPrint("DEBUG: Out-of-order product, not searching for orderItem. Using ProductInfo.orderQuantity: ${viewModel.selectedProduct!.orderQuantity}");
        orderItem = null;
      } else {
        try {
          // HATA DÜZELTMESİ: item.product?.id yerine item.productId kullan
          orderItem = viewModel.orderItems.firstWhere((item) => item.productId == viewModel.selectedProduct!.key);
          debugPrint("DEBUG: Found orderItem for product ${viewModel.selectedProduct!.key} (searching with key): expectedQuantity=${orderItem.expectedQuantity}");
        } catch (e) {
          debugPrint("DEBUG: OrderItem not found for product ${viewModel.selectedProduct!.key} (search key). Available orderItems: ${viewModel.orderItems.map((item) => 'productId=${item.productId}, expectedQuantity=${item.expectedQuantity}')}");
          orderItem = null;
        }
      }
    }

    double alreadyAddedInUI = 0.0;
    if (orderItem != null) {
      for (final item in viewModel.addedItems) {
        // HATA DÜZELTMESİ: orderItem.productId ile karşılaştır
        if (item.product.key == orderItem.productId) {
          alreadyAddedInUI += item.quantity;
        }
      }
    }

    final totalReceived = (orderItem?.receivedQuantity ?? 0.0) + alreadyAddedInUI;
    final expectedQty = orderItem?.expectedQuantity ?? viewModel.selectedProduct?.orderQuantity ?? 0.0;
    debugPrint("DEBUG: Order status display - expectedQty: $expectedQty, totalReceived: $totalReceived");
    
    // Sipariş dışı ürün debug
    if (orderItem == null && viewModel.selectedProduct != null) {
      debugPrint("DEBUG: Sipariş dışı ürün - ProductInfo.orderQuantity: ${viewModel.selectedProduct!.orderQuantity}");
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
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
                  viewModel.addItemToList(context);
                }
              }
            },
            validator: viewModel.validateQuantity,
          ),
        ),
        const SizedBox(width: _smallGap),
        Expanded(
          flex: 5,
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
                            text: '${totalReceived.toStringAsFixed(0)}',
                            style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          TextSpan(text: '/', style: TextStyle(color: textTheme.bodyLarge?.color?.withAlpha(179))),
                          TextSpan(text: '${expectedQty.toStringAsFixed(0)} ', style: TextStyle(color: textTheme.bodyLarge?.color)),
                          TextSpan(
                            text: viewModel.selectedProduct?.displayUnitName ?? '',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
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
    return StatefulBuilder(
      builder: (context, setState) {
        return TextFormField(
          controller: viewModel.expiryDateController,
          focusNode: viewModel.expiryDateFocusNode,
          enabled: viewModel.isExpiryDateEnabled,
          readOnly: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [
            _DateInputFormatter(),
          ],
          decoration: _inputDecoration(
            'goods_receiving_screen.label_expiry_date'.tr(),
            enabled: viewModel.isExpiryDateEnabled,
            suffixIcon: viewModel.expiryDateController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: viewModel.isExpiryDateEnabled
                        ? () {
                            viewModel.expiryDateController.clear();
                            setState(() {}); // Rebuild to update suffix icon
                            viewModel.expiryDateFocusNode.requestFocus();
                          }
                        : null,
                  )
                : const Icon(Icons.edit_calendar_outlined),
            hintText: 'DD/MM/YYYY',
          ),
          validator: viewModel.validateExpiryDate,
          onChanged: (value) {
            setState(() {}); // Rebuild to update suffix icon
            // DD/MM/YYYY formatı tamamlandıysa ve geçerli tarihse quantity field'a geç
            if (value.length == 10) {
              bool isValid = _isValidDate(value);
              // Debug: Date: $value, IsValid: $isValid
              if (isValid) {
                viewModel.onExpiryDateEntered();
              }
            }
          },
          onFieldSubmitted: (value) {
            if (value.length == 10) {
              if (_isValidDate(value)) {
                viewModel.onExpiryDateEntered();
              } else {
                // Check if it's a past date or invalid date
                String errorMessage = _getDateErrorMessage(value);
                // Debug: Error for $value: $errorMessage
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        );
      },
    );
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
            'goods_receiving_screen.header_last_added_item'.tr() + ' (${viewModel.addedItemsCount})',
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

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon, bool enabled = true, String? hintText}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hintText,
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

    // Pallet modunda sadece pallet barcode ve product selection alanlarına el terminali ile giriş izinli
    if (viewModel.receivingMode == ReceivingMode.palet) {
      if (viewModel.palletIdFocusNode.hasFocus) {
        viewModel.processScannedData('pallet', code, context: context);
      } else if (viewModel.productFocusNode.hasFocus) {
        viewModel.processScannedData('product', code, context: context);
      } else {
        // Pallet modunda diğer alanlar focus'ta ise barkod okutmayı engelle
        if (viewModel.expiryDateFocusNode.hasFocus || 
            viewModel.quantityFocusNode.hasFocus ||
            viewModel.deliveryNoteFocusNode.hasFocus) {
          // Bu alanlar el terminali ile doldurulmasın
          return;
        }
        
        // Eğer başka bir alan focus'ta değilse, öncelik sırasına göre işle
        if (viewModel.palletIdController.text.isEmpty) {
          viewModel.processScannedData('pallet', code, context: context);
        } else {
          viewModel.productFocusNode.requestFocus();
          viewModel.processScannedData('product', code, context: context);
        }
      }
    } else {
      // Product modunda eski davranışı koru
      if (viewModel.palletIdFocusNode.hasFocus) {
        viewModel.processScannedData('pallet', code, context: context);
      } else if (viewModel.productFocusNode.hasFocus) {
        viewModel.processScannedData('product', code, context: context);
      } else {
        viewModel.productFocusNode.requestFocus();
        viewModel.processScannedData('product', code, context: context);
      }
    }
  }

}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Handle deletion - if user deletes a slash, delete the preceding digit too
    if (newValue.text.length < oldValue.text.length) {
      if (newValue.text.isNotEmpty && oldValue.text.length > newValue.text.length) {
        final deletedChar = oldValue.text[newValue.text.length];
        if (deletedChar == '/' && newValue.text.isNotEmpty) {
          return TextEditingValue(
            text: newValue.text.substring(0, newValue.text.length - 1),
            selection: TextSelection.collapsed(offset: newValue.text.length - 1),
          );
        }
      }
      return newValue;
    }
    
    // Only allow digits
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (text.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    
    if (text.length > 8) return oldValue;
    
    // Smart formatting with validation
    String formatted = _smartFormatDate(text);
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
  
  String _smartFormatDate(String digits) {
    String result = '';
    
    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) result += '/';
      
      // Add digit with smart validation
      String digit = digits[i];
      
      // Day validation (position 0-1)
      if (i < 2) {
        if (i == 0 && int.parse(digit) > 3) {
          digit = '3'; // Max day starts with 3
        } else if (i == 1 && result.isNotEmpty) {
          int firstDigit = int.parse(result[0]);
          int dayValue = firstDigit * 10 + int.parse(digit);
          if (dayValue > 31) {
            digit = '1'; // 31 max
          } else if (dayValue == 0) {
            digit = '1'; // Min 01
          }
        }
      }
      // Month validation (position 2-3)
      else if (i < 4) {
        int monthPos = i - 2;
        if (monthPos == 0 && int.parse(digit) > 1) {
          digit = '1'; // Max month starts with 1
        } else if (monthPos == 1) {
          String monthFirstDigit = result.split('/')[1];
          int firstDigit = int.parse(monthFirstDigit);
          int monthValue = firstDigit * 10 + int.parse(digit);
          if (monthValue > 12) {
            digit = '2'; // 12 max
          } else if (monthValue == 0) {
            digit = '1'; // Min 01
          }
        }
      }
      
      result += digit;
    }
    
    // Final validation when we have complete date (8 digits)
    if (digits.length == 8) {
      result = _validateCompleteDate(result);
    }
    
    return result;
  }
  
  String _validateCompleteDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length != 3) return dateStr;
      
      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);
      
      // Create DateTime to check validity
      final date = DateTime(year, month, day);
      
      // If date was adjusted, use the adjusted values
      if (date.day != day || date.month != month) {
        // DateTime adjusted it, which means original was invalid
        // Use last day of the intended month
        final lastDay = DateTime(year, month + 1, 0).day;
        day = day > lastDay ? lastDay : day;
        
        return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}';
      }
      
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

}

// Helper function to get specific error message for date validation
String _getDateErrorMessage(String dateString) {
  if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dateString)) {
    return 'goods_receiving_screen.error_expiry_date_invalid'.tr();
  }
  
  try {
    final parts = dateString.split('/');
    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final year = int.parse(parts[2]);
    
    // First check if it's a valid date structure
    if (month < 1 || month > 12 || day < 1) {
      return 'goods_receiving_screen.error_expiry_date_invalid'.tr();
    }
    
    // Create DateTime to check if date is valid
    final date = DateTime(year, month, day);
    
    // Check if date was adjusted (invalid date like Feb 30)
    if (date.day != day || date.month != month || date.year != year) {
      // This means the date doesn't exist (like 30/02 or 31/04)
      return 'goods_receiving_screen.error_expiry_date_invalid'.tr();
    }
    
    // Now check if date is in the past
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    
    if (date.isBefore(todayDate)) {
      return 'goods_receiving_screen.error_expiry_date_past'.tr();
    }
    
    // If we reach here, the date should be valid
    return 'goods_receiving_screen.error_expiry_date_invalid'.tr();
  } catch (e) {
    return 'goods_receiving_screen.error_expiry_date_invalid'.tr();
  }
}

// Helper function to validate date - using DateTime's built-in validation
bool _isValidDate(String dateString) {
  if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dateString)) {
    return false;
  }
  
  try {
    final parts = dateString.split('/');
    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final year = int.parse(parts[2]);
    
    // Basic year check - must be current year or later
    final currentYear = DateTime.now().year;
    if (year < currentYear) {
      return false;
    }
    
    // Create DateTime - it will adjust invalid dates automatically
    final date = DateTime(year, month, day);
    
    // DateTime constructor adjusts invalid dates, so check if it's still the same
    if (date.day != day || date.month != month || date.year != year) {
      return false;
    }
    
    // Check if date is not in the past
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    
    return !date.isBefore(todayDate);
  } catch (e) {
    return false;
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
        color: theme.colorScheme.primaryContainer.withAlpha(128),
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

        // HATA DÜZELTMESİ: orderItem.productId ile karşılaştır, product.id değil
        final itemsBeingAdded = viewModel.addedItems.where((item) => item.product.key == orderItem.productId).toList();
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

