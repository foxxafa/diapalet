// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order_item.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late final GoodsReceivingRepository _repository;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _receiptNumberController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();
  final Map<int, TextEditingController> _quantityControllers = {};

  // State
  List<PurchaseOrder> _allPurchaseOrders = [];
  List<PurchaseOrder> _filteredPurchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<PurchaseOrderItem> _orderItems = [];
  final List<GoodsReceiptItem> _receiptItems = [];

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
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
      if (mounted) _showSnackBar('Siparişler yüklenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterPurchaseOrders(String query) {
    setState(() {
      _filteredPurchaseOrders = _allPurchaseOrders.where((order) {
        final poId = order.poId?.toLowerCase() ?? '';
        final supplier = order.supplierName?.toLowerCase() ?? '';
        final queryLower = query.toLowerCase();
        return poId.contains(queryLower) || supplier.contains(queryLower);
      }).toList();
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
      if (mounted) _showSnackBar('Sipariş kalemleri yüklenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveReceipt() async {
    if (!(_formKey.currentState?.validate() ?? false) || _selectedOrder == null) return;
    if (_receiptItems.isEmpty) {
      _showSnackBar('Kaydetmek için en az bir ürünün miktarını girin.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // DÜZELTME: Eksik olan 'id' ve 'status' parametreleri eklendi.
      final receipt = GoodsReceipt(
        id: 0, // ID veritabanı tarafından atanacağı için 0 gönderilebilir.
        purchaseOrderId: _selectedOrder!.id,
        receiptNumber: _receiptNumberController.text,
        receiptDate: DateTime.now(),
        notes: _notesController.text,
        status: 'pending', // Başlangıç durumu olarak 'pending' ayarlandı.
        items: _receiptItems,
      );

      await _repository.saveGoodsReceipt(receipt);
      if (!mounted) return;
      _showSnackBar("Mal kabul başarıyla kaydedildi.", isError: false);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _showSnackBar('Kayıt başarısız: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onOrderItemChanged(PurchaseOrderItem item, String value) {
    final quantity = double.tryParse(value) ?? 0.0;
    _receiptItems.removeWhere((receiptItem) => receiptItem.productId == item.productId);

    if (quantity > 0) {
      // DÜZELTME: Eksik olan 'id' ve 'goodsReceiptId' parametreleri eklendi.
      _receiptItems.add(
        GoodsReceiptItem(
          id: 0, // Bu ID veritabanı tarafından atanacak.
          goodsReceiptId: 0, // Bu ID asıl fiş kaydedildikten sonra atanacak.
          productId: item.productId,
          quantity: quantity,
        ),
      );
    }
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

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ));
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
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,))
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
          child: TextFormField(
            controller: _searchController,
            decoration: InputDecoration(
                labelText: 'goods_receiving.search_po'.tr(),
                hintText: 'goods_receiving.search_po_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder()
            ),
            onChanged: _filterPurchaseOrders,
          ),
        ),
        if (_isLoading && _filteredPurchaseOrders.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_filteredPurchaseOrders.isEmpty)
          Expanded(child: Center(child: Text('goods_receiving.no_open_pos'.tr())))
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
                    subtitle: Text(order.supplierName ?? 'Bilinmeyen Tedarikçi'),
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
                ? const Center(child: Text('Bu siparişte ürün bulunmuyor.'))
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _orderItems.length,
              itemBuilder: (context, index) => _buildOrderItemCard(_orderItems[index]),
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
            Text(_selectedOrder?.poId ?? 'PO #${_selectedOrder?.id}', style: Theme.of(context).textTheme.headlineSmall),
            Text(_selectedOrder?.supplierName ?? 'Bilinmeyen Tedarikçi', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _receiptNumberController,
              decoration: InputDecoration(
                labelText: 'İrsaliye Numarası',
                hintText: 'Varsa irsaliye numarasını girin',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
                    if (code != null) _receiptNumberController.text = code;
                  },
                ),
              ),
              validator: (val) => val == null || val.isEmpty ? 'Bu alan zorunludur' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notlar',
                hintText: 'İsteğe bağlı notlar',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemCard(PurchaseOrderItem item) {
    final qtyController = _quantityControllers[item.id]!;
    const alreadyReceived = 0.0;
    final remaining = item.expectedQuantity - alreadyReceived;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName ?? 'Bilinmeyen Ürün', style: Theme.of(context).textTheme.titleMedium),
            Text(item.stockCode ?? '', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildInfoColumn('Sipariş', item.expectedQuantity.toStringAsFixed(0))),
                Expanded(child: _buildInfoColumn('Kalan', remaining.toStringAsFixed(0))),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: qtyController,
                    decoration: const InputDecoration(labelText: 'Gelen Miktar', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => _onOrderItemChanged(item, val),
                    validator: (val) {
                      final entered = num.tryParse(val ?? '0');
                      if (entered != null && entered > remaining) return 'Kalanı aşamaz';
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

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
