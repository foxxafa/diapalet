// lib/features/goods_receiving/presentation/screens/goods_receiving_screen.dart
// Bu dosya tamamen yeni tasarıma göre yeniden yazıldı.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:intl/intl.dart'; // Eğer tarih formatlama gerekirse (şu an kullanılmıyor)

import '../../domain/entities/product_info.dart';
import '../../domain/entities/goods_receipt_log_item.dart';
import '../../domain/repositories/goods_receiving_repository.dart';
import '../../../../core/widgets/qr_scanner_screen.dart'; // QR Tarayıcı

// ReceivedProductListItemCard bu yeni tasarımda doğrudan kullanılmayabilir,
// çünkü GoodsReceiptLogItem farklı alanlara sahip.
// İhtiyaç olursa yeni bir list item card oluşturulabilir.
// import '../widgets/received_product_list_item_card.dart';


class GoodsReceivingScreen extends StatefulWidget {
  const GoodsReceivingScreen({super.key});

  @override
  State<GoodsReceivingScreen> createState() => _GoodsReceivingScreenState();
}

class _GoodsReceivingScreenState extends State<GoodsReceivingScreen> {
  late GoodsReceivingRepository _repository;
  bool _isRepoInitialized = false;
  bool _isLoading = true; // Başlangıçta yükleme true
  bool _isSaving = false;

  final _formKey = GlobalKey<FormState>();

  // State değişkenleri
  ReceiveMode _selectedMode = ReceiveMode.palet;

  List<String> _availableInvoices = [];
  String? _selectedInvoice;

  List<String> _availablePallets = [];
  List<String> _availableBoxes = [];
  String? _selectedPalletOrBoxId;

  List<ProductInfo> _availableProducts = [];
  ProductInfo? _selectedProduct;

  final TextEditingController _quantityController = TextEditingController();
  final List<GoodsReceiptLogItem> _addedItems = [];

  // UI Sabitleri
  static const double _fieldHeight = 56;
  static const double _gap = 12;
  static const double _smallGap = 8;
  final _borderRadius = BorderRadius.circular(12);

