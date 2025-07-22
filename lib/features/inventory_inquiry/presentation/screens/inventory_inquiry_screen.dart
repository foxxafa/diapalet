
import 'dart:async';
import 'dart:io';

import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/utils/gs1_parser.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_inquiry/domain/entities/product_location.dart';
import 'package:diapalet/features/inventory_inquiry/domain/repositories/inventory_inquiry_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class InventoryInquiryScreen extends StatefulWidget {
  const InventoryInquiryScreen({super.key});

  @override
  State<InventoryInquiryScreen> createState() => _InventoryInquiryScreenState();
}

class _InventoryInquiryScreenState extends State<InventoryInquiryScreen> {
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _isLoading = false;
  List<ProductLocation>? _locations;
  String? _lastSearchedBarcode;
  String? _fullScannedBarcode;

  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    _barcodeService = BarcodeIntentService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _intentSub = _barcodeService.stream.listen(_handleBarcode,
        onError: (e) => _showErrorSnackBar(
            'common_labels.barcode_reading_error'.tr(namedArgs: {'error': e.toString()})));
  }

  void _handleBarcode(String code) {
    if (!mounted) return;
    _fullScannedBarcode = code; // Store the full raw code

    final parsedData = GS1Parser.parse(code);
    String displayCode = code;

    // GTIN (01) varsa, onu kullan. Eğer 14 haneliyse ve '0' ile başlıyorsa, kısalt.
    if (parsedData.containsKey('01')) {
      String gtin = parsedData['01']!;
      if (gtin.length == 14 && gtin.startsWith('0')) {
        displayCode = gtin.substring(1); // Baştaki '0'ı at
      } else {
        displayCode = gtin;
      }
    }
    _barcodeController.text = displayCode;
    _search();
  }

  Future<void> _search() async {
    final displayBarcode = _barcodeController.text.trim();
    if (displayBarcode.isEmpty) {
      return;
    }

    // For the actual backend search, use the complete barcode if it came from a scan.
    final barcodeToSearch = _fullScannedBarcode ?? displayBarcode;
    _fullScannedBarcode = null; // Consume the value so it's not used again for manual search

    _barcodeFocusNode.unfocus();
    setState(() {
      _isLoading = true;
      _locations = null;
      _lastSearchedBarcode = displayBarcode; // Use the display barcode for UI messages
    });

    try {
      final repo = context.read<InventoryInquiryRepository>();
      final results = await repo.findProductLocationsByBarcode(barcodeToSearch);
      if (!mounted) return;
      setState(() {
        _locations = results;
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
          'inventory_inquiry.error_searching'.tr(namedArgs: {'error': e.toString()}));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'inventory_inquiry.title'.tr(),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'inventory_inquiry.barcode_label'.tr(),
                border: const OutlineInputBorder(),
                suffixIcon: _barcodeController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _barcodeController.clear();
                          setState(() {
                            _locations = null;
                            _lastSearchedBarcode = null;
                          });
                          _barcodeFocusNode.requestFocus();
                        },
                      )
                    : null,
              ),
              onFieldSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QrScannerScreen(),
                  ),
                );
                if (result != null && result.isNotEmpty) {
                  _handleBarcode(result);
                }
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.qr_code_scanner, size: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_locations == null) {
      return Center(
        child: Text(
          'inventory_inquiry.prompt'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    if (_locations!.isEmpty) {
      return Center(
        child: Text(
          'inventory_inquiry.no_results'
              .tr(namedArgs: {'barcode': _lastSearchedBarcode ?? ''}),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    return ListView.builder(
      itemCount: _locations!.length,
      itemBuilder: (context, index) {
        final location = _locations![index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.productName,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  location.productCode,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 24),
                _buildInfoRow(
                    Icons.inventory,
                    'inventory_inquiry.quantity'.tr(),
                    location.quantity.toString()),
                const SizedBox(height: 8),
                _buildInfoRow(
                    Icons.location_on,
                    'inventory_inquiry.location'.tr(),
                    location.locationName ?? 'N/A'),
                if (location.palletBarcode != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow(
                      Icons.pallet,
                      'inventory_inquiry.pallet_barcode'.tr(),
                      location.palletBarcode!),
                ],
                if (location.expiryDate != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow(
                      Icons.date_range,
                      'inventory_inquiry.expiry_date'.tr(),
                      DateFormat('dd.MM.yyyy').format(location.expiryDate!)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 12),
        Text('$label: ', style: Theme.of(context).textTheme.bodyLarge),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
    ));
  }
} 