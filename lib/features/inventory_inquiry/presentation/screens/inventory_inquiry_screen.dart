
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

enum SearchType { barcode, stockCode, productName, pallet }

// SearchType'ı SuggestionSearchType'a dönüştür
SuggestionSearchType _toSuggestionSearchType(SearchType type) {
  switch (type) {
    case SearchType.barcode:
      return SuggestionSearchType.barcode;
    case SearchType.stockCode:
      return SuggestionSearchType.stockCode;
    case SearchType.productName:
      return SuggestionSearchType.productName;
    case SearchType.pallet:
      return SuggestionSearchType.pallet;
  }
}

class _InventoryInquiryScreenState extends State<InventoryInquiryScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isLoading = false;
  List<ProductLocation>? _locations;
  List<Map<String, dynamic>> _productSuggestions = [];
  String? _lastSearchQuery;
  SearchType _searchType = SearchType.pallet; // Varsayılan olarak palet barkodu

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
    _searchByStockCode(); // Dropdown seçimine göre arama yap
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
      List<ProductLocation> results;

      // Seçilen arama tipine göre arama yap
      switch (_searchType) {
        case SearchType.barcode:
          results = await repo.findProductLocationsByBarcode(query);
          break;
        case SearchType.pallet:
          results = await repo.searchProductLocationsByPalletBarcode(query);
          break;
        case SearchType.productName:
          results = await repo.searchProductLocationsByProductName(query);
          break;
        case SearchType.stockCode:
        default:
          results = await repo.searchProductLocationsByStockCode(query);
          break;
      }

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
      // Seçilen arama tipine göre suggestions getir
      final suggestionType = _toSuggestionSearchType(_searchType);
      final results = await repo.getProductSuggestions(query, suggestionType);
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

  void _selectProduct(Map<String, dynamic> product) {
    if (_searchType == SearchType.pallet) {
      _searchController.text = product['pallet_barcode'] ?? '';
      setState(() {
        _productSuggestions = [];
      });
      _searchByStockCode(); // dispatcher
    } else { // productName or stockCode
      _searchController.text = product['StokKodu'] ?? '';
      setState(() {
        _productSuggestions = [];
        _searchType = SearchType.stockCode;
      });
      _searchByStockCode();
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
          // Suggestions göster
          if (_productSuggestions.isNotEmpty)
            Flexible(
              child: _buildProductSuggestions(),
            ),
          // Suggestion gösteriliyorsa results'ı hiç render etme
          if (_productSuggestions.isEmpty)
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Arama tipi seçici - Dropdown
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.manage_search, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'inventory_inquiry.search_by'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                DropdownButtonHideUnderline(
                  child: DropdownButton<SearchType>(
                    value: _searchType,
                    isDense: true,
                    alignment: AlignmentDirectional.centerEnd,
                    selectedItemBuilder: (BuildContext context) {
                      return SearchType.values.map<Widget>((SearchType type) {
                        IconData icon;
                        String label;

                        switch (type) {
                          case SearchType.barcode:
                            icon = Icons.qr_code_scanner;
                            label = 'inventory_inquiry.barcode'.tr();
                            break;
                          case SearchType.stockCode:
                            icon = Icons.inventory_2;
                            label = 'inventory_inquiry.stock_code'.tr();
                            break;
                          case SearchType.productName:
                            icon = Icons.label;
                            label = 'inventory_inquiry.product_name'.tr();
                            break;
                          case SearchType.pallet:
                            icon = Icons.pallet;
                            label = 'inventory_inquiry.pallet_barcode'.tr();
                            break;
                        }

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(icon, size: 18),
                            const SizedBox(width: 8),
                            Text(label, style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        );
                      }).toList();
                    },
                    items: [
                      DropdownMenuItem(
                        value: SearchType.barcode,
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code_scanner, size: 18),
                            const SizedBox(width: 8),
                            Text('inventory_inquiry.barcode'.tr()),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: SearchType.stockCode,
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2, size: 18),
                            const SizedBox(width: 8),
                            Text('inventory_inquiry.stock_code'.tr()),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: SearchType.productName,
                        child: Row(
                          children: [
                            const Icon(Icons.label, size: 18),
                            const SizedBox(width: 8),
                            Text('inventory_inquiry.product_name'.tr()),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: SearchType.pallet,
                        child: Row(
                          children: [
                            const Icon(Icons.pallet, size: 18),
                            const SizedBox(width: 8),
                            Text('inventory_inquiry.pallet_barcode'.tr()),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (SearchType? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _searchType = newValue;
                          _locations = null; // Sonuçları temizle
                          _productSuggestions = []; // Önerileri temizle
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          QrTextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            labelText: _getSearchLabel(),
            onChanged: (value) {
              if (value.trim().isEmpty) {
                setState(() {
                  _productSuggestions = [];
                });
              } else {
                // Stok kodu, ürün adı ve palet barcode aramasında suggestions göster
                if (_searchType == SearchType.stockCode ||
                    _searchType == SearchType.productName ||
                    _searchType == SearchType.pallet) {
                  _searchProductSuggestions(value);
                }
              }
            },
            onFieldSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                _searchByStockCode();
              }
            },
            onQrScanned: (scannedData) => _handleBarcode(scannedData),
          ),
        ],
      ),
    );
  }

  String _getSearchLabel() {
    switch (_searchType) {
      case SearchType.barcode:
        return 'inventory_inquiry.enter_barcode'.tr();
      case SearchType.pallet:
        return 'inventory_inquiry.enter_pallet'.tr();
      case SearchType.productName:
        return 'inventory_inquiry.enter_product_name'.tr();
      case SearchType.stockCode:
      default:
        return 'inventory_inquiry.enter_stock_code'.tr();
    }
  }

  Widget _buildProductSuggestions() {
    final suggestions = _productSuggestions.take(InventoryInquiryConstants.maxDisplayedSuggestions).toList();

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: InventoryInquiryConstants.searchBarPadding,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(InventoryInquiryConstants.borderRadius),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final product = suggestions[index];
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
                if (product['barcode'] != null && product['barcode'].toString().isNotEmpty)
                  Text(
                    '${'inventory_inquiry.barcode'.tr()}: ${product['barcode']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                if (product['pallet_barcode'] != null && product['pallet_barcode'].toString().isNotEmpty)
                  Text(
                    '${'inventory_inquiry.pallet_barcode'.tr()}: ${product['pallet_barcode']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange,
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
            onTap: () => _selectProduct(product),
          );
        },
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Suggestion gösteriliyorsa prompt mesajını gösterme
    if (_locations == null) {
      // Suggestion yoksa prompt göster
      if (_productSuggestions.isEmpty) {
        return Center(
          child: Text(
            'inventory_inquiry.prompt'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
      }
      // Suggestion varsa hiçbir şey gösterme
      return const SizedBox();
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
                      .bodyLarge
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
                    location.locationId == null ? '000' : (location.locationName ?? 'N/A')),
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
                // Mal kabul bilgisi - Sipariş veya İrsaliye
                if (location.orderNumber != null) ...[
                  const SizedBox(height: InventoryInquiryConstants.infoRowSpacing),
                  _buildInfoRow(
                      Icons.receipt_long,
                      'Order Number',
                      location.orderNumber!,
                      valueColor: Colors.blue),
                ] else if (location.deliveryNoteNumber != null) ...[
                  const SizedBox(height: InventoryInquiryConstants.infoRowSpacing),
                  _buildInfoRow(
                      Icons.local_shipping,
                      'Delivery Note',
                      location.deliveryNoteNumber!,
                      valueColor: Colors.green),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? valueColor}) {
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
                ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
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