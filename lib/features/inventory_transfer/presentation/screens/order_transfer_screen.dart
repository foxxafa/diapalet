// lib/features/inventory_transfer/presentation/screens/order_transfer_screen.dart

import 'dart:async';
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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_intent/receive_intent.dart' as receive_intent;
import 'package:shared_preferences/shared_preferences.dart';

class OrderTransferScreen extends StatefulWidget {
  final PurchaseOrder order;
  const OrderTransferScreen({super.key, required this.order});

  @override
  State<OrderTransferScreen> createState() => _OrderTransferScreenState();
}

class _OrderTransferScreenState extends State<OrderTransferScreen> {
  late InventoryTransferRepository _repo;
  final _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSaving = false;

  List<TransferableContainer> _transferableContainers = [];
  final Map<String, MapEntry<String, int>> _assignedTargets = {};
  int _focusedIndex = 0;

  StreamSubscription? _intentSubscription;

  static const _unitechAction = "android.intent.ACTION_DECODE_DATA";
  static const _unitechDataKey = "barcode_string";

  static const _honeywellAction = "com.honeywell.decode.intent.action.DECODE_EVENT";
  static const _honeywellDataKey = "data";

  static const _zebraAction = "com.diapalet.SCAN";
  static const _zebraDataKey = "com.symbol.datawedge.data_string";

  static const String sourceLocationName = "Mal Kabul Alanı";
  static const int sourceLocationId = 1;

  @override
  void initState() {
    super.initState();
    _repo = context.read<InventoryTransferRepository>();
    _loadContainers();
    _initIntentReceiver();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _intentSubscription?.cancel();
    super.dispose();
  }

  void _initIntentReceiver() {
    _intentSubscription = receive_intent.ReceiveIntent.receivedIntentStream.listen(
          (receive_intent.Intent? intent) {
        if (intent == null || intent.action == null || intent.extra == null) return;

        String? barcode;

        // HATA DÜZELTMESİ: getStringExtra metodu yerine 'extra' Map'i kullanılıyor.
        switch (intent.action) {
          case _unitechAction:
            barcode = intent.extra?[_unitechDataKey];
            break;
          case _honeywellAction:
            barcode = intent.extra?[_honeywellDataKey];
            break;
          case _zebraAction:
            barcode = intent.extra?[_zebraDataKey];
            break;
        }

        if (barcode != null && barcode.isNotEmpty && mounted) {
          if (_transferableContainers.isNotEmpty && _focusedIndex < _transferableContainers.length) {
            final focusedContainer = _transferableContainers[_focusedIndex];
            _processScannedLocation(focusedContainer, barcode);
          }
        }
      },
      onError: (err) {
        debugPrint("Intent alırken hata oluştu: $err");
      },
    );
  }

  // --- BU KISIMDAN SONRASINDA HİÇBİR DEĞİŞİKLİK YOKTUR ---
  // Fonksiyonların tam ve eksiksiz olması için tekrar eklenmiştir.

  void _processScannedLocation(TransferableContainer container, String scannedBarcode) async {
    try {
      var targetLocations = await _repo.getTargetLocations();
      targetLocations.removeWhere((key, value) => value == 1);

      final entry = targetLocations.entries.firstWhereOrNull(
              (entry) => entry.key.toLowerCase() == scannedBarcode.toLowerCase()
      );

      if (entry != null) {
        _assignTargetLocation(container, entry);
      } else {
        _showSnackBar('inventory_transfer.error_invalid_target_location'.tr(namedArgs: {'data': scannedBarcode}), isError: true);
      }
    } catch (e) {
      _showSnackBar('Hedef lokasyonlar yüklenemedi: $e', isError: true);
    }
  }

