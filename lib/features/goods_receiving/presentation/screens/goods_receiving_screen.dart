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
  // --- Sabitler ve Stil Değişkenleri (Eski tasarımdan) ---
  static const double _fieldHeight = 56;
  static const double _gap = 12;
  static const double _smallGap = 8;
  final _borderRadius = BorderRadius.circular(12);

  // --- State ve Controller'lar (Yeni mantıktan) ---
  late final GoodsReceivingRepository _repository;
  final _formKey = GlobalKey<FormState>();

  // Sayfa durumu
  bool _isLoading = true;
  bool _isSaving = false;

  // Seçimler ve veriler
  ReceivingMode _receivingMode = ReceivingMode.palet;
  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrder? _selectedOrder;
  List<ProductInfo> _availableProducts = [];
  ProductInfo? _selectedProduct;
  List<ReceiptItemDraft> _addedItems = [];

  // Controller'lar
  final _orderController = TextEditingController();
  final _palletIdController = TextEditingController();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Provider'ı initState içinde, listen:false ile almak en güvenlisidir.
    _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
    _loadInitialData();
  }

  @override
  void dispose() {
    _orderController.dispose();
    _palletIdController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // --- VERİ YÜKLEME (YENİ MANTIK) ---
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getOpenPurchaseOrders(),
        _repository.searchProducts(''), // Başlangıçta tüm ürünleri veya bir kısmını getir
      ]);
      if (!mounted) return;

      setState(() {
        // HATA DÜZELTMESİ: Future.wait'ten dönen List<Object> doğru tiplere çevrildi (cast).
        _purchaseOrders = results[0] as List<PurchaseOrder>;
        _availableProducts = results[1] as List<ProductInfo>;
      });
    } catch (e) {
      if (mounted) _showErrorSnackBar('Başlangıç verileri yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LİSTE VE KAYDETME İŞLEMLERİ (YENİ MANTIK) ---
  void _addItemToList() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final quantity = double.tryParse(_quantityController.text);
    if (_selectedProduct == null || quantity == null || quantity <= 0) {
      _showErrorSnackBar("Lütfen ürün seçin ve geçerli bir miktar girin.");
      return;
    }

    final isKutuModeLocked = _receivingMode == ReceivingMode.kutu && _addedItems.isNotEmpty;
    if (isKutuModeLocked) {
      _showErrorSnackBar("Kutu modunda sadece tek çeşit ürün ekleyebilirsiniz.");
      return;
    }

    setState(() {
      _addedItems.insert(0, ReceiptItemDraft(
        product: _selectedProduct!,
        quantity: quantity,
        palletBarcode: _receivingMode == ReceivingMode.palet ? _palletIdController.text : null,
      ));
      _clearEntryFields();
    });
    _showSuccessSnackBar("${_selectedProduct!.name} listeye eklendi.");
  }

  void _removeItemFromList(int index) {
    if (!mounted) return;
    final removedItemName = _addedItems[index].product.name;
    setState(() => _addedItems.removeAt(index));
    _showSuccessSnackBar("$removedItemName listeden kaldırıldı.", isError: true);
  }

  Future<void> _saveAndConfirm() async {
    if (_addedItems.isEmpty) {
      _showErrorSnackBar("Kaydetmek için listeye en az bir ürün eklemelisiniz.");
      return;
    }
    if (_selectedOrder == null) {
      _showErrorSnackBar("Lütfen bir sipariş seçin.");
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mal Kabulü Onayla"),
        content: Text("${_addedItems.length} kalem ürün 'MAL KABUL' lokasyonuna kaydedilecek. Emin misiniz?"),
        actions: [
          TextButton(child: const Text("İptal"), onPressed: () => Navigator.of(ctx).pop(false)),
          ElevatedButton(child: const Text("Onayla ve Kaydet"), onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isSaving = true);

    try {
      final payload = GoodsReceiptPayload(
        header: GoodsReceiptHeader(
          siparisId: _selectedOrder!.id,
          invoiceNumber: _selectedOrder!.poId,
          receiptDate: DateTime.now(),
        ),
        items: _addedItems.map((draft) => GoodsReceiptItemPayload(
          urunId: draft.product.id,
          quantity: draft.quantity,
          palletBarcode: draft.palletBarcode,
        )).toList(),
      );
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

  void _clearEntryFields() {
    _productController.clear();
    _quantityController.clear();
    _selectedProduct = null;
    // Palet modundaysa ve listede ürün varsa palet ID'si temizlenmemeli.
    if (_receivingMode == ReceivingMode.kutu || _addedItems.isEmpty) {
      _palletIdController.clear();
    }
    FocusScope.of(context).unfocus();
  }

  void _resetScreen() {
    setState(() {
      _addedItems.clear();
      _selectedOrder = null;
      _orderController.clear();
      _formKey.currentState?.reset();
      _clearEntryFields();
    });
  }

  // --- ARAYÜZ (ESKİ TASARIMDAN UYARLANMIŞ) ---
  @override
  Widget build(BuildContext context) {
    final bool isKutuModeLocked = _receivingMode == ReceivingMode.kutu && _addedItems.isNotEmpty;

    return Scaffold(
      appBar: SharedAppBar(title: 'Mal Kabul'),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _buildBottomBar(),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeSelector(),
                const SizedBox(height: _gap),
                _buildSearchableOrderDropdown(),
                if (_receivingMode == ReceivingMode.palet) ...[
                  const SizedBox(height: _gap),
                  _buildPalletIdInput(),
                ],
                const SizedBox(height: _gap),
                _buildSearchableProductInputRow(isLocked: isKutuModeLocked),
                const SizedBox(height: _gap),
                _buildQuantityInput(isLocked: isKutuModeLocked),
                const SizedBox(height: _gap),
                _buildAddToListButton(isLocked: isKutuModeLocked),
                const SizedBox(height: _smallGap + 4),
                Expanded(child: _buildAddedItemsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<ReceivingMode>(
        segments: const [
          ButtonSegment(value: ReceivingMode.palet, label: Text('Palet'), icon: Icon(Icons.pallet)),
          ButtonSegment(value: ReceivingMode.kutu, label: Text('Kutu'), icon: Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_receivingMode},
        onSelectionChanged: (newSelection) {
          if (_isSaving) return;
          setState(() {
            _receivingMode = newSelection.first;
            _addedItems.clear();
            _clearEntryFields();
          });
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(75),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildSearchableOrderDropdown() {
    return TextFormField(
      controller: _orderController,
      readOnly: true,
      decoration: _inputDecoration('Sipariş Seç', filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
      onTap: () async {
        final PurchaseOrder? selected = await _showSearchableDropdownDialog<PurchaseOrder>(
          title: 'Sipariş Seç',
          items: _purchaseOrders,
          itemToString: (item) => item.poId ?? "ID: ${item.id}",
          filterCondition: (item, query) => (item.poId ?? "ID: ${item.id}").toLowerCase().contains(query.toLowerCase()),
        );
        if (selected != null) {
          setState(() {
            _selectedOrder = selected;
            _orderController.text = selected.poId ?? "ID: ${selected.id}";
          });
        }
      },
      validator: (value) => (value == null || value.isEmpty) ? 'Lütfen bir sipariş seçin.' : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }

  Widget _buildPalletIdInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _palletIdController,
            decoration: _inputDecoration('Palet Barkodu Girin/Okutun'),
            validator: (value) {
              if (_receivingMode == ReceivingMode.palet && (value == null || value.isEmpty)) {
                return "Palet barkodu zorunludur.";
              }
              return null;
            },
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(onTap: () async {
          final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScannerScreen()));
          if(result != null && result.isNotEmpty && mounted) {
            _palletIdController.text = result;
          }
        }, size: _fieldHeight),
      ],
    );
  }

  Widget _buildSearchableProductInputRow({required bool isLocked}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _productController,
            readOnly: true,
            enabled: !isLocked,
            decoration: _inputDecoration('Ürün Seç', filled: true, suffixIcon: const Icon(Icons.arrow_drop_down), enabled: !isLocked),
            onTap: isLocked ? null : () async {
              final ProductInfo? selected = await _showSearchableDropdownDialog<ProductInfo>(
                title: 'Ürün Seç',
                items: _availableProducts,
                itemToString: (product) => "${product.name} (${product.stockCode})",
                filterCondition: (product, query) =>
                product.name.toLowerCase().contains(query.toLowerCase()) ||
                    product.stockCode.toLowerCase().contains(query.toLowerCase()),
              );
              if (selected != null) {
                setState(() {
                  _selectedProduct = selected;
                  _productController.text = "${selected.name} (${selected.stockCode})";
                });
              }
            },
            validator: (value) => (value == null || value.isEmpty) ? 'Lütfen bir ürün seçin.' : null,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ),
        const SizedBox(width: _smallGap),
        _QrButton(onTap: (){}, size: _fieldHeight, isEnabled: !isLocked), // QR Butonun işlevi eklenebilir
      ],
    );
  }

  Widget _buildQuantityInput({required bool isLocked}) {
    return TextFormField(
      controller: _quantityController,
      keyboardType: TextInputType.number,
      enabled: !isLocked,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _inputDecoration('Miktar Girin', enabled: !isLocked),
      validator: (value) {
        if (isLocked) return null;
        if (value == null || value.isEmpty) return 'Miktar girin.';
        final number = int.tryParse(value);
        if (number == null || number <= 0) return 'Geçerli bir miktar girin.';
        return null;
      },
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }

  Widget _buildAddToListButton({required bool isLocked}) {
    return SizedBox(
      height: _fieldHeight,
      child: ElevatedButton.icon(
        onPressed: isLocked || _isSaving ? null : _addItemToList,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Listeye Ekle'),
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildAddedItemsList() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(125),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(180)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              "Eklenen Ürünler (${_addedItems.length})",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: _addedItems.isEmpty
                ? Center(
              child: Text(
                "Liste boş. Lütfen ürün ekleyin.",
                style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: _smallGap, horizontal: _smallGap / 2),
              itemCount: _addedItems.length,
              itemBuilder: (context, index) {
                final item = _addedItems[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    title: Text(item.product.name, style: Theme.of(context).textTheme.titleSmall),
                    subtitle: Text("Palet: ${item.palletBarcode ?? 'YOK'}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("x${item.quantity.toInt()}", style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(width: _smallGap),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                          onPressed: () => _removeItemFromList(index),
                          tooltip: 'Ürünü sil',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_isLoading) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton.icon(
        onPressed: _addedItems.isEmpty || _isSaving ? null : _saveAndConfirm,
        icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
        label: const Text('Kaydet ve Onayla'),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // --- YARDIMCI METOTLAR (Eski tasarımdan) ---

  InputDecoration _inputDecoration(String label, {bool filled = false, Widget? suffixIcon, bool enabled = true}) {
    return InputDecoration(
      labelText: label,
      filled: filled,
      fillColor: enabled ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(75) : Colors.grey.shade200,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabled: enabled,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(fontSize: 0, height: 0.01), // Hata mesajını gizler
      helperText: ' ', // Alanın altına boşluk ekler
      helperStyle: const TextStyle(fontSize: 0, height: 0.01),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.orangeAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: _borderRadius),
    ));
  }

  Future<T?> _showSearchableDropdownDialog<T>({
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
  }) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        String searchText = '';
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filteredItems = items.where((item) => filterCondition(item, searchText)).toList();

            return AlertDialog(
              title: Text(title),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Ara...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: _borderRadius),
                      ),
                      onChanged: (value) {
                        setStateDialog(() {
                          searchText = value;
                        });
                      },
                    ),
                    const SizedBox(height: _gap),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? const Center(child: Text('Sonuç bulunamadı.'))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return ListTile(
                            title: Text(itemToString(item)),
                            onTap: () => Navigator.of(dialogContext).pop(item),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('İptal'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),

              ],
            );
          },
        );
      },
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool isEnabled;

  const _QrButton({required this.onTap, required this.size, this.isEnabled = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: isEnabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade300;
            }
            return Theme.of(context).colorScheme.secondaryContainer;
          }),
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }
}
