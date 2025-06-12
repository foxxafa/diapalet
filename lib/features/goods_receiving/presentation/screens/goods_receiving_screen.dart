// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/local/database_helper.dart';
import 'package:diapalet/features/goods_receiving/data/goods_receiving_repository_impl.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/widgets/barcode_scanner_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/shared_app_bar.dart';

enum GoodsReceivingMode { pallet, box }

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late final GoodsReceivingRepository _repository;
  final _formKey = GlobalKey<FormState>();

  final _receiptNumberController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  List<PurchaseOrder> _allPurchaseOrders = [];
  List<PurchaseOrder> _filteredPurchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
  final List<GoodsReceiptItem> _receiptItems = [];
  final Map<int, TextEditingController> _quantityControllers = {};

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
    _repository = GoodsReceivingRepositoryImpl(dbHelper: dbHelper);
    _loadPurchaseOrders();
  }

  @override
  void dispose() {
    _receiptNumberController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    _quantityControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _loadPurchaseOrders() async {
    setState(() => _isLoading = true);
    try {
      final orders = await _repository.getOpenPurchaseOrders();
      if (mounted) {
        setState(() {
          _allPurchaseOrders = orders;
          _filteredPurchaseOrders = orders;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('goods_receiving.errors.load_orders'.tr(args: [e.toString()]))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterPurchaseOrders(String query) {
    setState(() {
      _filteredPurchaseOrders = _allPurchaseOrders
          .where((order) =>
              (order.poId?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
              (order.supplierName?.toLowerCase().contains(query.toLowerCase()) ?? false))
          .toList();
    });
  }

  Future<void> _selectOrder(PurchaseOrder order) async {
    setState(() {
      _selectedOrder = order;
      _receiptItems.clear();
      _orderItems = [];
      _quantityControllers.forEach((_, c) => c.dispose());
      _quantityControllers.clear();
      _isLoading = true;
    });

    try {
      final items = await _repository.getPurchaseOrderItems(order.id);
      if (mounted) {
        setState(() {
          _orderItems = items;
          for (var item in items) {
            _quantityControllers[item.id] = TextEditingController();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('goods_receiving.errors.load_order_items'.tr(args: [e.toString()]))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveReceipt() async {
    if (!_formKey.currentState!.validate() || _selectedOrder == null) return;
    if (_receiptItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('goods_receiving.errors.add_item_prompt'.tr())),
      );
      return;
    }

    setState(() => _isSaving = true);

    final receipt = GoodsReceipt(
      id: 0,
      purchaseOrderId: _selectedOrder!.id,
      receiptNumber: _receiptNumberController.text,
      receiptDate: DateTime.now(),
      notes: _notesController.text,
      status: 'pending',
      items: _receiptItems,
    );

    try {
      await _repository.saveGoodsReceipt(receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('goods_receiving.success.receipt_saved'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('goods_receiving.errors.save_receipt'.tr(args: [e.toString()])),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onOrderItemChanged(PurchaseOrderItem item, String value) {
    final quantity = double.tryParse(value) ?? 0.0;
    _receiptItems.removeWhere((receiptItem) => receiptItem.productId == item.productId);

    if (quantity > 0) {
      _receiptItems.add(
        GoodsReceiptItem(
          id: 0,
          goodsReceiptId: 0,
          productId: item.productId,
          quantity: quantity,
          notes: '',
        ),
      );
    }
    setState(() {});
  }
  
  void _onBarcodeScanned(String barcode) {
    // This could try to find a matching PO or item
  }

  void _reset() {
    setState(() {
      _selectedOrder = null;
      _orderItems.clear();
      _receiptItems.clear();
      _receiptNumberController.clear();
      _notesController.clear();
      _searchController.clear();
      _filteredPurchaseOrders = _allPurchaseOrders;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'goods_receiving.title'.tr(),
        actions: [
          if (_selectedOrder != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _reset,
              tooltip: 'common.clear_selection'.tr(),
            )
        ],
      ),
      body: _selectedOrder == null ? _buildOrderSelectionUI() : _buildItemEntryUI(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    if (_selectedOrder == null || _orderItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveReceipt,
        icon: _isSaving
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_alt_outlined),
        label: Text('common.save'.tr()),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          textStyle: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildOrderSelectionUI() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: CustomTextField(
            controller: _searchController,
            labelText: 'goods_receiving.search_po'.tr(),
            hintText: 'goods_receiving.search_po_hint'.tr(),
            prefixIcon: const Icon(Icons.search),
            onChanged: _filterPurchaseOrders,
          ),
        ),
        if (_isLoading && _filteredPurchaseOrders.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_filteredPurchaseOrders.isEmpty)
          Expanded(
            child: Center(
              child: Text('goods_receiving.no_open_pos'.tr()),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _filteredPurchaseOrders.length,
              itemBuilder: (context, index) {
                final order = _filteredPurchaseOrders[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    title: Text(order.poId ?? 'PO #${order.id}'),
                    subtitle: Text(order.supplierName ?? 'goods_receiving.unknown_supplier'.tr()),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _selectOrder(order),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildItemEntryUI() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildSelectedOrderHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _orderItems.isEmpty
                    ? Center(child: Text('goods_receiving.no_items_in_order'.tr()))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _orderItems.length,
                        itemBuilder: (context, index) {
                          return _buildOrderItemCard(_orderItems[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedOrderHeader() {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedOrder?.poId ?? 'PO #${_selectedOrder?.id}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              _selectedOrder?.supplierName ?? 'goods_receiving.unknown_supplier'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _receiptNumberController,
              labelText: 'goods_receiving.delivery_note_number'.tr(),
              hintText: 'goods_receiving.delivery_note_number_hint'.tr(),
              validator: (val) => val == null || val.isEmpty ? 'validation.required'.tr() : null,
              suffixIcon: BarcodeScannerButton(onScan: (code) => _receiptNumberController.text = code),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _notesController,
              labelText: 'common.notes'.tr(),
              hintText: 'common.notes_optional_hint'.tr(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemCard(PurchaseOrderItem item) {
    final qtyController = _quantityControllers[item.id]!;
    final alreadyReceived = 0.0; // Placeholder
    final remaining = (item.expectedQuantity ?? 0.0) - alreadyReceived;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName ?? 'goods_receiving.unknown_product'.tr(), style: Theme.of(context).textTheme.titleMedium),
            Text(item.productCode ?? '', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('goods_receiving.ordered'.tr(), style: Theme.of(context).textTheme.bodySmall),
                      Text(item.expectedQuantity.toString(), style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('goods_receiving.remaining'.tr(), style: Theme.of(context).textTheme.bodySmall),
                      Text(remaining.toString(), style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: CustomTextField(
                    controller: qtyController,
                    labelText: 'goods_receiving.received_qty'.tr(),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => _onOrderItemChanged(item, val),
                    validator: (val) {
                      final num? entered = num.tryParse(val ?? '0');
                      if (entered != null && entered > remaining) {
                        return 'goods_receiving.errors.qty_exceeds_remaining'.tr();
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
