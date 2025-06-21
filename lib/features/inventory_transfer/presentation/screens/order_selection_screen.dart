// lib/features/inventory_transfer/presentation/screens/order_selection_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/order_transfer_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Kullanıcının transfer yapacağı satınalma siparişini seçtiği ekran.
class OrderSelectionScreen extends StatefulWidget {
  const OrderSelectionScreen({super.key});

  @override
  State<OrderSelectionScreen> createState() => _OrderSelectionScreenState();
}

class _OrderSelectionScreenState extends State<OrderSelectionScreen> {
  late Future<List<PurchaseOrder>> _ordersFuture;
  List<PurchaseOrder> _allOrders = [];
  List<PurchaseOrder> _filteredOrders = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final repo = context.read<InventoryTransferRepository>();
    // Sadece transfer edilmeye uygun siparişleri repository'den çeker.
    _ordersFuture = repo.getOpenPurchaseOrdersForTransfer();
    _ordersFuture.then((orders) {
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _filteredOrders = orders;
        });
      }
    });
    _searchController.addListener(_filterOrders);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterOrders() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredOrders = _allOrders.where((order) {
        return (order.poId?.toLowerCase().contains(query) ?? false) ||
            (order.supplierName?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: "Select Order",
        showBackButton: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "Search PO Number or Supplier",
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
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.data == null || snapshot.data!.isEmpty) {
                  return const Center(child: Text("No transferable orders found."));
                }

                return ListView.builder(
                  itemCount: _filteredOrders.length,
                  itemBuilder: (context, index) {
                    final order = _filteredOrders[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ListTile(
                        title: Text(order.poId ?? 'Unknown Order'),
                        subtitle: Text(
                          "${order.supplierName ?? 'Supplier not specified'}\n"
                          // DÜZELTME: Nullable DateTime için kontrol eklendi.
                              "${order.date != null ? DateFormat('dd.MM.yyyy').format(order.date!) : 'No Date'}",
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OrderTransferScreen(order: order),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}