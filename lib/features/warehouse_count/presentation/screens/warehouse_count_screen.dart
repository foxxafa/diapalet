// lib/features/warehouse_count/presentation/screens/warehouse_count_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:diapalet/core/services/barcode_intent_service.dart';
import 'package:diapalet/core/services/sound_service.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/core/widgets/qr_text_field.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/features/warehouse_count/constants/warehouse_count_constants.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_sheet.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_item.dart';
import 'package:diapalet/features/warehouse_count/domain/entities/count_mode.dart';
import 'package:diapalet/features/warehouse_count/domain/repositories/warehouse_count_repository.dart';
import 'package:diapalet/features/warehouse_count/presentation/widgets/counted_items_review_table.dart';
import 'package:diapalet/features/warehouse_count/presentation/screens/warehouse_count_review_screen.dart';
import 'package:diapalet/features/goods_receiving/utils/date_validation_utils.dart';
import 'package:diapalet/core/local/database_helper.dart';
import 'package:provider/provider.dart';
import 'dart:async';

class WarehouseCountScreen extends StatefulWidget {
  final WarehouseCountRepository repository;
  final CountSheet countSheet;

  const WarehouseCountScreen({
    super.key,
    required this.repository,
    required this.countSheet,
  });

  @override
  State<WarehouseCountScreen> createState() => _WarehouseCountScreenState();
}

class _WarehouseCountScreenState extends State<WarehouseCountScreen> {
  static const double _gap = 12;

  CountMode _selectedMode = CountMode.product;
  final TextEditingController _palletBarcodeController = TextEditingController();
  final TextEditingController _productSearchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _shelfController = TextEditingController();
  final TextEditingController _expiryDateController = TextEditingController();

  final FocusNode _palletBarcodeFocusNode = FocusNode();
  final FocusNode _productSearchFocusNode = FocusNode();
  final FocusNode _quantityFocusNode = FocusNode();
  final FocusNode _shelfFocusNode = FocusNode();
  final FocusNode _expiryDateFocusNode = FocusNode();

  List<CountItem> _countedItems = [];
  bool _isLoading = false;
  bool _isAdding = false; // 🔥 YENİ: Ekleme işlemi devam ediyor mu?

  // Product selection state
  String? _selectedBarcode;
  String? _selectedStokKodu;
  String? _selectedProductName; // Ürün adını sakla
  List<Map<String, dynamic>> _availableUnits = [];
  String? _selectedBirimKey;
  List<Map<String, dynamic>> _productSearchResults = [];

  // Validation error states
  bool _isShelfValid = false;

  // 🔥 YENİ: Barkod okutma flag'i
  bool _isProcessingBarcodeScanner = false;

  late BarcodeIntentService _barcodeService;
  StreamSubscription<String>? _barcodeSub;

  // 🔥 Debounce timer for search
  Timer? _searchDebounce;

  // 🔥 YENİ: Hızlı yazım algılama (el terminali tespiti)
  String _previousValue = ''; // Önceki değer
  DateTime? _lastChangeTime; // Son değişiklik zamanı
  DateTime? _inputStartTime; // İlk karakter ne zaman geldi (ortalama hız için)
  static const _scannerInputThreshold = Duration(milliseconds: 100); // 100ms'den hızlı = el terminali
  static const _avgCharInputThreshold = 20; // Ortalama karakter başına max 20ms = scanner
  static const _minBarcodeLength = 8; // Minimum barkod uzunluğu

  @override
  void initState() {
    super.initState();
    _barcodeService = Provider.of<BarcodeIntentService>(context, listen: false);
    _initBarcodeListener();
    _loadExistingItems();

    // 🔥 YENİ: Sayfa açıldığında doğru alana focus ver
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Varsayılan mod product, bu yüzden product search'e focus ver
        _productSearchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _searchDebounce?.cancel();
    _palletBarcodeController.dispose();
    _productSearchController.dispose();
    _quantityController.dispose();
    _shelfController.dispose();
    _expiryDateController.dispose();
    _palletBarcodeFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _quantityFocusNode.dispose();
    _shelfFocusNode.dispose();
    _expiryDateFocusNode.dispose();
    super.dispose();
  }

  void _initBarcodeListener() {
    _barcodeSub = _barcodeService.stream.listen((barcode) {
      if (mounted) {
        _handleBarcodeScanned(barcode);
      }
    });
  }