  @override
  void initState() {
    super.initState();
    // initState içinde async işlem yapılmaz, didChangeDependencies kullanılır.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repository = Provider.of<GoodsReceivingRepository>(context, listen: false);
      _loadInitialData();
      _isRepoInitialized = true;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getInvoices(),
        _repository.getPalletsForDropdown(),
        _repository.getBoxesForDropdown(),
        _repository.getProductsForDropdown(),
      ]);
      if (!mounted) return;

      setState(() {
        _availableInvoices = results[0] as List<String>;
        _availablePallets = results[1] as List<String>;
        _availableBoxes = results[2] as List<String>;
        _availableProducts = results[3] as List<ProductInfo>;

        // Otomatik ilk seçimler (isteğe bağlı)
        _selectedInvoice = _availableInvoices.isNotEmpty ? _availableInvoices.first : null;
        _updatePalletOrBoxOptions(); // Mod seçimine göre palet/kutu listesini ve seçimi ayarla
        _selectedProduct = _availableProducts.isNotEmpty ? _availableProducts.first : null;
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar("Başlangıç verileri yüklenirken hata: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updatePalletOrBoxOptions() {
    // Bu metod, _selectedMode değiştiğinde veya başlangıçta çağrılır.
    // Palet/Kutu seçeneklerini ve seçili değeri günceller.
    if (_selectedMode == ReceiveMode.palet) {
      _selectedPalletOrBoxId = _availablePallets.isNotEmpty ? _availablePallets.first : null;
    } else {
      _selectedPalletOrBoxId = _availableBoxes.isNotEmpty ? _availableBoxes.first : null;
    }
  }


  void _resetInputFields({bool resetAll = false}) {
    _quantityController.clear();
    if (mounted) {
      setState(() {
        // Genellikle ürün ve miktar sıfırlanır, diğerleri kalır.
        // _selectedProduct = _availableProducts.isNotEmpty ? _availableProducts.first : null;
        if(resetAll){
          _selectedInvoice = _availableInvoices.isNotEmpty ? _availableInvoices.first : null;
          _selectedMode = ReceiveMode.palet; // Modu da başa al
          _updatePalletOrBoxOptions(); // Bu, _selectedPalletOrBoxId'yi de günceller
          _selectedProduct = _availableProducts.isNotEmpty ? _availableProducts.first : null;
          _addedItems.clear();
        }
      });
    }
  }

  void _addItemToList() {
    FocusScope.of(context).unfocus(); // Klavyeyi kapat
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar("Lütfen tüm zorunlu alanları doğru doldurun.");
      return;
    }
    // _selectedInvoice, _selectedPalletOrBoxId, _selectedProduct null kontrolleri
    // validator'lar tarafından yapıldığı için burada tekrar kontrol etmeye gerek yok
    // (DropdownButtonFormField'ların validator'ları null ise hata verir).

    final quantity = int.tryParse(_quantityController.text);
    // Miktar validasyonu da TextFormField validator'ı tarafından yapılıyor.

    final newItem = GoodsReceiptLogItem(
      mode: _selectedMode,
      invoice: _selectedInvoice!,
      palletOrBoxId: _selectedPalletOrBoxId!,
      product: _selectedProduct!,
      quantity: quantity!, // Validator'lar geçtiği için null olamaz.
    );

    if (mounted) {
      setState(() {
        _addedItems.insert(0, newItem);
        _quantityController.clear(); // Sadece miktar sıfırlanır
        // İsteğe bağlı: _selectedProduct = null; veya ilk ürüne ayarla
      });
      _showSuccessSnackBar("${newItem.product.name} listeye eklendi.");
    }
  }

  void _removeItemFromList(int index) {
    if (mounted) {
      setState(() {
        final removedItem = _addedItems.removeAt(index);
        _showSuccessSnackBar("${removedItem.product.name} listeden silindi.", isError: true);
      });
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (_addedItems.isEmpty) {
      _showErrorSnackBar("Kaydedilecek ürün bulunmuyor.");
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Onay'),
          content: Text('${_addedItems.length} kalem ürün sisteme kaydedilecek. Emin misiniz?'),
          actions: <Widget>[
            TextButton(
              child: const Text('İptal'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: const Text('Kaydet ve Onayla'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isSaving = true);
      try {
        await _repository.saveGoodsReceiptLog(_addedItems, _selectedMode);
        if (mounted) {
          _showSuccessSnackBar("Ürünler başarıyla kaydedildi!");
          setState(() {
            // _addedItems.clear(); // resetInputFields içinde yapılıyor
            _resetInputFields(resetAll: true); // Her şeyi sıfırla
          });
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar("Kaydetme sırasında hata: ${e.toString()}");
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }


  Future<void> _scanQrAndUpdateSelection(String fieldType) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      String successMessage = "";
      bool found = false;

      setState(() {
        if (fieldType == 'palletOrBox') {
          final currentOptions = _selectedMode == ReceiveMode.palet ? _availablePallets : _availableBoxes;
          if (currentOptions.contains(result)) {
            _selectedPalletOrBoxId = result;
            successMessage = "${_selectedMode.displayName} QR ile seçildi: $result";
            found = true;
          } else {
            _showErrorSnackBar("Taranan QR ($result) geçerli bir ${_selectedMode.displayName} seçeneği değil.");
          }
        } else if (fieldType == 'product') {
          // Ürün ID, Stok Kodu veya Adına göre arama yap.
          // Gerçek uygulamada bu daha karmaşık bir arama olabilir (örn. büyük/küçük harf duyarsız)
          final matchedProduct = _availableProducts.firstWhere(
                (p) => p.id == result || p.stockCode == result || p.name.toLowerCase() == result.toLowerCase(),
            orElse: () => ProductInfo.empty,
          );
          if (matchedProduct != ProductInfo.empty) {
            _selectedProduct = matchedProduct;
            successMessage = "Ürün QR ile seçildi: ${matchedProduct.name}";
            found = true;
          } else {
            _showErrorSnackBar("Taranan QR ($result) geçerli bir ürün seçeneği değil.");
          }
        }
      });
      if(found && mounted){
        _showSuccessSnackBar(successMessage);
      }
    }
  }


  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccessSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.orangeAccent : Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  InputDecoration _inputDecoration(String label, {bool filled = false, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      // contentPadding dikeyde ortalamak için ayarlandı.
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: (_fieldHeight - 20) / 2),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double bottomNavHeight = (screenHeight * 0.09).clamp(70.0, 90.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mal Kabul'), // Başlık güncellendi
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true, // Klavye açıldığında taşmayı önler
      bottomNavigationBar: _isLoading || _isSaving
          ? null
          : Container(
        // Kenar boşlukları Padding widget'ı ile daha iyi yönetilebilir.
        margin: const EdgeInsets.fromLTRB(20,0,20,20), // Alt boşluk artırıldı
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _addedItems.isEmpty ? null : _onConfirmSave,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: _borderRadius),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      body: SafeArea( // SafeArea, sistem arayüzlerinden (örn. notch) kaçınmak için
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding( // Ana içerik için genel padding
          padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 0), // Alt padding bottomNav için çıkarıldı
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeSelector(),
                const SizedBox(height: _gap),
                _buildInvoiceDropdown(),
                const SizedBox(height: _gap),
                _buildPalletOrBoxInputRow(),
                const SizedBox(height: _gap),
                _buildProductInputRow(),
                const SizedBox(height: _gap),
                _buildQuantityInput(),
                const SizedBox(height: _gap),
                _buildAddToListButton(),
                const SizedBox(height: _smallGap + 4), // Liste ile buton arası boşluk
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
      child: SegmentedButton<ReceiveMode>(
        segments: const [
          ButtonSegment(value: ReceiveMode.palet, label: Text('Palet'), icon: Icon(Icons.pallet)),
          ButtonSegment(value: ReceiveMode.kutu, label: Text('Kutu'), icon: Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<ReceiveMode> newSelection) {
          if (mounted) {
            setState(() {
              _selectedMode = newSelection.first;
              _updatePalletOrBoxOptions();
            });
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius), // Hata düzeltildi
          // minimumSize ve padding ile buton boyutları ayarlanabilir.
          // minimumSize: Size(double.infinity, 40),
        ),
      ),
    );
  }

  Widget _buildInvoiceDropdown() {
    return SizedBox(
      height: _fieldHeight,
      child: DropdownButtonFormField<String>(
        decoration: _inputDecoration('İrsaliye Seç', filled: true),
        value: _selectedInvoice,
        isExpanded: true,
        hint: const Text('İrsaliye Seçin'),
        items: _availableInvoices.map((String invoice) {
          return DropdownMenuItem<String>(value: invoice, child: Text(invoice, overflow: TextOverflow.ellipsis));
        }).toList(),
        onChanged: (String? newValue) {
          if (mounted) setState(() => _selectedInvoice = newValue);
        },
        validator: (value) => value == null ? 'Lütfen bir irsaliye seçin.' : null,
      ),
    );
  }

  Widget _buildPalletOrBoxInputRow() {
    final currentOptions = _selectedMode == ReceiveMode.palet ? _availablePallets : _availableBoxes;
    final label = _selectedMode == ReceiveMode.palet ? 'Palet Seç' : 'Kutu Seç';

    return SizedBox(
      height: _fieldHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Dikeyde hizalama
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              decoration: _inputDecoration(label, filled: true),
              value: _selectedPalletOrBoxId,
              isExpanded: true,
              hint: Text(label),
              items: currentOptions.map((String id) {
                return DropdownMenuItem<String>(value: id, child: Text(id, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (String? newValue) {
                if (mounted) setState(() => _selectedPalletOrBoxId = newValue);
              },
              validator: (value) => value == null ? 'Lütfen bir $label.' : null,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () => _scanQrAndUpdateSelection('palletOrBox'),
            size: _fieldHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildProductInputRow() {
    return SizedBox(
      height: _fieldHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Dikeyde hizalama
        children: [
          Expanded(
            child: DropdownButtonFormField<ProductInfo>(
              decoration: _inputDecoration('Ürün Seç', filled: true),
              value: _selectedProduct,
              isExpanded: true,
              hint: const Text('Ürün Seçin'),
              items: _availableProducts.map((ProductInfo product) {
                return DropdownMenuItem<ProductInfo>(
                  value: product,
                  child: Text("${product.name} (${product.stockCode})", overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (ProductInfo? newValue) {
                if (mounted) setState(() => _selectedProduct = newValue);
              },
              validator: (value) => value == null ? 'Lütfen bir ürün seçin.' : null,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () => _scanQrAndUpdateSelection('product'),
            size: _fieldHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityInput() {
    return SizedBox(
      height: _fieldHeight,
      child: TextFormField(
        controller: _quantityController,
        keyboardType: TextInputType.number,
        decoration: _inputDecoration('Miktar Girin'),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Miktar girin.';
          final number = int.tryParse(value);
          if (number == null) return 'Lütfen sayı girin.';
          if (number <= 0) return 'Miktar 0\'dan büyük olmalı.';
          return null;
        },
      ),
    );
  }

  Widget _buildAddToListButton() {
    return SizedBox(
      height: _fieldHeight,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _addItemToList,
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
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: _borderRadius,
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Eklenen Kalemler (${_addedItems.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: _addedItems.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Henüz listeye kalem eklenmedi.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: _smallGap, horizontal: _smallGap / 2),
              itemCount: _addedItems.length,
              itemBuilder: (context, index) {
                final item = _addedItems[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: _smallGap / 2),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    title: Text("${item.product.name} (${item.product.stockCode})", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        '${item.mode.displayName}: ${item.palletOrBoxId}\nİrsaliye: ${item.invoice}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${item.quantity} Adet', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(width: _smallGap),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.redAccent[700]),
                          onPressed: () => _removeItemFromList(index),
                          tooltip: 'Bu Kalemi Sil',
                          padding: EdgeInsets.zero, // Daha kompakt
                          constraints: const BoxConstraints(), // Daha kompakt
                        ),
                      ],
                    ),
                    isThreeLine: true, // Subtitle'ın tamamını göstermek için
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

// Helper QR Button Widget (can be moved to a common widgets folder)
class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const _QrButton({required this.onTap, required this.size, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          padding: EdgeInsets.zero,
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }
}