  Future<void> _loadContainers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final containers = await _repo.getTransferableContainers(widget.order.id);
      if (mounted) {
        setState(() {
          _transferableContainers = containers;
          _assignedTargets.clear();
          _focusedIndex = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("order_selection.error_loading".tr(namedArgs: {'error': e.toString()}), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _focusNextItem() {
    final nextIndex = _transferableContainers.indexWhere(
            (c) => !_assignedTargets.containsKey(c.id), _focusedIndex + 1);

    if (nextIndex != -1) {
      setState(() => _focusedIndex = nextIndex);
    } else {
      final firstUnassigned = _transferableContainers.indexWhere((c) => !_assignedTargets.containsKey(c.id));
      setState(() => _focusedIndex = (firstUnassigned == -1) ? 0 : firstUnassigned);
    }
    _scrollToFocused();
  }

  void _scrollToFocused() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _focusedIndex * 160.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _assignTargetLocation(TransferableContainer container, MapEntry<String, int> location) {
    setState(() {
      _assignedTargets[container.id] = location;
    });
    _showSnackBar(
      'order_transfer.item_added_to_cart'.tr(namedArgs: {
        'containerName': container.displayName,
        'targetLocation': location.key
      }),
    );
    _focusNextItem();
  }

  void _clearTarget(TransferableContainer container) {
    setState(() {
      _assignedTargets.remove(container.id);
      _focusedIndex = _transferableContainers.indexOf(container);
    });
  }

  Future<void> _onSave() async {
    if (_assignedTargets.isEmpty) {
      _showSnackBar("order_transfer.no_cart_items".tr(), isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeId = prefs.getInt('user_id');
      if (employeeId == null) throw Exception("Kullanıcı bilgisi bulunamadı.");

      final List<TransferItemDetail> allItemsToTransfer = [];
      _assignedTargets.forEach((containerId, targetLocation) {
        final container = _transferableContainers.firstWhere((c) => c.id == containerId);
        for (final item in container.items) {
          allItemsToTransfer.add(TransferItemDetail(
            productId: item.product.id,
            productName: item.product.name,
            productCode: item.product.stockCode,
            quantity: item.quantity,
            sourcePalletBarcode: item.sourcePalletBarcode,
            targetLocationId: targetLocation.value,
            targetLocationName: targetLocation.key,
          ));
        }
      });
      final header = TransferOperationHeader(
        employeeId: employeeId,
        transferDate: DateTime.now(),
        operationType: allItemsToTransfer.first.sourcePalletBarcode != null
            ? AssignmentMode.pallet
            : AssignmentMode.box,
        sourceLocationName: sourceLocationName,
        targetLocationName: "Muhtelif",
      );
      await _repo.recordTransferOperation(header, allItemsToTransfer, sourceLocationId, 0);
      if(mounted) {
        _showSnackBar("order_transfer.save_success".tr());
        context.read<SyncService>().performFullSync(force: true);
        await _loadContainers();
      }
    } catch (e) {
      if(mounted) {
        _showSnackBar("order_transfer.save_error".tr(namedArgs: {'error': e.toString()}), isError: true);
      }
    } finally {
      if(mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSave = _assignedTargets.isNotEmpty && !_isSaving;
    return Scaffold(
      appBar: SharedAppBar(title: "order_transfer.title".tr(), showBackButton: true),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: canSave ? _onSave : null,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: Text("order_transfer.save_cart_button".tr(namedArgs: {'count': _assignedTargets.length.toString()})),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            _buildOrderHeader(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transferableContainers.isEmpty
                  ? Center(child: Text("order_transfer.no_items_found".tr(), textAlign: TextAlign.center))
                  : RefreshIndicator(
                onRefresh: _loadContainers,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 80.0, top: 8.0),
                  itemCount: _transferableContainers.length,
                  itemBuilder: (context, index) {
                    final container = _transferableContainers[index];
                    return _ContainerTransferCard(
                      key: ValueKey(container.id),
                      container: container,
                      repo: _repo,
                      isFocused: index == _focusedIndex,
                      assignedTarget: _assignedTargets[container.id],
                      onTargetSelected: (location) => _assignTargetLocation(container, location),
                      onClearTarget: () => _clearTarget(container),
                      onTap: () => setState(() => _focusedIndex = index),
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

  Widget _buildOrderHeader() {
    final theme = Theme.of(context);
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
            Text('goods_receiving_screen.order_info_title'.tr(),
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(widget.order.poId ?? 'N/A',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
            if (widget.order.supplierName != null) ...[
              const SizedBox(height: 2),
              Text(widget.order.supplierName!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            ]
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }
}

class _ContainerTransferCard extends StatefulWidget {
  final TransferableContainer container;
  final InventoryTransferRepository repo;
  final bool isFocused;
  final MapEntry<String, int>? assignedTarget;
  final ValueChanged<MapEntry<String, int>> onTargetSelected;
  final VoidCallback onClearTarget;
  final VoidCallback onTap;

  const _ContainerTransferCard({
    super.key,
    required this.container,
    required this.repo,
    required this.isFocused,
    this.assignedTarget,
    required this.onTargetSelected,
    required this.onClearTarget,
    required this.onTap,
  });

  @override
  State<_ContainerTransferCard> createState() => _ContainerTransferCardState();
}

class _ContainerTransferCardState extends State<_ContainerTransferCard> {
  final _locationController = TextEditingController();
  final _locationFocusNode = FocusNode();
  Map<String, int> _targetLocations = {};
  bool _isLoadingLocations = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _locationFocusNode.addListener(_onFocus);
    if(widget.assignedTarget != null) {
      _locationController.text = widget.assignedTarget!.key;
    }
  }

  @override
  void didUpdateWidget(covariant _ContainerTransferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assignedTarget != oldWidget.assignedTarget) {
      _locationController.text = widget.assignedTarget?.key ?? '';
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _locationFocusNode.removeListener(_onFocus);
    _locationFocusNode.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_locationFocusNode.hasFocus && _locationController.text.isNotEmpty) {
      _locationController.selection = TextSelection(baseOffset: 0, extentOffset: _locationController.text.length);
    }
  }

  Future<void> _loadLocations() async {
    try {
      final locations = await widget.repo.getTargetLocations();
      locations.removeWhere((key, value) => value == 1);
      if(mounted) {
        setState(() {
          _targetLocations = locations;
          _isLoadingLocations = false;
        });
      }
    } catch(e) {
      if (mounted) {
        setState(() {
          _isLoadingLocations = false;
        });
      }
    }
  }

  Future<void> _scanLocation() async {
    final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const QrScannerScreen(title: 'Hedef Rafı Okutun'))
    );
    if(result != null && result.isNotEmpty && mounted) {
      _processLocationInput(result);
    }
  }

  void _processLocationInput(String input) {
    final entry = _targetLocations.entries.firstWhereOrNull(
            (entry) => entry.key.toLowerCase() == input.toLowerCase()
    );

    if (entry != null) {
      _locationController.text = entry.key;
      widget.onTargetSelected(entry);
      FocusScope.of(context).unfocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('inventory_transfer.error_invalid_target_location'.tr(namedArgs: {'data': input})),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isAssigned = widget.assignedTarget != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
        elevation: widget.isFocused ? 4 : 2,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: widget.isFocused ? theme.colorScheme.primary : (isAssigned ? Colors.green : Colors.transparent),
            width: widget.isFocused ? 2.5 : 1.5,
          ),
        ),
        child: Column(
          children: [
            ExpansionTile(
              key: PageStorageKey(widget.container.id),
              initiallyExpanded: widget.isFocused,
              onExpansionChanged: (isExpanded) {
                if (isExpanded) widget.onTap();
              },
              title: Text(widget.container.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: isAssigned
                  ? Icon(Icons.check_circle, color: Colors.green.shade700)
                  : const Icon(Icons.pending_outlined),
              children: widget.container.items.map((item) {
                return ListTile(
                  dense: true,
                  title: Text(item.product.name),
                  subtitle: Text(item.product.stockCode),
                  trailing: Text(
                    "Miktar: ${item.quantity.toStringAsFixed(0)}",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                );
              }).toList(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: isAssigned
                  ? _buildAssignedTargetRow(theme)
                  : _buildTargetAssignmentRow(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedTargetRow(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.location_on, color: Colors.green.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.assignedTarget!.key,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, color: theme.colorScheme.error),
          onPressed: widget.onClearTarget,
          tooltip: 'Hedefi Temizle',
        )
      ],
    );
  }

  Widget _buildTargetAssignmentRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Autocomplete<MapEntry<String, int>>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable.empty();
              }
              if (_isLoadingLocations) return const [];
              return _targetLocations.entries.where((entry) {
                return entry.key.toLowerCase().contains(textEditingValue.text.toLowerCase());
              });
            },
            displayStringForOption: (option) => option.key,
            fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
              return TextFormField(
                controller: _locationController,
                focusNode: _locationFocusNode,
                decoration: InputDecoration(
                  labelText: 'Hedef Raf Ata',
                  isDense: true,
                  hintText: 'Yazın, seçin veya okutun...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: _isLoadingLocations ? const Padding(padding: EdgeInsets.all(10.0), child: CircularProgressIndicator(strokeWidth: 2)) : null,
                ),
                onChanged: (value) {
                  textEditingController.text = value;
                },
                onFieldSubmitted: (value) {
                  _processLocationInput(value);
                  onFieldSubmitted();
                },
              );
            },
            onSelected: (selection) {
              _processLocationInput(selection.key);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _scanLocation,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Icon(Icons.qr_code_scanner),
          ),
        ),
      ],
    );
  }
}