// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
import 'package:diapalet/core/widgets/qr_scanner_screen.dart';
import 'package:diapalet/core/widgets/shared_app_bar.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/goods_receipt_entities.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/product_info.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/purchase_order.dart';
import 'package:diapalet/features/goods_receiving/domain/repositories/goods_receiving_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';

class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  // --- State ve Controller'lar ---
  late final GoodsReceivingRepository _repository;
  final _formKey = GlobalKey<FormState>();

  // Sayfa durumu
  bool _isLoading = true;
  bool _isSaving = false;

  // Seçimler ve veriler
  ReceivingMode _receivingMode = ReceivingMode.kutu;
  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<ProductInfo> _products = [];
  ProductInfo? _selectedProduct;
  List<ReceiptItemDraft> _receiptItems = []; // Listeye eklenen ürünler

  // Controller'lar
  final _palletBarcodeController = TextEditingController();
  final _quantityController = TextEditingController();
  final _productSearchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadInitialData();

    // Ürün arama için debounce (kullanıcı yazmayı bitirince arama yapar)
    _productSearchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (_productSearchController.text.isNotEmpty) {
          _searchProducts(_productSearchController.text);
        }
      });
    });
  }

  @override
  void dispose() {
    _palletBarcodeController.dispose();
    _quantityController.dispose();
    _productSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- Veri Yükleme ---
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final orders = await _repository.getOpenPurchaseOrders();
      if (mounted) {
        setState(() {
          _purchaseOrders = orders;
        });
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Siparişler yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchProducts(String query) async {
    try {
      final products = await _repository.searchProducts(query);
      if (mounted) {
        setState(() {
          _products = products;
        });
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Ürünler aranırken hata: $e');
    }
  }

  // --- UI Etkileşimleri ---
  void _onOrderSelected(PurchaseOrder? order) {
    setState(() {
      _selectedOrder = order;
      // Sipariş seçimi değiştiğinde diğer alanları temizle
      _clearEntryFields();
    });
  }

  void _onProductSelected(ProductInfo? product) {
    setState(() {
      _selectedProduct = product;
    });
  }

  void _addItemToList() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final quantity = double.tryParse(_quantityController.text);
    if (_selectedProduct == null || quantity == null || quantity <= 0) {
      _showErrorSnackBar("Lütfen ürün seçin ve geçerli bir miktar girin.");
      return;
    }

    setState(() {
      _receiptItems.add(ReceiptItemDraft(
        product: _selectedProduct!,
        quantity: quantity,
        palletBarcode: _receivingMode == ReceivingMode.palet
            ? _palletBarcodeController.text
            : null,
      ));
      _clearEntryFields();
    });
  }

  Future<void> _saveAndConfirm() async {
    if (_receiptItems.isEmpty) {
      _showErrorSnackBar("Kaydetmek için listeye en az bir ürün eklemelisiniz.");
      return;
    }

    // Onay dialogu
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mal Kabulü Onayla"),
        content: Text("${_receiptItems.length} kalem ürün 'MAL KABUL' lokasyonuna kaydedilecek. Emin misiniz?"),
        actions: [
          TextButton(child: const Text("İptal"), onPressed: () => Navigator.of(ctx).pop(false)),
          ElevatedButton(child: const Text("Onayla"), onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    try {
      // Payload'ı oluştur
      final payload = GoodsReceiptPayload(
        header: GoodsReceiptHeader(
          siparisId: _selectedOrder?.id,
          invoiceNumber: _selectedOrder?.poId,
          receiptDate: DateTime.now(),
        ),
        items: _receiptItems.map((draft) => GoodsReceiptItemPayload(
          urunId: draft.product.id,
          quantity: draft.quantity,
          palletBarcode: draft.palletBarcode,
        )).toList(),
      );

      // Repository üzerinden kaydet
      await _repository.saveGoodsReceipt(payload);

      if (mounted) {
        _showSuccessSnackBar("Mal kabul başarıyla kaydedildi!");
        _resetScreen();
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar("Kaydetme hatası: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Temizlik ve Resetleme ---
  void _clearEntryFields() {
    _productSearchController.clear();
    setState(() {
      _selectedProduct = null;
      _products = [];
    });
    _quantityController.clear();
    // Palet barkodu modu Palet ise temizlenmemeli
    if (_receivingMode == ReceivingMode.kutu) {
      _palletBarcodeController.clear();
    }
    FocusScope.of(context).unfocus();
  }

  void _resetScreen() {
    setState(() {
      _receiptItems.clear();
      _selectedOrder = null;
      _receivingMode = ReceivingMode.kutu;
      _clearEntryFields();
    });
  }

  // --- Yardımcı Widget'lar ve Metotlar ---
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
    ));
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
    ));
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _palletBarcodeController.text = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(title: 'Mal Kabul'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // 1. Mod Seçimi
                  SegmentedButton<ReceivingMode>(
                    segments: const [
                      ButtonSegment(value: ReceivingMode.kutu, label: Text('Kutu'), icon: Icon(Icons.inventory_2_outlined)),
                      ButtonSegment(value: ReceivingMode.palet, label: Text('Palet'), icon: Icon(Icons.pallet)),
                    ],
                    selected: {_receivingMode},
                    onSelectionChanged: (newSelection) {
                      setState(() => _receivingMode = newSelection.first);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. Sipariş Seçimi
                  DropdownButtonFormField<PurchaseOrder>(
                    value: _selectedOrder,
                    items: _purchaseOrders.map((order) {
                      return DropdownMenuItem(
                        value: order,
                        child: Text(order.poId ?? "ID: ${order.id}"),
                      );
                    }).toList(),
                    onChanged: _onOrderSelected,
                    decoration: const InputDecoration(
                      labelText: 'Sipariş Seç (Opsiyonel)',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                  ),
                  const SizedBox(height: 16),

                  // 3. Palet Barkodu (Görünürlük kontrolü)
                  if (_receivingMode == ReceivingMode.palet)
                    TextFormField(
                      controller: _palletBarcodeController,
                      decoration: InputDecoration(
                          labelText: 'Palet Barkodu',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanBarcode,
                          )
                      ),
                      validator: (value) {
                        if (_receivingMode == ReceivingMode.palet && (value == null || value.isEmpty)) {
                          return "Palet modu için barkod zorunludur.";
                        }
                        return null;
                      },
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  const SizedBox(height: 16),

                  const Divider(),

                  // 4. Ürün Seçimi (Autocomplete)
                  Autocomplete<ProductInfo>(
                    displayStringForOption: (option) => "${option.name} (${option.stockCode})",
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text == '') {
                        return const Iterable<ProductInfo>.empty();
                      }
                      // Arama sonuçları _products listesinden gelecek
                      return _products.where((p) =>
                      p.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                          p.stockCode.toLowerCase().contains(textEditingValue.text.toLowerCase())
                      );
                    },
                    onSelected: _onProductSelected,
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      // Arama kontrolcüsünü bizimkiyle senkronize et
                      if (_productSearchController != controller) {
                        // Bu sadece bir kerelik senkronizasyon için
                      }
                      return TextFormField(
                        controller: _productSearchController, // Kendi kontrolcümüzü kullanıyoruz
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: "Ürün Ara (Ad veya Stok Kodu)",
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.search),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 5. Miktar Girişi
                  TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Miktar',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) => (value?.isEmpty ?? true) ? "Miktar girin." : null,
                  ),
                  const SizedBox(height: 24),

                  // 6. Listeye Ekle Butonu
                  ElevatedButton.icon(
                    onPressed: _addItemToList,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Listeye Ekle'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  ),
                  const SizedBox(height: 24),

                  // 7. Eklenenler Listesi
                  Text("Kabul Edilecek Ürünler (${_receiptItems.length})", style: Theme.of(context).textTheme.titleMedium),
                  const Divider(),
                  if (_receiptItems.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Liste boş.")))
                  else
                    _buildReceiptsList(),
                ],
              ),
            ),
            // 8. Kaydet ve Onayla Butonu
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveAndConfirm,
                icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.check_circle),
                label: const Text('Kaydet ve Onayla'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50)
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _receiptItems.length,
      itemBuilder: (context, index) {
        final item = _receiptItems[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title: Text(item.product.name),
            subtitle: Text("Palet: ${item.palletBarcode ?? 'YOK'}"),
            trailing: Text("x ${item.quantity.toStringAsFixed(0)}", style: Theme.of(context).textTheme.titleLarge),
            onLongPress: () {
              // Silme onayı
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Öğeyi Sil"),
                content: Text("'${item.product.name}' ürününü listeden kaldırmak istediğinize emin misiniz?"),
                actions: [
                  TextButton(child: const Text("İptal"), onPressed: () => Navigator.of(ctx).pop()),
                  TextButton(child: const Text("Sil"), onPressed: (){
                    setState(() => _receiptItems.removeAt(index));
                    Navigator.of(ctx).pop();
                  }),
                ],
              ));
            },
          ),
        );
      },
    );
  }
}
