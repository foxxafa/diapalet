// lib/features/inventory_transfer/presentation/screens/order_selection_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_view_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/sync/sync_service.dart';

class OrderSelectionScreen extends StatefulWidget {
  const OrderSelectionScreen({super.key});

  @override
  State<OrderSelectionScreen> createState() => _OrderSelectionScreenState();
}

class _OrderSelectionScreenState extends State<OrderSelectionScreen> {
  List<PurchaseOrder> _allOrders = [];
  List<PurchaseOrder> _filteredOrders = [];
  final _searchController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
    if (!mounted) return;
    try {
      final repo = Provider.of<InventoryTransferRepository>(context, listen: false);
      final orders = await repo.getOpenPurchaseOrdersForTransfer();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _filteredOrders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('order_selection.error_loading'
                  .tr(namedArgs: {'error': e.toString()}))),
        );
      }
    }
  }

  void _filterOrders() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredOrders = _allOrders;
      });
      return;
    }
    setState(() {
      _filteredOrders = _allOrders.where((order) {
        return (order.poId?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: "order_selection.title".tr(),
        showBackButton: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "order_selection.search_hint".tr(),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadOrders,
                    child: _filteredOrders.isEmpty
                        ? Center(child: Text("order_selection.no_results".tr()))
                        : ListView.builder(
                            itemCount: _filteredOrders.length,
                            itemBuilder: (context, index) {
                              final order = _filteredOrders[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                child: ListTile(
                                  title: Text(order.poId ??
                                      'common_labels.unknown_order'.tr()),
                                  subtitle: Text(
                                    '${'order_selection.order_date'.tr()}: ${order.date != null ? DateFormat('dd.MM.yyyy').format(order.date!) : 'Bilinmiyor'}\n'
                                    '${'order_selection.supplier'.tr()}: ${order.supplierName ?? 'Bilinmiyor'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    final result = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => ChangeNotifierProvider(
                                          create: (context) => InventoryTransferViewModel(
                                            repository: context.read<InventoryTransferRepository>(),
                                            syncService: context.read<SyncService>(),
                                            barcodeService: context.read<BarcodeIntentService>(),
                                          ),
                                          child: InventoryTransferScreen(selectedOrder: order),
                                        ),
                                      ),
                                    );

                                    if (result == true && mounted) {
                                      _loadOrders();
                                    }
                                  },
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
