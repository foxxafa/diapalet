// lib/features/inventory_transfer/presentation/screens/delivery_note_selection_screen.dart
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:diapalet/features/inventory_transfer/presentation/screens/inventory_transfer_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DeliveryNoteSelectionScreen extends StatefulWidget {
  const DeliveryNoteSelectionScreen({super.key});

  @override
  State<DeliveryNoteSelectionScreen> createState() => _DeliveryNoteSelectionScreenState();
}

class _DeliveryNoteSelectionScreenState extends State<DeliveryNoteSelectionScreen> {
  late InventoryTransferRepository _repo;
  Future<List<String>>? _deliveryNotesFuture;
  List<String> _allDeliveryNotes = [];
  List<String> _filteredDeliveryNotes = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repo = context.read<InventoryTransferRepository>();
    _loadDeliveryNotes();
    _searchController.addListener(_filterDeliveryNotes);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterDeliveryNotes);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDeliveryNotes() async {
    setState(() {
      _deliveryNotesFuture = _fetchDeliveryNotes();
    });
  }

  Future<List<String>> _fetchDeliveryNotes() async {
    try {
      final notes = await _repo.getFreeReceiptDeliveryNotes();
      if (mounted) {
        setState(() {
          _allDeliveryNotes = notes;
          _filteredDeliveryNotes = notes;
        });
      }
      return notes;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('delivery_note_selection.error_loading'.tr(namedArgs: {'error': e.toString()}))),
        );
      }
      return [];
    }
  }

  void _filterDeliveryNotes() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredDeliveryNotes = _allDeliveryNotes;
      });
      return;
    }
    setState(() {
      _filteredDeliveryNotes = _allDeliveryNotes.where((note) {
        return note.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: "delivery_note_selection.title".tr(),
        showBackButton: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "delivery_note_selection.search_hint".tr(),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _deliveryNotesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("delivery_note_selection.error_loading".tr(namedArgs: {'error': snapshot.error.toString()})));
                }
                if (_filteredDeliveryNotes.isEmpty) {
                  return Center(child: Text("delivery_note_selection.no_results".tr()));
                }

                return RefreshIndicator(
                  onRefresh: _loadDeliveryNotes,
                  child: ListView.builder(
                    itemCount: _filteredDeliveryNotes.length,
                    itemBuilder: (context, index) {
                      final deliveryNote = _filteredDeliveryNotes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          title: Text(deliveryNote),
                          subtitle: Text("delivery_note_selection.tap_to_continue".tr()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => InventoryTransferScreen(
                                  isFreePutAway: true,
                                  selectedDeliveryNote: deliveryNote,
                                ),
                              ),
                            );

                            // Transfer ekranından `true` dönerse (yani işlem yapıldıysa) listeyi yenile.
                            if (result == true && mounted) {
                              _loadDeliveryNotes();
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
