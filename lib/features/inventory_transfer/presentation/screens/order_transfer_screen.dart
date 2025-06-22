// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart
import 'package:collection/collection.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/inventory_transfer/domain/entities/transferable_container.dart';
import 'package:diapalet/features/inventory_transfer/domain/repositories/inventory_transfer_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() => _OrderTransferScreenState();
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
  late InventoryTransferRepository _repo;

  bool _isLoading = true;
  bool _isSaving = false;

  List<TransferableContainer> _transferableContainers = [];
  final List<TransferItemDetail> _transferCart = [];

  static const String sourceLocationName = "Mal Kabul Alanı";

  @override
  void initState() {
    super.initState();
    _repo = context.read<InventoryTransferRepository>();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final containers = await _repo.getTransferableContainers(widget.order.id);
      if (mounted) {
        setState(() {
          _transferableContainers = containers;
        });
      }
    } catch (e, s) {
      if (mounted) {
        debugPrint("Konteyner yükleme hatası: $e\n$s");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("order_selection.error_loading".tr(namedArgs: {'error': e.toString()}))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _transferContainer(TransferableContainer container) async {
    final selectedLocation = await showDialog<MapEntry<String, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SelectTargetLocationDialog(repo: _repo),
    );

    if (selectedLocation == null) return;

    final List<TransferItemDetail> itemsToAdd = [];
    for (final item in container.items) {
      itemsToAdd.add(TransferItemDetail(
        productId: item.product.id,
        productName: item.product.name,
        productCode: item.product.stockCode,
        quantity: item.quantity,
        sourcePalletBarcode: item.sourcePalletBarcode,
        targetLocationId: selectedLocation.value,
        targetLocationName: selectedLocation.key,
      ));
    }

    if (itemsToAdd.isEmpty) return;

    setState(() => _transferCart.addAll(itemsToAdd));

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('order_transfer.item_added_to_cart'.tr(namedArgs: {
              'containerName': container.displayName,
              'targetLocation': selectedLocation.key
            })),
            backgroundColor: Colors.green)
    );
  }

  Future<void> _saveTransferCart() async {
    if (_transferCart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("order_transfer.no_cart_items".tr()), backgroundColor: Colors.red));
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmationDialog(
        transferItems: _transferCart,
        sourceLocationName: sourceLocationName,
      ),
    );
    if (confirmed == true) _executeSave();
  }

  Future<void> _executeSave() async {
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');
      if (employeeId == null) throw Exception("Kullanıcı bilgisi bulunamadı.");

      final groupedByTarget = groupBy(_transferCart, (item) => item.targetLocationId);

      const sourceLocationId = 1;

      for (var entry in groupedByTarget.entries) {
        final targetLocationId = entry.key;
        final itemsForTarget = entry.value;
        final targetLocationName = itemsForTarget.first.targetLocationName;

        final operationMode = itemsForTarget.first.sourcePalletBarcode != null
            ? AssignmentMode.pallet
            : AssignmentMode.box;

        final header = TransferOperationHeader(
          employeeId: employeeId,
          transferDate: DateTime.now(),
          operationType: operationMode,
          sourceLocationName: sourceLocationName,
          targetLocationName: targetLocationName,
        );

        await _repo.recordTransferOperation(header, itemsForTarget, sourceLocationId, targetLocationId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("order_transfer.save_success".tr()), backgroundColor: Colors.green));

        context.read<SyncService>().performFullSync(force: true);

        setState(() {
          _transferCart.clear();
          _loadContainers();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("order_transfer.save_error".tr(namedArgs: {'error': e.toString()})), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: "order_transfer.title".tr(), showBackButton: true),
      bottomNavigationBar: _transferCart.isNotEmpty ? _buildBottomBar() : null,
      body: Padding(
        // GÜNCELLEME: Tutarlı görünüm için body'e yatay padding eklendi.
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12), // Üst boşluk
            _buildOrderHeader(),
            const SizedBox(height: 12), // Kart ile liste arasına boşluk
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transferableContainers.isEmpty
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "order_transfer.no_items_found".tr(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
                  : RefreshIndicator(
                onRefresh: _loadContainers,
                child: ListView.builder(
                  // GÜNCELLEME: Yatay padding buradan kaldırıldı, body'den alıyor.
                  padding: const EdgeInsets.only(bottom: 80.0, top: 8.0),
                  itemCount: _transferableContainers.length,
                  itemBuilder: (context, index) {
                    final container = _transferableContainers[index];
                    final isAlreadyInCart = _transferCart.any((item) => (item.sourcePalletBarcode ?? "PALETSIZ_${item.productId}") == container.id);
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ExpansionTile(
                        title: Text(container.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: isAlreadyInCart
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : ElevatedButton.icon(
                          icon: const Icon(Icons.move_to_inbox, size: 18),
                          label: Text("order_transfer.add_to_cart_button".tr()),
                          onPressed: () => _transferContainer(container),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              visualDensity: VisualDensity.compact),
                        ),
                        children: container.items.map((item) {
                          return ListTile(
                            dense: true,
                            title: Text(item.product.name),
                            trailing: Text(
                              "Miktar: ${item.quantity.toStringAsFixed(0)}",
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveTransferCart,
        icon: _isSaving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text("order_transfer.save_cart_button".tr(namedArgs: {'count': _transferCart.length.toString()})),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
    );
  }

  Widget _buildOrderHeader() {
    final theme = Theme.of(context);
    // GÜNCELLEME: Kartın stili Mal Kabul ekranındaki ile tam olarak aynı yapıldı.
    // Dışındaki Padding kaldırıldı, çünkü artık body'de genel bir padding var.
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primaryContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // Tutarlılık için aynı çeviri anahtarı kullanıldı.
              'goods_receiving_screen.order_info_title'.tr(),
              style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.order.poId ?? 'N/A',
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer
              ),
            ),
            if(widget.order.supplierName != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.order.supplierName!,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _SelectTargetLocationDialog extends StatefulWidget {
  final InventoryTransferRepository repo;
  const _SelectTargetLocationDialog({required this.repo});
  @override
  State<_SelectTargetLocationDialog> createState() => _SelectTargetLocationDialogState();
}

class _SelectTargetLocationDialogState extends State<_SelectTargetLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  Map<String, int> _targetLocations = {};
  String? _selectedLocationName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.repo.getTargetLocations().then((locations) {
      if (mounted) {
        setState(() {
          _targetLocations = locations;
          _isLoading = false;
        });
      }
    });
  }

  void _onConfirm() {
    if (!(_formKey.currentState?.validate() ?? false) || _selectedLocationName == null) return;
    final selectedId = _targetLocations[_selectedLocationName];
    if (selectedId == null) return;

    final selectedEntry = MapEntry(_selectedLocationName!, selectedId);
    Navigator.of(context).pop(selectedEntry);
  }

  Future<void> _scanLocation() async {
    final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if(result != null && result.isNotEmpty && mounted) {
      final locationName = _targetLocations.keys.firstWhere(
            (k) => k.toLowerCase() == result.toLowerCase(),
        orElse: () => '',
      );

      if (locationName.isNotEmpty) {
        setState(() {
          _selectedLocationName = locationName;
        });
        _onConfirm();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('inventory_transfer.error_invalid_target_location'.tr(namedArgs: {'data': result}))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("order_transfer.select_target_location_title".tr()),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedLocationName,
              hint: Text("order_transfer.select_target_location_hint".tr()),
              items: _targetLocations.keys.map((name) {
                return DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedLocationName = val),
              validator: (val) => val == null ? "order_transfer.validator_target_required".tr() : null,
              isExpanded: true,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: Text("order_transfer.scan_target_shelf".tr()),
              onPressed: _scanLocation,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("dialog.cancel".tr())),
        ElevatedButton(onPressed: _isLoading ? null : _onConfirm, child: Text("dialog.confirm".tr())),
      ],
    );
  }
}


class _ConfirmationDialog extends StatelessWidget {
  final List<TransferItemDetail> transferItems;
  final String sourceLocationName;
  const _ConfirmationDialog({required this.transferItems, required this.sourceLocationName});

  @override
  Widget build(BuildContext context) {
    final sortedItems = List<TransferItemDetail>.from(transferItems)
      ..sort((a, b) => a.targetLocationName.compareTo(b.targetLocationName));
    return AlertDialog(
      title: Text("order_transfer.confirm_dialog_title".tr()),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text("order_transfer.confirm_dialog_body".tr(namedArgs: {'sourceLocation': sourceLocationName})),
            const Divider(height: 20),
            ...sortedItems.map((item) => ListTile(
              title: Text(item.productName),
              subtitle: Text("Hedef: ${item.targetLocationName}"),
              trailing: Text(item.quantity.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text("dialog.cancel".tr())),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text("order_transfer.confirm_button".tr())),
      ],
    );
  }
}
