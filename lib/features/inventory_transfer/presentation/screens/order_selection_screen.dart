// lib/features/inventory_transfer/presentation/screens/order_selection_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/order_transfer_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrderSelectionScreen extends StatefulWidget {
  const OrderSelectionScreen({super.key});

  @override
  State<OrderSelectionScreen> createState() => _OrderSelectionScreenState();
}

class _OrderSelectionScreenState extends State<OrderSelectionScreen> {
  late InventoryTransferRepository _repo;
  Future<List<PurchaseOrder>>? _ordersFuture;
  List<PurchaseOrder> _allOrders = [];
  List<PurchaseOrder> _filteredOrders = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repo = context.read<InventoryTransferRepository>();
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
    setState(() {
      _ordersFuture = _fetchAndFilterOrders();
    });
  }

  Future<List<PurchaseOrder>> _fetchAndFilterOrders() async {
    try {
      // # GÜNCELLEME: Bu metod artık sadece durumu 2 (Kısmi Kabul) olanları getirecek.
      final orders = await _repo.getOpenPurchaseOrdersForTransfer();
      List<PurchaseOrder> transferableOrders = [];

      // # GÜNCELLEME: Her sipariş için mal kabulde bekleyen stoğu var mı diye kontrol et.
      // Eğer hiç yerleştirilecek ürünü kalmadıysa listede gösterme.
      for (final order in orders) {
        final containers = await _repo.getTransferableContainers(null, orderId: order.id);
        if (containers.isNotEmpty) {
          transferableOrders.add(order);
        }
      }

      // UI'ı anında güncellemek için setState içinde ata
      if (mounted) {
        setState(() {
          _allOrders = transferableOrders;
          _filteredOrders = transferableOrders;
        });
      }
      return transferableOrders;
    } catch(e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('order_selection.error_loading'.tr(namedArgs: {'error': e.toString()}))),
        );
      }
      return []; // Hata durumunda boş liste dön
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
            child: FutureBuilder<List<PurchaseOrder>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("order_selection.error_loading".tr(namedArgs: {'error': snapshot.error.toString()})));
                }
                if (_filteredOrders.isEmpty) {
                  return Center(child: Text("order_selection.no_results".tr()));
                }

                return RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: ListView.builder(
                    itemCount: _filteredOrders.length,
                    itemBuilder: (context, index) {
                      final order = _filteredOrders[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(order.poId ?? 'common_labels.unknown_order'.tr()),
                          subtitle: Text(
                            "${'orders.no_supplier'.tr()}\n" // Tedarikçi adı kaldırıldı, gerekirse eklenebilir.
                                "${order.date != null ? DateFormat('dd.MM.yyyy').format(order.date!) : 'order_selection.no_date'.tr()}",
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => OrderTransferScreen(order: order),
                              ),
                            );

                            // Yerleştirme ekranından `true` dönerse (yani işlem yapıldıysa) listeyi yenile.
                            if (result == true && mounted) {
                              _loadOrders();
                            }
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
