// features/pallet_assignment/presentation/pallet_assignment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter
import 'package:provider/provider.dart';
import '../domain/pallet_repository.dart';
import '../../../core/widgets/qr_scanner_screen.dart';

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late PalletRepository _repo;
  bool _isRepoInitialized = false;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;

  AssignmentMode _selectedMode = AssignmentMode.palet;

  List<String> _availableSourceLocations = [];
  String? _selectedSourceLocation;

  final TextEditingController _scannedContainerIdController = TextEditingController();
  List<ProductItem> _productsInContainer = [];
  // Map to store quantity controllers for each product in the list
  Map<String, TextEditingController> _quantityControllers = {};
  Map<String, FocusNode> _quantityFocusNodes = {};


  List<String> _availableTargetLocations = [];
  String? _selectedTargetLocation;

  static const double _fieldHeight = 56.0;
  static const double _gap = 16.0;
  static const double _smallGap = 8.0;
  final _borderRadius = BorderRadius.circular(12.0);

  @override
  void initState() {
    super.initState();
    _scannedContainerIdController.addListener(_onScannedIdChange);
  }

  void _onScannedIdChange() {
    // Clear previous products if ID changes
    if (_scannedContainerIdController.text.isEmpty && _productsInContainer.isNotEmpty) {
      if (mounted) {
        setState(() {
          _productsInContainer = [];
          _clearQuantityControllers();
        });
      }
    }
    // Optionally, auto-fetch if ID is of a certain length or format,
    // or rely on a separate button/action. For now, manual fetch via button/enter.
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repo = Provider.of<PalletRepository>(context, listen: false);
      _loadInitialData();
      _isRepoInitialized = true;
    }
  }

  @override
  void dispose() {
    _scannedContainerIdController.removeListener(_onScannedIdChange);
    _scannedContainerIdController.dispose();
    _clearQuantityControllers(disposeNodes: true);
    super.dispose();
  }

  void _clearQuantityControllers({bool disposeNodes = false}) {
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    if (disposeNodes) {
      for (var node in _quantityFocusNodes.values) {
        node.dispose();
      }
      _quantityFocusNodes.clear();
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoadingInitialData = true);
    try {
      final results = await Future.wait([
        _repo.getSourceLocations(),
        _repo.getTargetLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _availableSourceLocations = results[0];
        _availableTargetLocations = results[1];
        _selectedSourceLocation = _availableSourceLocations.isNotEmpty ? _availableSourceLocations.first : null;
        _selectedTargetLocation = _availableTargetLocations.isNotEmpty ? _availableTargetLocations.first : null;
      });
    } catch (e) {
      if (mounted) _showSnackBar("Veri yüklenirken hata: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _fetchContainerContents() async {
    FocusScope.of(context).unfocus(); // Klavyeyi kapat
    final containerId = _scannedContainerIdController.text.trim();
    if (containerId.isEmpty) {
      _showSnackBar("${_selectedMode.displayName} ID boş olamaz.", isError: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = []; // Önceki ürünleri temizle
      _clearQuantityControllers();
    });
    try {
      final contents = await _repo.getContentsOfContainer(containerId, _selectedMode);
      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        // Create new controllers for the new products
        for (var product in _productsInContainer) {
          _quantityControllers[product.id] = TextEditingController();
          _quantityFocusNodes[product.id] = FocusNode();
        }
        if (contents.isEmpty) {
          _showSnackBar("$containerId ID'li ${_selectedMode.displayName} bulunamadı veya içi boş.", isError: true);
        }
      });
    } catch (e) {
      if (mounted) _showSnackBar("İçerik yüklenirken hata: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingContainerContents = false);
    }
  }


  void _resetForm({bool resetAll = true}) {
    _formKey.currentState?.reset(); // Formun kendi içindeki alanları sıfırlar (varsa)
    _scannedContainerIdController.clear();
    _clearQuantityControllers();
    if (mounted) {
      setState(() {
        _productsInContainer = [];
        if (resetAll) {
          _selectedMode = AssignmentMode.palet;
          _selectedSourceLocation = _availableSourceLocations.isNotEmpty ? _availableSourceLocations.first : null;
          _selectedTargetLocation = _availableTargetLocations.isNotEmpty ? _availableTargetLocations.first : null;
        }
      });
    }
  }

  Future<void> _scanQrAndUpdateField(String fieldIdentifier) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        bool showSuccess = true;
        String message = "";
        if (fieldIdentifier == 'source') {
          if (_availableSourceLocations.contains(result)) {
            _selectedSourceLocation = result;
            message = "Kaynak QR ile seçildi: $result";
          } else {
            message = "Taranan QR ($result) geçerli bir Kaynak Lokasyonu değil."; showSuccess = false;
          }
        } else if (fieldIdentifier == 'scannedId') {
          _scannedContainerIdController.text = result;
          message = "${_selectedMode.displayName} ID QR ile okundu: $result";
          // ID okunduktan sonra otomatik içerik yükleme
          _fetchContainerContents();
        } else if (fieldIdentifier == 'target') {
          if (_availableTargetLocations.contains(result)) {
            _selectedTargetLocation = result;
            message = "Hedef QR ile seçildi: $result";
          } else {
            message = "Taranan QR ($result) geçerli bir Hedef Lokasyonu değil."; showSuccess = false;
          }
        }
        _showSnackBar(message, isError: !showSuccess);
      });
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar("Lütfen tüm zorunlu alanları doldurun.", isError: true);
      return;
    }

    List<TransferItem> itemsToTransfer = [];
    bool validationError = false;
    for (var product in _productsInContainer) {
      final controller = _quantityControllers[product.id];
      if (controller != null && controller.text.isNotEmpty) {
        final quantity = int.tryParse(controller.text);
        if (quantity == null || quantity < 0) {
          _showSnackBar("${product.name} için geçersiz miktar.", isError: true);
          validationError = true;
          _quantityFocusNodes[product.id]?.requestFocus();
          break;
        }
        if (quantity > product.currentQuantity) {
          _showSnackBar("${product.name} için transfer miktarı (${quantity}) mevcut miktarı (${product.currentQuantity}) aşamaz.", isError: true);
          validationError = true;
          _quantityFocusNodes[product.id]?.requestFocus();
          break;
        }
        if (quantity > 0) {
          itemsToTransfer.add(TransferItem(
            productId: product.id,
            productName: product.name,
            quantityToTransfer: quantity,
          ));
        }
      }
    }

    if (validationError) return;

    if (itemsToTransfer.isEmpty) {
      _showSnackBar("Transfer edilecek ürün miktarı girilmedi.", isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      await _repo.recordTransfer(
        mode: _selectedMode,
        sourceLocation: _selectedSourceLocation,
        containerId: _scannedContainerIdController.text,
        targetLocation: _selectedTargetLocation,
        transferredItems: itemsToTransfer,
      );
      if (mounted) {
        _showSnackBar("${_selectedMode.displayName} transferi başarıyla kaydedildi!");
        _resetForm(resetAll: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar("Kaydetme sırasında hata: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Önceki snackbar'ı kaldır
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _inputDecoration(String labelText, {Widget? suffixIcon, bool filled = false}) {
    return InputDecoration(
      labelText: labelText,
      border: OutlineInputBorder(borderRadius: _borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2.0),
      ),
      filled: filled,
      fillColor: filled ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : null,
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
        title: const Text('Palet/Kutu Taşıma'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: _isLoadingInitialData || _isSaving
          ? null
          : Container(
        margin: const EdgeInsets.all(20).copyWith(top:0),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _onConfirmSave,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_alt_outlined),
          label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoadingInitialData
            ? const Center(child: CircularProgressIndicator())
            : Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column( // ListView yerine Column ve Expanded kullandık
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeSelector(),
                const SizedBox(height: _gap),
                _buildDropdownWithQr(
                  label: 'Kaynak Lokasyon Seç',
                  value: _selectedSourceLocation,
                  items: _availableSourceLocations,
                  onChanged: (val) {
                    if (mounted) setState(() => _selectedSourceLocation = val);
                  },
                  onQrTap: () => _scanQrAndUpdateField('source'),
                  validator: (val) => val == null ? 'Kaynak lokasyon seçin.' : null,
                ),
                const SizedBox(height: _gap),
                _buildScannedIdSection(),
                const SizedBox(height: _smallGap), // Fetch butonu için boşluk
                if (_scannedContainerIdController.text.isNotEmpty)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: Text("${_selectedMode.displayName} İçeriğini Getir"),
                    onPressed: _isLoadingContainerContents ? null : _fetchContainerContents,
                    style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, _fieldHeight * 0.8)),
                  ),
                if (_isLoadingContainerContents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: _smallGap),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_isLoadingContainerContents && _productsInContainer.isNotEmpty)
                  const SizedBox(height: _gap),
                if (!_isLoadingContainerContents && _productsInContainer.isNotEmpty)
                  Expanded(child: _buildProductsList()),
                if (!_isLoadingContainerContents && _productsInContainer.isEmpty && _scannedContainerIdController.text.isNotEmpty && !_isLoadingInitialData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: _gap),
                    child: Center(child: Text("${_scannedContainerIdController.text} ID'li ${_selectedMode.displayName} için ürün bulunamadı veya ID henüz getirilmedi.", textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor))),
                  ),
                const SizedBox(height: _gap),
                _buildDropdownWithQr(
                  label: 'Hedef Lokasyon Seç',
                  value: _selectedTargetLocation,
                  items: _availableTargetLocations,
                  onChanged: (val) {
                    if (mounted) setState(() => _selectedTargetLocation = val);
                  },
                  onQrTap: () => _scanQrAndUpdateField('target'),
                  validator: (val) => val == null ? 'Hedef lokasyon seçin.' : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<AssignmentMode>(
        segments: const [
          ButtonSegment(value: AssignmentMode.palet, label: Text('Palet'), icon: Icon(Icons.pallet)),
          ButtonSegment(value: AssignmentMode.kutu, label: Text('Kutu'), icon: Icon(Icons.inventory_2_outlined)),
        ],
        selected: {_selectedMode},
        onSelectionChanged: (Set<AssignmentMode> newSelection) {
          if (mounted) {
            setState(() {
              _selectedMode = newSelection.first;
              _scannedContainerIdController.clear();
              _productsInContainer = [];
              _clearQuantityControllers();
            });
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildDropdownWithQr({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required VoidCallback onQrTap,
    required FormFieldValidator<String>? validator,
  }) {
    return SizedBox(
      height: _fieldHeight, // Yüksekliği sabitledik
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Hizalama için
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              decoration: _inputDecoration(label, filled: true),
              value: value,
              isExpanded: true,
              hint: Text(label),
              items: items.map((String item) {
                return DropdownMenuItem<String>(value: item, child: Text(item, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: items.isEmpty ? null : onChanged, // Liste boşsa onChanged'i null yap
              validator: validator,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(onTap: onQrTap, size: _fieldHeight),
        ],
      ),
    );
  }

  Widget _buildScannedIdSection() {
    return SizedBox(
      height: _fieldHeight, // Yüksekliği sabitledik
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Hizalama için
        children: [
          Expanded(
            child: TextFormField(
              controller: _scannedContainerIdController,
              decoration: _inputDecoration('${_selectedMode.displayName} ID Okut/Yaz'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '${_selectedMode.displayName} ID boş olamaz.';
                }
                return null;
              },
              // Enter'a basıldığında içerik getirme
              onFieldSubmitted: (_) => _fetchContainerContents(),
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(
            onTap: () => _scanQrAndUpdateField('scannedId'),
            size: _fieldHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: _borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(_smallGap),
            child: Text(
              "${_scannedContainerIdController.text} İçeriği (${_productsInContainer.length} ürün):",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height:1),
          Expanded(
            child: ListView.separated(
              itemCount: _productsInContainer.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final product = _productsInContainer[index];
                _quantityControllers[product.id] ??= TextEditingController();
                _quantityFocusNodes[product.id] ??= FocusNode();


                return ListTile(
                  title: Text(product.name, style: Theme.of(context).textTheme.bodyLarge),
                  subtitle: Text('Mevcut: ${product.currentQuantity}'),
                  trailing: SizedBox(
                    width: 100, // Miktar alanı için genişlik
                    child: TextFormField(
                      controller: _quantityControllers[product.id],
                      focusNode: _quantityFocusNodes[product.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Miktar',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        errorStyle: const TextStyle(fontSize: 0, height: 0.01), // Hata mesajını gizle (SnackBar ile gösteriliyor)
                      ),
                      textAlign: TextAlign.center,
                      validator: (value) { // Bu validator _onConfirmSave içinde ayrıca kontrol ediliyor
                        if (value == null || value.isEmpty) return null; // Boşsa sorun yok, 0 kabul edilecek
                        final quantity = int.tryParse(value);
                        if (quantity == null) return 'Sayı!';
                        if (quantity < 0) return '>0!';
                        if (quantity > product.currentQuantity) return 'Max ${product.currentQuantity}!';
                        return null;
                      },
                      autovalidateMode: AutovalidateMode.onUserInteraction,
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
}

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
