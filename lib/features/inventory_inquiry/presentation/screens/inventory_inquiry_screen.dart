
import 'dart:async';
import 'dart:io';

import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/utils/gs1_parser.dart';
import 'package:diapalet/core/widgets/qr_text_field.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/inventory_inquiry/constants/inventory_inquiry_constants.dart';
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
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isLoading = false;
  List<ProductLocation>? _locations;
  List<Map<String, dynamic>> _productSuggestions = [];
  String? _lastSearchQuery;

  late final BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    _barcodeService = BarcodeIntentService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
      _initBarcode();
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    final parsedData = GS1Parser.parse(code);
    String displayCode = code;

    // GTIN (01) varsa, onu kullan. Eğer 14 haneliyse ve '0' ile başlıyorsa, kısalt.
    if (parsedData.containsKey(InventoryInquiryConstants.gs1GtinKey)) {
      String gtin = parsedData[InventoryInquiryConstants.gs1GtinKey]!;
      if (gtin.length == InventoryInquiryConstants.gtin14Length && gtin.startsWith(InventoryInquiryConstants.gtinLeadingZero)) {
        displayCode = gtin.substring(1); // Baştaki '0'ı at
      } else {
        displayCode = gtin;
      }
    }
    _searchController.text = displayCode;
    _searchByBarcode();
  }

  Future<void> _searchByBarcode() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    _searchFocusNode.unfocus();
    setState(() {
      _isLoading = true;
      _locations = null;
      _productSuggestions = [];
      _lastSearchQuery = query;
    });

    try {
      final repo = context.read<InventoryInquiryRepository>();
      final results = await repo.findProductLocationsByBarcode(query);
      if (!mounted) return;
      setState(() {
        _locations = results;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _locations = [];
          _isLoading = false;
        });
        _showErrorSnackBar('inventory_inquiry.error_searching'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  Future<void> _searchByStockCode() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    _searchFocusNode.unfocus();
    setState(() {
      _isLoading = true;
      _locations = null;
      _productSuggestions = [];
      _lastSearchQuery = query;
    });

    try {
      final repo = context.read<InventoryInquiryRepository>();
      final results = await repo.searchProductLocationsByStockCode(query);
      if (!mounted) return;
      setState(() {
        _locations = results;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _locations = [];
          _isLoading = false;
        });
        _showErrorSnackBar('inventory_inquiry.error_searching'.tr(namedArgs: {'error': e.toString()}));
      }
    }
  }

  Future<void> _searchProductSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _productSuggestions = [];
      });
      return;
    }

    try {
      final repo = context.read<InventoryInquiryRepository>();
      final results = await repo.getProductSuggestions(query);
      if (!mounted) return;
      setState(() {
        _productSuggestions = results;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _productSuggestions = [];
        });
      }
    }
  }

  void _selectProduct(String stockCode) {
    _searchController.text = stockCode;
    setState(() {
      _productSuggestions = [];
    });
    _searchByStockCode();
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
      padding: const EdgeInsets.all(InventoryInquiryConstants.searchBarPadding),
      child: Column(
        children: [
          QrTextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            labelText: 'inventory_inquiry.search_label'.tr(),
            onChanged: (value) {
              if (value.trim().isEmpty) {
                setState(() {
                  _productSuggestions = [];
                });
              } else {
                _searchProductSuggestions(value);
              }
            },
            onFieldSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                if (_productSuggestions.isNotEmpty) {
                  _selectProduct(_productSuggestions.first['StokKodu'] ?? '');
                } else {
                  // Enter'a basınca hem barkod hem StokKodu ile arama yap
                  _searchByStockCode();
                }
              }
            },
            onQrScanned: (scannedData) => _handleBarcode(scannedData),
          ),
          if (_productSuggestions.isNotEmpty) _buildProductSuggestions(),
        ],
      ),
    );
  }

  Widget _buildProductSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: InventoryInquiryConstants.suggestionMarginTop),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(InventoryInquiryConstants.borderRadius),
      ),
      child: Column(
        children: _productSuggestions.take(InventoryInquiryConstants.maxDisplayedSuggestions).map((product) {
          return ListTile(
            dense: true,
            title: Text(
              product['UrunAdi'] ?? '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'inventory_inquiry.stock_code'.tr()}: ${product['StokKodu'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${'inventory_inquiry.barcode'.tr()}: ${product['barcode'] ?? 'N/A'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                Text(
                  '${'inventory_inquiry.unit'.tr()}: ${product['unit_name'] ?? 'N/A'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            onTap: () => _selectProduct(product['StokKodu'] ?? ''),
          );
        }).toList(),
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
              .tr(namedArgs: {'query': _lastSearchQuery ?? ''}),
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
          margin: const EdgeInsets.symmetric(horizontal: InventoryInquiryConstants.cardMarginHorizontal, vertical: InventoryInquiryConstants.cardMarginVertical),
          child: Padding(
            padding: const EdgeInsets.all(InventoryInquiryConstants.cardPadding),
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
                  '${'inventory_inquiry.stock_code'.tr()}: ${location.productCode}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: InventoryInquiryConstants.dividerHeight),
                _buildInfoRow(
                    Icons.inventory,
                    'inventory_inquiry.quantity'.tr(),
                    '${location.quantity.toInt()} ${location.unitName ?? 'N/A'}'),
                const SizedBox(height: InventoryInquiryConstants.infoRowSpacing),
                _buildInfoRow(
                    Icons.location_on,
                    'inventory_inquiry.location'.tr(),
                    location.locationName ?? 'N/A'),
                if (location.palletBarcode != null) ...[
                  const SizedBox(height: InventoryInquiryConstants.infoRowSpacing),
                  _buildInfoRow(
                      Icons.pallet,
                      'inventory_inquiry.pallet_barcode'.tr(),
                      location.palletBarcode!),
                ],
                if (location.expiryDate != null) ...[
                  const SizedBox(height: InventoryInquiryConstants.infoRowSpacing),
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
        Icon(icon, size: InventoryInquiryConstants.iconSize, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: InventoryInquiryConstants.iconTextSpacing),
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