  Future<void> _loadExistingItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await widget.repository.getCountItemsBySheetId(widget.countSheet.id!);
      if (mounted) {
        setState(() => _countedItems = items);
      }
    } catch (e) {
      debugPrint('Error loading count items: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleBarcodeScanned(String barcode) async {
    debugPrint('🔴 _handleBarcodeScanned called with: $barcode');

    // Flag'i set et
    _isProcessingBarcodeScanner = true;

    // Text controller'ı güncelle (bu onChanged'i tetikleyebilir)
    _productSearchController.text = barcode;
    _selectedBarcode = barcode;

    // Arama yap
    await _searchProduct(barcode, isFromBarcodeScanner: true);

    // İşlem bittiğinde flag'i sıfırla
    _isProcessingBarcodeScanner = false;
  }

  Future<void> _searchProduct(String query, {bool isFromBarcodeScanner = false}) async {
    if (query.trim().isEmpty) {
      setState(() {
        _productSearchResults = [];
      });
      return;
    }

    try {
      // HEM PRODUCT HEM PALLET MODUNDA ürün araması yap
      final searchResults = await widget.repository.searchProductsPartial(query.trim());

      debugPrint('🔍 _searchProduct çalıştı:');
      debugPrint('   - Query: $query');
      debugPrint('   - isFromBarcodeScanner: $isFromBarcodeScanner');
      debugPrint('   - searchResults.length: ${searchResults.length}');

      if (mounted) {
        // 🔥 YENİ: Benzersiz ürün sayısını kontrol et
        final uniqueProducts = <String>{};
        for (var result in searchResults) {
          final stokKodu = result['StokKodu'] as String?;
          debugPrint('   - Sonuç: StokKodu=$stokKodu, UrunAdi=${result['UrunAdi']}');
          if (stokKodu != null) {
            uniqueProducts.add(stokKodu);
          }
        }

        debugPrint('   - Benzersiz ürün sayısı: ${uniqueProducts.length}');

        // 🔊 SES BİLDİRİMİ: El terminali ile arama yapıldıysa ses çal
        if (isFromBarcodeScanner) {
          final soundService = Provider.of<SoundService>(context, listen: false);
          if (searchResults.isNotEmpty) {
            // Ürün bulundu - başarı sesi
            soundService.playSuccessSound();
            debugPrint('🔊 Başarılı arama - boopk.mp3 çalınıyor');
          } else {
            // Ürün bulunamadı - hata sesi + snackbar
            soundService.playErrorSound();
            debugPrint('🔊 Başarısız arama - wrongk.mp3 çalınıyor');

            // Snackbar ile kullanıcıya bildir
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('No product found'),
                duration: const Duration(seconds: 2),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }

        // 🔥 TEK KAYIT KONTROLÜ: Sadece searchResults.length == 1 ise otomatik seç
        // (Aynı üründen farklı birimler varsa dropdown göster)
        if (searchResults.length == 1) {
          // TEK KAYIT VAR! Dropdown göstermeden otomatik seç
          debugPrint('✅ TEK KAYIT BULUNDU! Otomatik seçiliyor...');
          debugPrint('   - Seçilen ürün: ${searchResults.first}');
          debugPrint('   - isFromBarcodeScanner: $isFromBarcodeScanner');
          setState(() {
            _productSearchResults = []; // Dropdown'ı GÖSTERME
          });
          // 🔥 Otomatik seçim bayrağını ekle
          _selectProduct(searchResults.first, isFromBarcodeScanner: isFromBarcodeScanner, isAutoSelection: true);
          return; // Erken çık, dropdown gösterilmeyecek
        } else if (searchResults.length > 1) {
          debugPrint('⚠️ ${searchResults.length} kayıt bulundu (${uniqueProducts.length} benzersiz ürün), dropdown gösteriliyor...');
        } else {
          debugPrint('⚠️ Boş sonuç');
        }

        // MANUEL ARAMA veya ÇOKLU SONUÇ: Dropdown'ı göster
        setState(() {
          _productSearchResults = searchResults;
        });
      }
    } catch (e) {
      debugPrint('❌ Error searching product: $e');
      if (mounted) {
        setState(() {
          _productSearchResults = [];
        });
        _showError('warehouse_count.error.search_failed'.tr());
      }
    }
  }

  void _selectProduct(Map<String, dynamic> productInfo, {bool isFromBarcodeScanner = false, bool isAutoSelection = false}) async {
    final stockCode = productInfo['StokKodu'] as String? ?? '';
    final barcode = productInfo['barkod'] as String?;
    final productName = productInfo['UrunAdi'] as String? ?? '';

    debugPrint('🔵 _selectProduct called: isAutoSelection=$isAutoSelection');

    setState(() {
      _selectedBarcode = barcode;
      _selectedStokKodu = stockCode;
      _selectedProductName = productName; // Ürün adını sakla
      _productSearchResults = [];

      // Text field'a BARKOD + STOK KODU yaz (goods_receiving gibi)
      // Eğer barkod varsa: "BARKOD (STOKKODU)", yoksa sadece "STOKKODU"
      if (barcode != null && barcode.isNotEmpty) {
        _productSearchController.text = '$barcode ($stockCode)';
      } else {
        _productSearchController.text = stockCode;
      }
    });

    // Ürünün TÜM birimlerini veritabanından getir (Goods Receiving gibi)
    if (stockCode.isNotEmpty) {
      try {
        final dbHelper = DatabaseHelper.instance;
        final units = await dbHelper.getAllUnitsForProduct(stockCode);

        if (mounted) {
          bool boxUnitSelected = false; // BOX birim seçildi mi?

          setState(() {
            _availableUnits = units;

            // 🔥 BOX OTOMATIK SEÇME: SADECE otomatik seçimde (tek ürün) çalışsın
            if (isAutoSelection) {
              debugPrint('✅ Otomatik seçim aktif - BOX birimi aranıyor...');
              // Önce BOX birimi var mı kontrol et
              final boxUnit = units.firstWhere(
                (u) => (u['birimadi'] as String?)?.toUpperCase() == 'BOX',
                orElse: () => <String, dynamic>{},
              );

              if (boxUnit.isNotEmpty) {
                // BOX birimi bulundu, otomatik seç
                _selectedBirimKey = boxUnit['birim_key'] as String?;
                boxUnitSelected = true;
                debugPrint('📦 BOX birimi bulundu ve otomatik seçildi: $_selectedBirimKey');
              } else {
                // BOX yok, arama sonucundan gelen birim_key'i kullan
                final searchBirimKey = productInfo['birim_key'] as String?;

                if (searchBirimKey != null && units.any((u) => u['birim_key'] == searchBirimKey)) {
                  _selectedBirimKey = searchBirimKey;
                  debugPrint('✅ Auto-selected unit from search: $searchBirimKey');
                } else {
                  _selectedBirimKey = null;
                  debugPrint('⚠️ No unit auto-selected, user must choose manually');
                }
              }
            } else {
              // MANUEL SEÇİM: Dropdown'dan seçilen ürün - kullanıcının seçtiği birim gelsin
              debugPrint('🟡 Manuel seçim - Kullanıcının seçtiği birim kullanılacak');
              final searchBirimKey = productInfo['birim_key'] as String?;

              if (searchBirimKey != null && units.any((u) => u['birim_key'] == searchBirimKey)) {
                _selectedBirimKey = searchBirimKey;
                debugPrint('✅ Manuel seçim: kullanıcının seçtiği birim: $searchBirimKey');
              } else {
                _selectedBirimKey = null;
                debugPrint('⚠️ No unit found from search result');
              }
            }

            debugPrint('🔄 Updated _availableUnits: ${units.length} units');
            for (var unit in units) {
              debugPrint('   - ${unit['birimadi']} (key: ${unit['birim_key']})');
            }
          });

          // 🔥 YENİ: Birim seçildiyse text field'ı güncelle VE BOX bildirimi göster
          if (_selectedBirimKey != null && isAutoSelection) {
            _updateProductSearchText();

            // BOX birimi seçildi ise kısa snackbar göster
            if (boxUnitSelected && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('BOX unit auto-selected'),
                  duration: const Duration(milliseconds: 800),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            }
          }

          // Birimler yüklendikten SONRA expiry date'e focus yap (SADECE otomatik seçimde)
          if (isAutoSelection) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                debugPrint('🎯 Focus yapılıyor: Expiry Date');
                _expiryDateFocusNode.requestFocus();
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading units: $e');
        if (mounted) {
          setState(() {
            _availableUnits = [];
            _selectedBirimKey = null;
          });
        }
      }
    }
  }

  Future<void> _openQrScannerForProduct() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const QrScannerScreen(),
      ),
    );

    if (barcode != null && mounted) {
      _handleBarcodeScanned(barcode);
    }
  }

  Future<void> _validateShelf(String shelfCode) async {
    if (shelfCode.trim().isEmpty) {
      setState(() {
        _isShelfValid = false;
      });
      return;
    }

    try {
      // Convert to uppercase for validation (case-insensitive)
      final upperShelfCode = shelfCode.trim().toUpperCase();
      final isValid = await widget.repository.validateShelfCode(upperShelfCode);

      if (mounted) {
        setState(() {
          _isShelfValid = isValid;
        });

        if (!isValid) {
          _showError('warehouse_count.error.invalid_shelf'.tr());
        } else {
          // Update controller with uppercase value
          _shelfController.text = upperShelfCode;

          // Move to Add button - focus stays on shelf but user can press Add
          // No auto-focus to quantity since shelf validation happens on enter
        }
      }
    } catch (e) {
      debugPrint('Error validating shelf: $e');
      if (mounted) {
        setState(() {
          _isShelfValid = false;
        });
        _showError('warehouse_count.error.validation_failed'.tr());
      }
    }
  }

  Future<void> _addCountItem() async {
    // 🔥 YENİ: Eğer zaten ekleme işlemi devam ediyorsa, tekrar çalıştırma
    if (_isAdding) {
      debugPrint('⚠️ Ekleme işlemi zaten devam ediyor, çıkılıyor...');
      return;
    }

    setState(() => _isAdding = true);

    // Pallet modunda pallet barkodu zorunlu
    if (_selectedMode.isPallet) {
      final palletBarcode = _palletBarcodeController.text.trim();
      if (palletBarcode.isEmpty) {
        setState(() => _isAdding = false);
        _showError('warehouse_count.error.scan_pallet'.tr());
        return;
      }
    }

    // Validate inputs - Ürün seçimi zorunlu (barkod olmasa bile StokKodu olmalı)
    if (_selectedStokKodu == null || _selectedStokKodu!.isEmpty) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.scan_barcode'.tr());
      return;
    }

    final shelfCode = _shelfController.text.trim();
    if (shelfCode.isEmpty) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.enter_shelf'.tr());
      return;
    }

    // Raf kodunu doğrula
    final isValidShelf = await widget.repository.validateShelfCode(shelfCode);
    if (!isValidShelf) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.invalid_shelf'.tr());
      return;
    }

    final quantityText = _quantityController.text.trim();
    if (quantityText.isEmpty) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.enter_quantity'.tr());
      return;
    }

    final quantity = double.tryParse(quantityText);
    if (quantity == null || quantity < WarehouseCountConstants.minQuantity) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.invalid_quantity'.tr());
      return;
    }

    if (quantity > WarehouseCountConstants.maxQuantity) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.quantity_too_large'.tr());
      return;
    }

    // Expiry date required (hem product hem pallet modunda ürün ekleniyor)
    final expiryDate = _expiryDateController.text.trim();
    if (expiryDate.isEmpty) {
      setState(() => _isAdding = false);
      _showError('warehouse_count.error.expiry_required'.tr());
      return;
    }

    // Tarih formatını ve geçerliliğini kontrol et
    if (!DateValidationUtils.isValidExpiryDate(expiryDate)) {
      setState(() => _isAdding = false);
      final errorMessage = DateValidationUtils.getDateValidationError(expiryDate);
      _showError(errorMessage);
      return;
    }

    // Unit selection required (hem product hem pallet modunda ürün ekleniyor)
    if (_selectedBirimKey == null || _selectedBirimKey!.isEmpty) {
      setState(() => _isAdding = false);
      _showError('goods_receiving_screen.validator_unit_required'.tr());
      return;
    }

    try {
      final now = DateTime.now().toUtc();
      final countItem = CountItem(
        operationUniqueId: widget.countSheet.operationUniqueId,
        itemUuid: const Uuid().v4(),
        // Pallet modunda: palletBarcodeController'dan al
        // Product modunda: null
        palletBarcode: _selectedMode.isPallet ? _palletBarcodeController.text.trim() : null,
        quantityCounted: quantity,
        // Product barkodu her zaman var (hem product hem pallet modunda ürün ekleniyor)
        barcode: _selectedBarcode,
        shelfCode: shelfCode,
        // Birim key her zaman var (ürün ekleniyorsa birim gerekli)
        birimKey: _selectedBirimKey,
        // birimAdi will be loaded via JOIN when reading from DB
        // Expiry date her zaman var (ürün ekleniyorsa gerekli)
        expiryDate: _expiryDateController.text.trim().isNotEmpty ? _expiryDateController.text.trim() : null,
        stokKodu: _selectedStokKodu,
        createdAt: now,
        updatedAt: now,
      );

      await widget.repository.addCountItem(countItem);

      // Reload items from database with JOIN to get birimAdi
      final reloadedItems = await widget.repository.getCountItemsBySheetId(widget.countSheet.id!);

      if (mounted) {
        setState(() {
          _countedItems = reloadedItems;
          _isAdding = false; // İşlem tamamlandı
        });

        // İnputları temizle (setState dışında, çünkü içinde kendi setState'i var)
        _clearInputs();

        _showSuccess('warehouse_count.success.item_added'.tr());
      }
    } catch (e) {
      debugPrint('Error adding count item: $e');
      if (mounted) {
        setState(() => _isAdding = false); // Hata durumunda da sıfırla
        _showError('warehouse_count.error.add_item'.tr());
      }
    }
  }

  void _updateProductSearchText() async {
    // Text field'ı seçili birimin barkodu ile güncelle
    if (_selectedStokKodu != null && _selectedBirimKey != null) {
      try {
        // Seçili birimin barkodunu veritabanından çek
        final dbHelper = DatabaseHelper.instance;
        final db = await dbHelper.database;

        // barkodlar._key_scf_stokkart_birimleri = birimler._key (birim_key)
        final result = await db.rawQuery('''
          SELECT barkod
          FROM barkodlar
          WHERE _key_scf_stokkart_birimleri = ?
          LIMIT 1
        ''', [_selectedBirimKey]);

        if (result.isNotEmpty && mounted) {
          final unitBarcode = result.first['barkod'] as String?;

          setState(() {
            _selectedBarcode = unitBarcode;

            // Format: "BARKOD (STOKKODU)"
            if (unitBarcode != null && unitBarcode.isNotEmpty) {
              _productSearchController.text = '$unitBarcode ($_selectedStokKodu)';
            } else {
              _productSearchController.text = _selectedStokKodu!;
            }

            debugPrint('🔄 Birim değişti - Yeni barkod: $unitBarcode');
            debugPrint('🔄 Text field güncellendi: ${_productSearchController.text}');
          });
        }
      } catch (e) {
        debugPrint('❌ Birim barkodu alınırken hata: $e');
      }
    }
  }

  void _clearInputs({
    bool focusOnPallet = false,
    bool skipFocus = false,
    bool includeModeChange = false,
    CountMode? newMode
  }) {
    debugPrint('🟡 _clearInputs BAŞLADI: focusOnPallet=$focusOnPallet, skipFocus=$skipFocus, current mode=$_selectedMode');

    // 🔥 YENİ: Add to Count'dan sonra pallet barkodunu da sıfırla
    // NOT: İlerde pallet barkodunun korunması istenirse aşağıdaki satırı yorum satırı yapın
    _palletBarcodeController.clear();

    // 🔥 ESKİ KOD (İlerde pallet barkodu korunması istenirse alttaki 3 satırı uncomment edin):
    // if (!_selectedMode.isPallet) {
    //   _palletBarcodeController.clear();
    // }

    _productSearchController.clear();
    _quantityController.clear();
    _shelfController.clear();
    _expiryDateController.clear();

    setState(() {
      _selectedBarcode = null;
      _selectedStokKodu = null;
      _selectedProductName = null;
      _selectedBirimKey = null;
      _availableUnits = [];
      _productSearchResults = [];
      _isShelfValid = false;

      // 🔥 YENİ: Eğer mod değişikliği varsa burada da değiştir
      if (includeModeChange && newMode != null) {
        debugPrint('🟡 _clearInputs: Mode değiştiriliyor (includeModeChange=true): $_selectedMode -> $newMode');
        _selectedMode = newMode;
      }
    });

    debugPrint('🟡 _clearInputs: setState tamamlandı, current mode=$_selectedMode');

    // Debounce timer'ı iptal et
    _searchDebounce?.cancel();

    // Scanner algılama değişkenlerini sıfırla
    _previousValue = '';
    _lastChangeTime = null;
    _inputStartTime = null;

    // Focus'u doğru alana ver (setState'ten sonra, frame bitiminde)
    if (!skipFocus) {
      debugPrint('🟡 _clearInputs: Focus yönetimi başlıyor (skipFocus=false)');
      // 🔥 Widget tree rebuild edildikten sonra focus ver
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('🟡 _clearInputs: postFrameCallback çalıştı');

          // Kısa bir gecikme ile doğru alana focus ver
          // Bu, widget tree'nin tamamen rebuild edilmesini bekler
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              // 🔥 YENİ: Eğer pallet moduna geçiliyorsa pallet barcode'a focus ver
              if (focusOnPallet) {
                debugPrint('🟢 _clearInputs: Focus veriliyor -> PALLET BARCODE (current mode=$_selectedMode)');
                _palletBarcodeFocusNode.requestFocus();
              } else {
                debugPrint('🟢 _clearInputs: Focus veriliyor -> PRODUCT SEARCH (current mode=$_selectedMode)');
                _productSearchFocusNode.requestFocus();
              }
            }
          });
        }
      });
    } else {
      debugPrint('🟡 _clearInputs: Focus atlandı (skipFocus=true)');
    }
  }

  Future<void> _removeCountItem(CountItem item) async {
    try {
      await widget.repository.deleteCountItem(item.id!);
      if (mounted) {
        setState(() {
          _countedItems.remove(item);
        });
        _showSuccess('warehouse_count.success.item_removed'.tr());
      }
    } catch (e) {
      debugPrint('Error removing count item: $e');
      if (mounted) {
        _showError('warehouse_count.error.remove_item'.tr());
      }
    }
  }


  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4CAF50), // AppTheme.accentColor (yeşil)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: widget.countSheet.sheetNumber,
      ),
      bottomNavigationBar: _buildBottomBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Mode Selector
                      _buildModeSelector(),
                      const SizedBox(height: _gap),

                      // Pallet Barcode Field (only for pallet mode)
                      if (_selectedMode.isPallet) ...[
                        Builder(
                          builder: (context) {
                            debugPrint('🔵 BUILD: Pallet Barcode Field render ediliyor (mode=$_selectedMode)');
                            return _buildPalletBarcodeField();
                          },
                        ),
                        const SizedBox(height: _gap),
                      ],

                      // Product Search with QR (HER ZAMAN VAR - hem product hem pallet modda)
                      Builder(
                        builder: (context) {
                          debugPrint('🔵 BUILD: Product Search Field render ediliyor (mode=$_selectedMode)');
                          return _buildProductSearchField();
                        },
                      ),
                      const SizedBox(height: _gap),

                      // Row 1: Expiry Date + Unit Dropdown
                      _buildExpiryDateAndUnitRow(),
                      const SizedBox(height: _gap),

                      // Row 2: Quantity + Shelf (with QR)
                      _buildQuantityAndShelfRow(),
                      const SizedBox(height: _gap),

                      // Add Button
                      _buildAddButton(),
                      const SizedBox(height: 24),

                      // Last Added Item Display
                      if (_countedItems.isNotEmpty) ...[
                        Text(
                          '${'warehouse_count.counted_items'.tr()} (${_countedItems.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80, // Fixed height for last added item
                          child: CountedItemsReviewTable(
                            items: [_countedItems.last], // Sadece son eklenen item
                            onItemRemoved: _removeCountItem,
                            enableScroll: false, // Parent scrollview var, scroll kapalı olsun
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<CountMode>(
      segments: [
        ButtonSegment(
          value: CountMode.product,
          label: Text('warehouse_count.mode.product'.tr()),
          icon: const Icon(Icons.inventory_2),
        ),
        ButtonSegment(
          value: CountMode.pallet,
          label: Text('warehouse_count.mode.pallet'.tr()),
          icon: const Icon(Icons.pallet),
        ),
      ],
      selected: {_selectedMode},
      onSelectionChanged: (Set<CountMode> newSelection) {
        final newMode = newSelection.first;
        debugPrint('🔴 MODE SELECTOR: onSelectionChanged called, newMode=$newMode, current mode=$_selectedMode');

        // 🔥 EN ÖNCE tüm focus'ları temizle (setState'ten ÖNCE!)
        FocusScope.of(context).unfocus();
        debugPrint('🔴 MODE SELECTOR: Focus temizlendi');

        // 🔥 SONRA modu değiştir (setState ile)
        setState(() {
          _selectedMode = newMode;
          debugPrint('🔴 MODE SELECTOR: setState completed, _selectedMode=$_selectedMode');
        });

        // 🔥 EN SON inputları temizle ve focus yönet
        // includeModeChange: false çünkü mod zaten yukarıda değiştirildi
        debugPrint('🔴 MODE SELECTOR: Calling _clearInputs with focusOnPallet=${newMode.isPallet}');
        _clearInputs(focusOnPallet: newMode.isPallet, includeModeChange: false);
      },
    );
  }

  Widget _buildPalletBarcodeField() {
    debugPrint('🟣 _buildPalletBarcodeField: Building, hasFocus=${_palletBarcodeFocusNode.hasFocus}');
    return QrTextField(
      controller: _palletBarcodeController,
      focusNode: _palletBarcodeFocusNode,
      labelText: 'warehouse_count.pallet_barcode'.tr(),
      showClearButton: true,
      // onQrTap verilmediğinde QrTextField varsayılan davranışı kullanır:
      // QR scanner açar ve sonucu controller'a yazar (shelf gibi)
      validator: (value) {
        if (_selectedMode.isPallet && (value == null || value.isEmpty)) {
          return 'warehouse_count.error.scan_pallet'.tr();
        }
        return null;
      },
    );
  }

  Widget _buildProductSearchField() {
    debugPrint('🟣 _buildProductSearchField: Building, hasFocus=${_productSearchFocusNode.hasFocus}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QrTextField(
          controller: _productSearchController,
          focusNode: _productSearchFocusNode,
          // Label: Ürün seçiliyse "ÜRÜN ADI (STOK KODU)", değilse "Search or Scan Product"
          labelText: _selectedProductName != null && _selectedStokKodu != null
              ? '$_selectedProductName ($_selectedStokKodu)'
              : 'warehouse_count.search_product'.tr(),
          showClearButton: true,
          onQrTap: _openQrScannerForProduct, // 🔥 YENİ: Product'a özel QR scanner
          onChanged: (value) {
            debugPrint('🟢 onChanged called: value=$value');

            // 🔥 YENİ: Hızlı girdi algılama (el terminali tespiti)
            final now = DateTime.now();
            bool isFromScanner = false;

            // Eğer önceki değer BOŞ veya ÇOK KISA idi ve şimdi bir anda UZUN bir değer geldiyse = EL TERMİNALİ
            final previousLength = _previousValue.length;
            final currentLength = value.length;
            final addedChars = currentLength - previousLength;

            debugPrint('   📊 Önceki uzunluk: $previousLength, Şimdiki uzunluk: $currentLength');
            debugPrint('   📝 Eklenen karakter sayısı: $addedChars');

            // 🔥 YENİ: İlk karakter ise başlangıç zamanını kaydet
            if (previousLength == 0 && currentLength > 0) {
              _inputStartTime = now;
              debugPrint('   🏁 Giriş başladı: $_inputStartTime');
            }

            // Eğer _lastChangeTime varsa, son değişiklikten beri geçen süreyi ölç
            if (_lastChangeTime != null) {
              final timeSinceLastChange = now.difference(_lastChangeTime!);
              debugPrint('   ⏱️ Son değişiklikten beri geçen süre: ${timeSinceLastChange.inMilliseconds}ms');

              // SCANNER KOŞULLARI:
              // 1. Bir anda çok fazla karakter eklendiyse (>= 8)
              // 2. Çok kısa sürede gerçekleştiyse (<= 100ms)
              // 3. Toplam uzunluk minimum barkod uzunluğundan fazlaysa
              if (addedChars >= _minBarcodeLength &&
                  timeSinceLastChange <= _scannerInputThreshold &&
                  currentLength >= _minBarcodeLength) {
                isFromScanner = true;
                debugPrint('   🔴 EL TERMİNALİ ALGILANDI! ($addedChars karakter ${timeSinceLastChange.inMilliseconds}ms içinde eklendi)');
              }
            } else if (currentLength >= _minBarcodeLength && previousLength == 0) {
              // İLK GİRİŞ ve UZUN: Muhtemelen scanner (field boşken bir anda 13 karakter geldi)
              isFromScanner = true;
              debugPrint('   🔴 EL TERMİNALİ ALGILANDI! (Field boşken bir anda $currentLength karakter geldi)');
            }

            // 🔥 YENİ: Ortalama hız kontrolü (daha güvenilir)
            if (!isFromScanner && currentLength >= _minBarcodeLength && _inputStartTime != null) {
              final totalInputTime = now.difference(_inputStartTime!);
              final avgTimePerChar = totalInputTime.inMilliseconds / currentLength;

              debugPrint('   📈 Ortalama hız analizi:');
              debugPrint('      - Toplam süre: ${totalInputTime.inMilliseconds}ms');
              debugPrint('      - Karakter sayısı: $currentLength');
              debugPrint('      - Ortalama karakter başına süre: ${avgTimePerChar.toStringAsFixed(1)}ms');

              if (avgTimePerChar < _avgCharInputThreshold) {
                isFromScanner = true;
                debugPrint('   🔴 EL TERMİNALİ ALGILANDI (Ortalama Hız)! (${avgTimePerChar.toStringAsFixed(1)}ms/karakter < $_avgCharInputThreshold ms/karakter)');
              }
            }

            // Değişkenleri güncelle
            _previousValue = value;
            _lastChangeTime = now;

            // 🔥 YENİ: Eğer barkod scanner işlemi devam ediyorsa, onChanged'i yok say
            if (_isProcessingBarcodeScanner) {
              debugPrint('   ⏸️ Barkod scanner işlemi devam ediyor, onChanged ignore ediliyor');
              setState(() {
                _isProcessingBarcodeScanner = false; // Flag'i sıfırla
              });
              return; // Erken çık, arama yapma
            }

            // Kullanıcı yazmaya başlarsa seçimi temizle
            if (value.isNotEmpty && _selectedProductName != null) {
              setState(() {
                _selectedBarcode = null;
                _selectedStokKodu = null;
                _selectedProductName = null;
                _availableUnits = [];
                _selectedBirimKey = null;
              });
            }

            // 🔥 Debounce mekanizması: Önceki timer'ı iptal et ve yeni timer başlat
            _searchDebounce?.cancel();

            // Boş değer ise sonuçları temizle
            if (value.trim().isEmpty) {
              setState(() {
                _productSearchResults = [];
                _previousValue = '';
                _lastChangeTime = null;
                _inputStartTime = null;
              });
              return;
            }

            _searchDebounce = Timer(const Duration(milliseconds: 400), () {
              // Kullanıcı 400ms boyunca yazmadıysa arama yap
              // Controller'dan güncel değeri al (closure'daki eski value yerine)
              if (mounted) {
                final currentValue = _productSearchController.text;
                if (currentValue.trim().isNotEmpty) {
                  // El terminali algılandıysa flag'i set et
                  _searchProduct(currentValue, isFromBarcodeScanner: isFromScanner);
                }
              }
            });
          },
          onClear: () {
            // Çarpı ikonu tıklandığında tüm ürün seçimini temizle
            _searchDebounce?.cancel();
            setState(() {
              _selectedBarcode = null;
              _selectedStokKodu = null;
              _selectedProductName = null;
              _availableUnits = [];
              _selectedBirimKey = null;
              _productSearchResults = [];
              _previousValue = '';
              _lastChangeTime = null;
              _inputStartTime = null;
            });
          },
        ),
        if (_productSearchResults.isNotEmpty)
          _buildProductSuggestions(),
      ],
    );
  }

  Widget _buildProductSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        children: _productSearchResults.map((product) {
          return ListTile(
            dense: true,
            title: Text(
              product['UrunAdi'] as String? ?? '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stok Kodu: ${product['StokKodu']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Barkod: ${product['barkod']}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                if (product['birimadi'] != null)
                  Text(
                    'Birim: ${product['birimadi']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
            onTap: () {
              _selectProduct(product);
              // Product name zaten _selectProduct içinde set ediliyor, tekrar set etme!
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpiryDateField() {
    // Ürün seçiliyse yazılabilir (barkodu olsun olmasın)
    final isProductSelected = _selectedStokKodu != null;

    return StatefulBuilder(
      builder: (context, setState) {
        return TextFormField(
          controller: _expiryDateController,
          focusNode: _expiryDateFocusNode,
          readOnly: !isProductSelected, // Ürün seçilmemişse sadece oku
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [
            _DateInputFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'goods_receiving_screen.label_expiry_date'.tr(),
            hintText: 'DD/MM/YYYY',
            // enabled parametresini KALDIRDIK - her zaman enabled, sadece readOnly değişiyor
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            suffixIcon: _expiryDateController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: isProductSelected
                        ? () {
                            _expiryDateController.clear();
                            setState(() {}); // Rebuild to update suffix icon
                            _expiryDateFocusNode.requestFocus();
                          }
                        : null,
                  )
                : const Icon(Icons.edit_calendar_outlined),
          ),
          validator: (value) {
            if (!isProductSelected) return null;

            // Expiry date is mandatory
            if (value == null || value.isEmpty) {
              return 'goods_receiving_screen.validator_expiry_date_required'.tr();
            }

            // Use comprehensive validation
            bool isValid = DateValidationUtils.isValidExpiryDate(value);
            if (!isValid) {
              return DateValidationUtils.getDateValidationError(value);
            }

            return null;
          },
          onChanged: (value) {
            setState(() {}); // Rebuild to update suffix icon
            // DD/MM/YYYY formatı tamamlandıysa ve geçerli tarihse quantity field'a geç
            if (value.length == 10) {
              bool isValid = DateValidationUtils.isValidExpiryDate(value);
              if (isValid) {
                _onExpiryDateEntered();
              }
            }
          },
          onFieldSubmitted: (value) {
            if (value.length == 10) {
              if (DateValidationUtils.isValidExpiryDate(value)) {
                _onExpiryDateEntered();
              } else {
                // Show error message
                String errorMessage = DateValidationUtils.getDateValidationError(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  void _onExpiryDateEntered() {
    if (_expiryDateController.text.isNotEmpty && _selectedStokKodu != null) {
      // Focus to quantity field
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _quantityFocusNode.requestFocus();
        }
      });
    }
  }

  Widget _buildExpiryDateAndUnitRow() {
    return Row(
      children: [
        // Expiry Date Field - %60 genişlik
        Expanded(
          flex: 6,
          child: _buildExpiryDateField(),
        ),
        const SizedBox(width: 8),
        // Unit Dropdown - %40 genişlik
        Expanded(
          flex: 4,
          child: _buildUnitDropdown(),
        ),
      ],
    );
  }

  Widget _buildUnitDropdown() {
    debugPrint('🎨 Building unit dropdown with ${_availableUnits.length} units, selected: $_selectedBirimKey');

    // 🔥 YENİ: Önce benzersiz (unique) birimleri filtrele
    final Map<String, Map<String, dynamic>> uniqueUnitsMap = {};
    for (var unit in _availableUnits) {
      final unitKey = unit['birim_key'] as String? ?? unit['_key'] as String?;
      if (unitKey != null && !uniqueUnitsMap.containsKey(unitKey)) {
        uniqueUnitsMap[unitKey] = unit;
      }
    }

    final uniqueUnits = uniqueUnitsMap.values.toList();
    debugPrint('   🔄 Filtered to ${uniqueUnits.length} unique units');

    // ITEMS LİSTESİNİ OLUŞTUR (benzersiz birimlerden)
    final dropdownItems = uniqueUnits.isNotEmpty
        ? uniqueUnits.map((unit) {
            final unitName = unit['birimadi'] as String? ?? 'Birim';
            final unitKey = unit['birim_key'] as String? ?? unit['_key'] as String?;
            debugPrint('   📋 Dropdown item: $unitName (key: $unitKey)');

            if (unitKey == null) {
              debugPrint('   ⚠️ WARNING: Unit key is NULL for $unitName! Full unit data: $unit');
            }

            return DropdownMenuItem<String>(
              value: unitKey ?? 'unknown_$unitName',
              child: Text(unitName),
            );
          }).toList()
        : <DropdownMenuItem<String>>[]; // Boş liste yerine empty list

    debugPrint('   🎯 Total dropdown items created: ${dropdownItems.length}');

    return DropdownButtonFormField<String>(
      value: _selectedBirimKey,
      isExpanded: true, // Taşmayı önlemek için
      hint: Text('goods_receiving_screen.label_unit_selection'.tr()),
      decoration: InputDecoration(
        labelText: 'goods_receiving_screen.label_unit_selection'.tr(),
        enabled: _availableUnits.isNotEmpty,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      items: dropdownItems.isEmpty ? null : dropdownItems, // Boşsa NULL ver!
      onChanged: _availableUnits.isNotEmpty
          ? (value) {
              setState(() {
                _selectedBirimKey = value;
                debugPrint('   ✅ Unit selected: $value');

                // 🔥 YENİ: Birim değiştiğinde text field'ı güncelle
                _updateProductSearchText();
              });
            }
          : null,
      validator: (value) {
        // Eğer product mode'da ve ürün seçiliyse birim zorunlu
        if (_selectedMode.isProduct && _selectedBarcode != null && _availableUnits.isNotEmpty) {
          if (value == null || value.isEmpty) {
            return 'goods_receiving_screen.validator_unit_required'.tr();
          }
        }
        return null;
      },
    );
  }

  Widget _buildQuantityAndShelfRow() {
    return Row(
      children: [
        // Quantity field - %30 genişlik
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _quantityController,
            focusNode: _quantityFocusNode,
            decoration: InputDecoration(
              labelText: 'warehouse_count.quantity'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (value) {
              // Quantity girildikten sonra shelf'e focus yap
              _shelfFocusNode.requestFocus();
            },
          ),
        ),
        const SizedBox(width: 8),
        // Shelf field - %70 genişlik
        Expanded(
          flex: 7,
          child: QrTextField(
            controller: _shelfController,
            focusNode: _shelfFocusNode,
            labelText: 'warehouse_count.shelf'.tr(),
            isValid: _isShelfValid,
            textCapitalization: TextCapitalization.characters, // Otomatik büyük harf
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'warehouse_count.error.enter_shelf'.tr();
              }
              return null;
            },
            onFieldSubmitted: (value) async {
              if (value.trim().isNotEmpty) {
                await _validateShelf(value.trim());
              }
            },
            onQrScanned: (result) async {
              await _validateShelf(result);
            },
            onChanged: (value) {
              // Reset validation state when user types
              if (_isShelfValid) {
                setState(() {
                  _isShelfValid = false;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: _isAdding ? null : _addCountItem, // İşlem devam ediyorsa devre dışı
      icon: _isAdding
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.add_circle),
      label: Text(_isAdding ? 'Adding...' : 'warehouse_count.add_item'.tr()),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _countedItems.isEmpty ? null : _openReviewScreen,
          icon: const Icon(Icons.checklist_rtl),
          label: Text('warehouse_count.review_items'.tr()),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
          ),
        ),
      ),
    );
  }

  void _openReviewScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WarehouseCountReviewScreen(
          countSheet: widget.countSheet,
          countedItems: _countedItems,
          repository: widget.repository,
        ),
      ),
    );
  }
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Handle deletion - if user deletes a slash, delete the preceding digit too
    if (newValue.text.length < oldValue.text.length) {
      if (newValue.text.isNotEmpty && oldValue.text.length > newValue.text.length) {
        final deletedChar = oldValue.text[newValue.text.length];
        if (deletedChar == '/' && newValue.text.isNotEmpty) {
          return TextEditingValue(
            text: newValue.text.substring(0, newValue.text.length - 1),
            selection: TextSelection.collapsed(offset: newValue.text.length - 1),
          );
        }
      }
      return newValue;
    }

    // Only allow digits
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    if (text.length > 8) return oldValue;

    // Smart formatting with validation
    String formatted = _smartFormatDate(text);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _smartFormatDate(String digits) {
    String result = '';

    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) result += '/';

      // Add digit with smart validation
      String digit = digits[i];

      // Day validation (position 0-1)
      if (i < 2) {
        if (i == 0 && int.parse(digit) > 3) {
          digit = '3'; // Max day starts with 3
        } else if (i == 1 && result.isNotEmpty) {
          int firstDigit = int.parse(result[0]);
          int dayValue = firstDigit * 10 + int.parse(digit);
          if (dayValue > 31) {
            digit = '1'; // 31 max
          } else if (dayValue == 0) {
            digit = '1'; // Min 01
          }
        }
      }
      // Month validation (position 2-3)
      else if (i < 4) {
        int monthPos = i - 2;
        if (monthPos == 0 && int.parse(digit) > 1) {
          digit = '1'; // Max month starts with 1
        } else if (monthPos == 1) {
          String monthFirstDigit = result.split('/')[1];
          int firstDigit = int.parse(monthFirstDigit);
          int monthValue = firstDigit * 10 + int.parse(digit);
          if (monthValue > 12) {
            digit = '2'; // 12 max
          } else if (monthValue == 0) {
            digit = '1'; // Min 01
          }
        }
      }

      result += digit;
    }

    // Final validation when we have complete date (8 digits)
    if (digits.length == 8) {
      result = _validateCompleteDate(result);
    }

    return result;
  }

  String _validateCompleteDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length != 3) return dateStr;

      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);

      // Create DateTime to check validity
      final date = DateTime(year, month, day);

      // If date was adjusted, use the adjusted values
      if (date.day != day || date.month != month) {
        // DateTime adjusted it, which means original was invalid
        // Use last day of the intended month
        final lastDay = DateTime(year, month + 1, 0).day;
        day = day > lastDay ? lastDay : day;

        return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}';
      }

      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }
}
