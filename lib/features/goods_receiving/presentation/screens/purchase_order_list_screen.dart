// lib/features/goods_receiving/presentation/screens/purchase_order_list_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:diapalet/features/goods_receiving/presentation/screens/goods_receiving_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  State<PurchaseOrderListScreen> createState() => _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  late final GoodsReceivingRepository _repository;
  List<PurchaseOrder> _allOrders = [];
  List<PurchaseOrder> _filteredOrders = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadOrders();
    _searchController.addListener(_filterOrders);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterOrders);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final orders = await _repository.getOpenPurchaseOrders();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _filteredOrders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('orders.error_loading'.tr(namedArgs: {'error': e.toString()}))),
        );
      }
    }
  }

  void _filterOrders() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredOrders = _allOrders.where((order) {
        final poId = order.poId?.toLowerCase() ?? '';
        final supplier = order.supplierName?.toLowerCase() ?? '';
        return poId.contains(query) || supplier.contains(query);
      }).toList();
    });
  }

  void _onOrderSelected(PurchaseOrder order) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => GoodsReceivingScreen(selectedOrder: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: SharedAppBar(title: 'orders.title'.tr()),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'orders.search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                ? Center(child: Text('orders.no_results'.tr()))
                : RefreshIndicator(
              onRefresh: _loadOrders,
              child: ListView.builder(
                itemCount: _filteredOrders.length,
                itemBuilder: (context, index) {
                  final order = _filteredOrders[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      title: Text("PO: ${order.poId ?? 'N/A'}", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      subtitle: Text(order.supplierName ?? 'orders.no_supplier'.tr()),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () => _onOrderSelected(order),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
