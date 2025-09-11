import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_view_model.dart';

class CompactReviewTable extends StatelessWidget {
  final GoodsReceivingViewModel viewModel;
  final ValueChanged<ReceiptItemDraft> onItemRemoved;
  final List<PurchaseOrderItem> orderItems;
  final List<ProductInfo> outOfOrderItems;
  final bool isFreeReceiving;
  final String? deliveryNoteNumber;

  const CompactReviewTable({
    super.key,
    required this.viewModel,
    required this.onItemRemoved,
    this.orderItems = const [],
    this.outOfOrderItems = const [],
    this.isFreeReceiving = false,
    this.deliveryNoteNumber,
  });

  @override
  Widget build(BuildContext context) {
    if (viewModel.addedItems.isEmpty && orderItems.isEmpty && outOfOrderItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'goods_receiving_screen.dialog_list_empty'.tr(),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: [
        // Sipariş ürünleri
        if (orderItems.isNotEmpty)
          ..._buildOrderItemRows(context),
        
        // Sipariş dışı ürünler - sadece serbest mal kabulde delivery note bazında gruplanmış
        if (isFreeReceiving && (outOfOrderItems.isNotEmpty || viewModel.addedItems.any((item) => item.product.isOutOfOrder))) ...[
          ..._buildDeliveryNoteGroupedItems(context),
        ],
      ],
    );
  }

  Widget _buildSectionDivider(BuildContext context, String title) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          if (isFreeReceiving && deliveryNoteNumber != null && deliveryNoteNumber!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(77),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withAlpha(51),
                  width: 0.5,
                ),
              ),
              child: Text(
                deliveryNoteNumber!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildOrderItemRows(BuildContext context) {
    final widgets = <Widget>[];
    
    // Sort order items by total quantity (items being added + already received) - highest first  
    final sortedOrderItems = [...orderItems];
    sortedOrderItems.sort((a, b) {
      final aItemsBeingAdded = viewModel.addedItems.where((item) => 
        item.product.key == a.productId && !item.product.isOutOfOrder
      );
      final bItemsBeingAdded = viewModel.addedItems.where((item) => 
        item.product.key == b.productId && !item.product.isOutOfOrder
      );
      
      final aTotalQuantity = aItemsBeingAdded.fold<double>(0.0, (sum, item) => sum + item.quantity);
      final bTotalQuantity = bItemsBeingAdded.fold<double>(0.0, (sum, item) => sum + item.quantity);
      
      return bTotalQuantity.compareTo(aTotalQuantity);
    });

    // Tüm ürünleri topla: sipariş içi + sipariş dışı (sipariş bazlı mal kabulde)
    final allItems = <ReceiptItemDraft>[];
    
    // Sipariş içi ürünler
    for (final orderItem in sortedOrderItems) {
      final itemsBeingAdded = viewModel.addedItems.where((item) => 
        item.product.key == orderItem.productId && !item.product.isOutOfOrder
      ).toList();
      allItems.addAll(itemsBeingAdded);
    }
    
    // Sipariş dışı ürünler (sipariş bazlı mal kabulde)
    if (!isFreeReceiving) {
      final outOfOrderItems = viewModel.addedItems.where((item) => item.product.isOutOfOrder).toList();
      allItems.addAll(outOfOrderItems);
    }
    
    if (allItems.isNotEmpty) {
      // Palet bazında gruplama
      final Map<String?, List<ReceiptItemDraft>> palletGroups = {};
      final List<ReceiptItemDraft> looseItems = [];
      
      for (final item in allItems) {
        if (item.palletBarcode != null && item.palletBarcode!.isNotEmpty) {
          palletGroups.putIfAbsent(item.palletBarcode, () => []).add(item);
        } else {
          looseItems.add(item);
        }
      }
      
      // 🚚 Her pallet için section
      palletGroups.forEach((palletBarcode, palletItems) {
        widgets.add(_buildPalletHeader(context, palletBarcode!));
        // Palet içindeki ürünler (indent)
        for (final item in palletItems) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildProductCard(
              context: context,
              productName: item.product.name,
              stockCode: item.product.stockCode,
              items: [item],
              isOutOfOrder: item.product.isOutOfOrder,
            ),
          ));
        }
      });
      
      // 📦 Loose Items (palet olmayan ürünler)
      if (looseItems.isNotEmpty) {
        widgets.add(_buildLooseItemsHeader(context));
        for (final item in looseItems) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildProductCard(
              context: context,
              productName: item.product.name,
              stockCode: item.product.stockCode,
              items: [item],
              isOutOfOrder: item.product.isOutOfOrder,
            ),
          ));
        }
      }
    }
    
    // Miktar eklenmemiş sipariş ürünleri (0 quantity olanlar)
    for (final orderItem in sortedOrderItems) {
      final product = orderItem.product;
      if (product == null) continue;

      final itemsBeingAdded = viewModel.addedItems.where((item) => 
        item.product.key == orderItem.productId && !item.product.isOutOfOrder
      ).toList();
      
      // Sadece miktar eklenmemiş ürünleri göster
      if (itemsBeingAdded.isEmpty) {
        widgets.add(_buildProductCard(
          context: context,
          productName: product.name,
          stockCode: product.stockCode,
          items: [],
          orderItem: orderItem,
        ));
      }
    }
    
    return widgets;
  }

  List<Widget> _buildDeliveryNoteGroupedItems(BuildContext context) {
    final widgets = <Widget>[];
    
    // Memory'deki sipariş dışı ürünler
    final memoryOutOfOrderItems = viewModel.addedItems.where((item) => item.product.isOutOfOrder).toList();
    
    // Delivery note bazında gruplama - artık her item'ın kendi delivery note'u var
    final Map<String?, List<ReceiptItemDraft>> deliveryNoteGroups = {};
    
    for (final item in memoryOutOfOrderItems) {
      final itemDeliveryNote = item.deliveryNoteNumber ?? deliveryNoteNumber;
      deliveryNoteGroups.putIfAbsent(itemDeliveryNote, () => []).add(item);
    }
    
    // Her delivery note grubu için widget oluştur
    deliveryNoteGroups.forEach((deliveryNote, items) {
      // 📄 Delivery Note Header
      widgets.add(_buildDeliveryNoteHeaderWithNumber(context, deliveryNote));
      
      // Bu delivery note'daki ürünleri pallet bazında grupla
      final Map<String?, List<ReceiptItemDraft>> palletGroups = {};
      final List<ReceiptItemDraft> looseItems = [];
      
      for (final item in items) {
        if (item.palletBarcode != null && item.palletBarcode!.isNotEmpty) {
          palletGroups.putIfAbsent(item.palletBarcode, () => []).add(item);
        } else {
          looseItems.add(item);
        }
      }
      
      // 🚚 Her pallet için section
      palletGroups.forEach((palletBarcode, palletItems) {
        widgets.add(_buildPalletHeader(context, palletBarcode!));
        // Palet içindeki ürünler (indent)
        for (final item in palletItems) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildProductCard(
              context: context,
              productName: item.product.name,
              stockCode: item.product.stockCode,
              items: [item],
              isOutOfOrder: true,
            ),
          ));
        }
      });
      
      // 📦 Loose Items
      if (looseItems.isNotEmpty) {
        widgets.add(_buildLooseItemsHeader(context));
        for (final item in looseItems) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildProductCard(
              context: context,
              productName: item.product.name,
              stockCode: item.product.stockCode,
              items: [item],
              isOutOfOrder: true,
            ),
          ));
        }
      }
    });
    
    // DB'deki ürünleri ekle (sadece sipariş bazlı mal kabul modunda)
    if (outOfOrderItems.isNotEmpty && !isFreeReceiving) {
      widgets.add(_buildDeliveryNoteHeaderWithNumber(context, "Önceki Kabuller"));
      for (final productInfo in outOfOrderItems) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 16),
          child: _buildProductCard(
            context: context,
            productName: productInfo.name,
            stockCode: productInfo.stockCode,
            items: [],
            productInfo: productInfo,
            isOutOfOrder: true,
            isFromDB: true,
          ),
        ));
      }
    }
    
    return widgets;
  }

  List<Widget> _buildOrderBasedOutOfOrderItems(BuildContext context) {
    final widgets = <Widget>[];
    
    // Memory'deki sipariş dışı ürünler
    final memoryOutOfOrderItems = viewModel.addedItems.where((item) => item.product.isOutOfOrder).toList();
    
    // Sipariş dışı ürünleri direkt liste halinde göster (delivery note header olmadan)
    for (final item in memoryOutOfOrderItems) {
      widgets.add(_buildProductCard(
        context: context,
        productName: item.product.name,
        stockCode: item.product.stockCode,
        items: [item],
        isOutOfOrder: true,
      ));
    }
    
    // DB'deki önceki kabul edilmiş ürünler
    for (final productInfo in outOfOrderItems) {
      widgets.add(_buildProductCard(
        context: context,
        productName: productInfo.name,
        stockCode: productInfo.stockCode,
        items: [],
        productInfo: productInfo,
        isOutOfOrder: true,
        isFromDB: true,
      ));
    }
    
    return widgets;
  }

  // 📄 Delivery Note Header
  Widget _buildDeliveryNoteHeader(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Delivery Note:',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          if (deliveryNoteNumber != null && deliveryNoteNumber!.isNotEmpty) ...[
            Text(
              deliveryNoteNumber!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ] else ...[
            Text(
              'Genel',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 📄 Delivery Note Header with specific number
  Widget _buildDeliveryNoteHeaderWithNumber(BuildContext context, String? noteNumber) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Delivery Note:',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            noteNumber ?? 'Genel',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: noteNumber != null ? 'monospace' : null,
              color: noteNumber != null ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  // 🚚 Pallet Header
  Widget _buildPalletHeader(BuildContext context, String palletBarcode) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.pallet,
            size: 16,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            'Pallet:',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            palletBarcode,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  // 📦 Loose Items Header
  Widget _buildLooseItemsHeader(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Text(
            'goods_receiving_screen.other_items'.tr(),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildProductCard({
    required BuildContext context,
    required String productName,
    required String stockCode,
    required List<ReceiptItemDraft> items,
    PurchaseOrderItem? orderItem,
    ProductInfo? productInfo,
    bool isOutOfOrder = false,
    bool isFromDB = false,
  }) {
    final theme = Theme.of(context);
    final totalQuantity = items.fold<double>(0.0, (sum, item) => sum + item.quantity);
    final unit = items.isNotEmpty 
        ? items.first.product.displayUnitName ?? ''
        : orderItem?.unitName ?? orderItem?.unit ?? productInfo?.displayUnitName ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      color: (!isFreeReceiving && isOutOfOrder) 
          ? const Color(0xFFFFF3E0) 
          : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: (!isFreeReceiving && isOutOfOrder) 
              ? const Color(0xFFFF9800) 
              : theme.dividerColor.withAlpha(128),
          width: 0.5,
        ),
      ),
      child: InkWell(
        onTap: (!isOutOfOrder && !isFromDB && (items.isNotEmpty || orderItem != null)) ? () => _showDetailDialog(context, productName, stockCode, items, orderItem, productInfo) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            productName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          stockCode,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // SKT ve sipariş dışı badge'lerini göster - palet bilgisi header olarak gösterilecek
                        if (items.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ..._buildProductExtraInfo(context, items, showPalletInfo: false, isOutOfOrder: isOutOfOrder),
                        ],
                        
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Quantity info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isFromDB && productInfo != null) ...[
                    Text(
                      '${(productInfo.quantityReceived ?? 0.0).toStringAsFixed(0)} $unit',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ] else if (items.isNotEmpty) ...[
                    Text(
                      '${totalQuantity.toStringAsFixed(0)} $unit',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ] else if (orderItem != null) ...[
                    Text(
                      '0 $unit',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(width: 8),
              
              // Action button
              if (!isFromDB && items.isNotEmpty) ...[
                items.length == 1
                    ? IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                          size: 22,
                        ),
                        onPressed: () => onItemRemoved(items.first),
                        tooltip: 'common_labels.delete'.tr(),
                      )
                    : PopupMenuButton<ReceiptItemDraft>(
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                          size: 22,
                        ),
                        itemBuilder: (context) => items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return PopupMenuItem(
                            value: item,
                            child: Text('${index + 1}. ${'common_labels.delete'.tr()}'),
                          );
                        }).toList(),
                        onSelected: (item) => onItemRemoved(item),
                        tooltip: 'common_labels.delete'.tr(),
                      ),
              ] else ...[
                const SizedBox(width: 48), // Boş alan - ikonları kaldır
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildProductExtraInfo(BuildContext context, List<ReceiptItemDraft> items, {PurchaseOrderItem? orderItem, bool showPalletInfo = true, bool isOutOfOrder = false}) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    
    // Tek bir SKT varsa göster
    final expiryDates = items.where((item) => item.expiryDate != null).map((item) => item.expiryDate!).toSet();
    if (expiryDates.length == 1) {
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer.withAlpha(204),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withAlpha(77),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 12, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(
                DateFormat('dd/MM/yy').format(expiryDates.first),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Palet bilgisini göster - sadece showPalletInfo true ise
    if (showPalletInfo) {
      Set<String> allPalletBarcodes = {};
      
      // Items'dan palet bilgisi
      final itemsPalletBarcodes = items.where((item) => item.palletBarcode != null && item.palletBarcode!.isNotEmpty).map((item) => item.palletBarcode!);
      allPalletBarcodes.addAll(itemsPalletBarcodes);
      
      if (allPalletBarcodes.isNotEmpty) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 8));
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withAlpha(153),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.secondary.withAlpha(77),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pallet, size: 12, color: theme.colorScheme.secondary),
              const SizedBox(width: 3),
              Text(
                allPalletBarcodes.length == 1 ? allPalletBarcodes.first : '${allPalletBarcodes.length}x',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
      }
    }
    
    return widgets;
  }

  void _showDetailDialog(
    BuildContext context,
    String productName,
    String stockCode,
    List<ReceiptItemDraft> items,
    PurchaseOrderItem? orderItem,
    ProductInfo? productInfo,
  ) {
    showDialog(
      context: context,
      builder: (context) => ProductDetailDialog(
        productName: productName,
        stockCode: stockCode,
        items: items,
        orderItem: orderItem,
        productInfo: productInfo,
        onItemRemoved: onItemRemoved,
      ),
    );
  }

}

class ProductDetailDialog extends StatelessWidget {
  final String productName;
  final String stockCode;
  final List<ReceiptItemDraft> items;
  final PurchaseOrderItem? orderItem;
  final ProductInfo? productInfo;
  final ValueChanged<ReceiptItemDraft> onItemRemoved;

  const ProductDetailDialog({
    super.key,
    required this.productName,
    required this.stockCode,
    required this.items,
    this.orderItem,
    this.productInfo,
    required this.onItemRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.8,
          maxWidth: mediaQuery.size.width * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(26),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stockCode,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(179),
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'common_labels.close'.tr(),
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order summary (if applicable)
                    if (orderItem != null) ...[
                      _buildOrderSummary(context),
                      const SizedBox(height: 20),
                    ],
                    
                    // DB product summary (if applicable)
                    if (productInfo != null) ...[
                      _buildDBProductSummary(context),
                      const SizedBox(height: 20),
                    ],
                    
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary(BuildContext context) {
    if (orderItem == null) return const SizedBox.shrink();
    
    final theme = Theme.of(context);
    final quantityBeingAdded = items.fold<double>(0.0, (sum, item) => sum + item.quantity);
    final remaining = (orderItem!.expectedQuantity - orderItem!.receivedQuantity - quantityBeingAdded)
        .clamp(0.0, double.infinity);
    final unit = orderItem!.unitName ?? orderItem!.unit ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(77),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withAlpha(77),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'goods_receiving_screen.order_info_title'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // SKT bilgisi (items varsa)
          if (items.isNotEmpty) ...[
            _buildExpiryInfo(context),
            const SizedBox(height: 12),
          ],
          
          _buildStatRow(context, 'goods_receiving_screen.confirmation.ordered'.tr(), '${orderItem!.expectedQuantity.toStringAsFixed(0)}', unit),
          const SizedBox(height: 8),
          _buildStatRow(context, 'goods_receiving_screen.confirmation.previously_received'.tr(), '${orderItem!.receivedQuantity.toStringAsFixed(0)}', unit),
          const SizedBox(height: 8),
          _buildStatRow(context, 'goods_receiving_screen.confirmation.currently_adding'.tr(), '${quantityBeingAdded.toStringAsFixed(0)}', unit, 
            color: theme.colorScheme.primary),
          if (remaining > 0) ...[
            const SizedBox(height: 8),
            _buildStatRow(context, 'goods_receiving_screen.confirmation.remaining_after'.tr(), '${remaining.toStringAsFixed(0)}', unit, 
              color: theme.colorScheme.error),
          ],
        ],
      ),
    );
  }

  Widget _buildDBProductSummary(BuildContext context) {
    if (productInfo == null) return const SizedBox.shrink();
    
    final theme = Theme.of(context);
    final quantity = productInfo!.quantityReceived ?? 0.0;
    final unit = productInfo!.displayUnitName ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withAlpha(77),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withAlpha(77),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2,
                color: theme.colorScheme.secondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'goods_receiving_screen.out_of_order_products'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: _buildStatColumn(context, 'Kabul Edilen', '${quantity.toStringAsFixed(0)}', unit, 
              color: theme.colorScheme.secondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(BuildContext context, String label, String value, String unit, {Color? color}) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          unit,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color ?? theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value, String unit, {Color? color}) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyLarge,
        ),
        Text(
          '$value $unit',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          items.length == 1 ? 'Eklenen Ürün' : 'Eklenen Ürünler (${items.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildItemRow(context, item, index + 1);
        }),
      ],
    );
  }

  Widget _buildItemRow(BuildContext context, ReceiptItemDraft item, int index) {
    final theme = Theme.of(context);
    final expiryText = item.expiryDate != null 
        ? DateFormat('dd/MM/yyyy').format(item.expiryDate!) 
        : null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withAlpha(128),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withAlpha(128),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Index
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                index.toString(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Item info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantity.toStringAsFixed(0)} ${item.product.displayUnitName ?? ''}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.palletBarcode != null || expiryText != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (item.palletBarcode != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pallet, size: 16, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(
                              item.palletBarcode!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      if (expiryText != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule, size: 16, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(
                              expiryText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // Delete button
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            onPressed: () {
              onItemRemoved(item);
              if (items.length == 1) {
                Navigator.of(context).pop();
              }
            },
            tooltip: 'Sil',
          ),
        ],
      ),
    );
  }

  Widget _buildExpiryInfo(BuildContext context) {
    final theme = Theme.of(context);
    
    // Tüm SKT'leri topla
    final expiryDates = items.where((item) => item.expiryDate != null).map((item) => item.expiryDate!).toSet().toList();
    if (expiryDates.isEmpty) return const SizedBox.shrink();
    
    expiryDates.sort();
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer.withAlpha(128),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(77),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'goods_receiving_screen.label_expiry_date'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: expiryDates.length == 1
                ? Text(
                    DateFormat('dd/MM/yyyy').format(expiryDates.first),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.end,
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: expiryDates.map((date) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(26),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yy').format(date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: theme.colorScheme.outline.withAlpha(128),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz eklenen ürün yok',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Bu ürün için miktar eklemek üzere ana ekrana geri dönebilirsiniz',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
