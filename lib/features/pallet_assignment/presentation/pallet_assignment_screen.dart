// lib/features/pallet_assignment/presentation/pallet_assignment_screen.dart
import 'package:diapalet/features/pallet_assignment/domain/repositories/pallet_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Corrected entity and repository imports using your project name 'diapalet'
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/core/widgets/qr_scanner_screen.dart'; // Assuming 'diapalet'


class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late PalletAssignmentRepository _repo;
  bool _isRepoInitialized = false;
  bool _isLoadingInitialData = true;
  bool _isLoadingContainerContents = false;
  bool _isSaving = false;

  AssignmentMode _selectedMode = AssignmentMode.palet;

  List<String> _availableSourceLocations = [];
  String? _selectedSourceLocation;
  final TextEditingController _sourceLocationController = TextEditingController();

  List<String> _availableContainerIds = [];
  bool _isLoadingContainerIds = false;
  Map<String, String> _boxIdToName = {}; // boxId -> product name mapping

  final TextEditingController _scannedContainerIdController = TextEditingController();
  List<ProductItem> _productsInContainer = [];
  final TextEditingController _transferQuantityController = TextEditingController();

  List<String> _availableTargetLocations = [];
  String? _selectedTargetLocation;
  final TextEditingController _targetLocationController = TextEditingController();

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
    if (_scannedContainerIdController.text.isEmpty && _productsInContainer.isNotEmpty) {
      if (mounted) {
        setState(() {
          _productsInContainer = [];
          _transferQuantityController.clear();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repo = Provider.of<PalletAssignmentRepository>(context, listen: false);
      _loadInitialData();
      _isRepoInitialized = true;
    }
  }

  @override
  void dispose() {
    _scannedContainerIdController.removeListener(_onScannedIdChange);
    _scannedContainerIdController.dispose();
    _sourceLocationController.dispose();
    _targetLocationController.dispose();
    _transferQuantityController.dispose();
    super.dispose();
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
        _availableSourceLocations = List<String>.from(results[0]);
        _availableTargetLocations = List<String>.from(results[1]);
      });
      await _loadContainerIdsForLocation();
    } catch (e) {
      if (mounted) _showSnackBar("Veri yüklenirken hata: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingInitialData = false);
    }
  }

  Future<void> _loadContainerIdsForLocation() async {
    if (_selectedSourceLocation == null) {
      if (mounted) setState(() => _availableContainerIds = []);
      return;
    }
    setState(() => _isLoadingContainerIds = true);
    try {
      final ids = await _repo.getContainerIdsAtLocation(_selectedSourceLocation!, _selectedMode);
      Map<String, String> nameMap = {};
      if (_selectedMode == AssignmentMode.kutu) {
        for (final id in ids) {
          final contents = await _repo.getContentsOfContainer(id, _selectedMode);
          if (contents.isNotEmpty) {
            nameMap[id] = contents.first.name;
          }
        }
      }
      if (mounted) {
        setState(() {
          _availableContainerIds = ids;
          _boxIdToName = nameMap;
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar("ID'ler yüklenemedi: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingContainerIds = false);
    }
  }

  Future<void> _fetchContainerContents() async {
    FocusScope.of(context).unfocus();
    final containerId = _scannedContainerIdController.text.trim();
    if (containerId.isEmpty) {
      _showSnackBar("${_selectedMode.displayName} ID boş olamaz.", isError: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingContainerContents = true;
      _productsInContainer = [];
    });
    try {
      // Ensure _selectedMode is passed correctly
      final contents = await _repo.getContentsOfContainer(containerId, _selectedMode);
      if (!mounted) return;
      setState(() {
        _productsInContainer = contents;
        if (_selectedMode == AssignmentMode.kutu && contents.isNotEmpty) {
          _transferQuantityController.text = contents.first.currentQuantity.toString();
        } else {
          _transferQuantityController.clear();
        }
        if (contents.isEmpty && containerId.isNotEmpty) {
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
    _formKey.currentState?.reset();
    _scannedContainerIdController.clear();
    if (mounted) {
      setState(() {
        _productsInContainer = [];
        _transferQuantityController.clear();
        if (resetAll) {
          _selectedMode = AssignmentMode.palet;
          _selectedSourceLocation = null;
          _sourceLocationController.clear();
          _selectedTargetLocation = null;
          _targetLocationController.clear();
          _availableContainerIds = [];
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
      String successMessage = "";
      bool found = false;
      if (fieldIdentifier == 'source') {
        if (_availableSourceLocations.contains(result)) {
          setState(() {
            _selectedSourceLocation = result;
            _sourceLocationController.text = result;
            _scannedContainerIdController.clear();
          });
          successMessage = "Kaynak QR ile seçildi: $result";
          found = true;
          await _loadContainerIdsForLocation();
        } else {
          _showSnackBar("Taranan QR ($result) geçerli bir Kaynak Lokasyonu değil.", isError: true);
        }
      } else if (fieldIdentifier == 'scannedId') {
        setState(() {
          _scannedContainerIdController.text = result;
        });
        successMessage = "${_selectedMode.displayName} ID QR ile okundu: $result";
        found = true;
        await _fetchContainerContents();
      } else if (fieldIdentifier == 'target') {
        if (_availableTargetLocations.contains(result)) {
          setState(() {
            _selectedTargetLocation = result;
            _targetLocationController.text = result;
          });
          successMessage = "Hedef QR ile seçildi: $result";
          found = true;
        } else {
          _showSnackBar("Taranan QR ($result) geçerli bir Hedef Lokasyonu değil.", isError: true);
        }
      }
      if (found && successMessage.isNotEmpty) _showSnackBar(successMessage);
      _formKey.currentState?.validate();
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar("Lütfen tüm zorunlu alanları doldurun ve hataları düzeltin.", isError: true);
      return;
    }

    List<TransferItemDetail> itemsToTransferDetails;
    if (_selectedMode == AssignmentMode.kutu) {
      if (_productsInContainer.isEmpty) {
        _showSnackBar("Kaynak ${_selectedMode.displayName} için ürün bulunamadı.", isError: true);
        return;
      }
      final product = _productsInContainer.first; // Kutu modunda listede tek ürün olmalı
      final qty = int.tryParse(_transferQuantityController.text) ?? 0;

      // Transfer edilecek miktar sıfırdan büyük olmalı
      if (qty <= 0) {
        _showSnackBar("Transfer miktarı 0'dan büyük olmalıdır.", isError: true);
        return;
      }
      // Transfer edilecek miktar mevcut miktarı aşmamalı
      if (qty > product.currentQuantity) {
        _showSnackBar("Transfer miktarı mevcut miktarı (${product.currentQuantity}) aşamaz.", isError: true);
        return;
      }

      itemsToTransferDetails = [
        TransferItemDetail(
          operationId: 0,
          productId: product.id, // ProductItem'ın 'id' alanı productId'yi temsil eder
          productCode: product.productCode,
          productName: product.name,
          quantity: qty,
        )
      ];
    } else { // Palet modu
      itemsToTransferDetails = _productsInContainer
          .map((p) => TransferItemDetail(
        operationId: 0,
        productId: p.id, // ProductItem'ın 'id' alanı productId'yi temsil eder
        productCode: p.productCode,
        productName: p.name,
        quantity: p.currentQuantity,
      ))
          .toList();
    }

    if (itemsToTransferDetails.isEmpty) {
      _showSnackBar("Kaynak ${_selectedMode.displayName} için transfer edilecek ürün bulunamadı.", isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      final header = TransferOperationHeader(
        operationType: _selectedMode,
        sourceLocation: _selectedSourceLocation!,
        containerId: _scannedContainerIdController.text,
        targetLocation: _selectedTargetLocation!,
        transferDate: DateTime.now(),
      );

      await _repo.recordTransferOperation(header, itemsToTransferDetails);

      if (mounted) {
        String msg;
        if (_selectedMode == AssignmentMode.kutu && _productsInContainer.isNotEmpty) {
          msg = "${_productsInContainer.first.name} kutu transferi kaydedildi";
        } else {
          msg = "${_selectedMode.displayName} transferi başarıyla kaydedildi!";
        }
        _showSnackBar(msg);
        _resetForm(resetAll: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar("Kaydetme sırasında hata: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
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
      fillColor: filled ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: (_fieldHeight - 24) / 2),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(fontSize: 0, height: 0.01),
      helperText: ' ',
      helperStyle: const TextStyle(fontSize: 0, height: 0.01),
    );
  }


  Future<T?> _showSearchableDropdownDialog<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T) itemToString,
    required bool Function(T, String) filterCondition,
    T? initialValue,
  }) async {
    return showDialog<T>(
      context: context,
      builder: (BuildContext dialogContext) {
        String searchText = '';
        List<T> filteredItems = List.from(items);

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            if (searchText.isNotEmpty) {
              filteredItems = items.where((item) => filterCondition(item, searchText)).toList();
            } else {
              filteredItems = List.from(items);
            }

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
                          ? const Center(child: Text("Sonuç bulunamadı"))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredItems.length,
                        itemBuilder: (BuildContext context, int index) {
                          final item = filteredItems[index];
                          return ListTile(
                            title: Text(itemToString(item)),
                            onTap: () {
                              Navigator.of(dialogContext).pop(item);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('İptal'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeSelector(),
                const SizedBox(height: _gap),
                _buildSearchableDropdownWithQr(
                    controller: _sourceLocationController,
                    label: 'Kaynak Lokasyon Seç',
                    value: _selectedSourceLocation,
                    items: _availableSourceLocations,
                    onSelected: (val) {
                      if (mounted) {
                        setState(() {
                          _selectedSourceLocation = val;
                          _sourceLocationController.text = val ?? "";
                          _scannedContainerIdController.clear();
                        });
                        _loadContainerIdsForLocation();
                      }
                    },
                    onQrTap: () => _scanQrAndUpdateField('source'),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Kaynak lokasyon seçimi zorunludur.';
                      return null;
                    }
                ),
                const SizedBox(height: _gap),
                _buildScannedIdSection(),
                if (_isLoadingContainerIds)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: _smallGap),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: _smallGap),
                if (_isLoadingContainerContents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: _gap),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!_isLoadingContainerContents && _productsInContainer.isNotEmpty)
                        Expanded(child: _buildProductsList())
                      else if (!_isLoadingContainerContents && _scannedContainerIdController.text.isNotEmpty && !_isLoadingInitialData)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: _gap),
                            child: Center(child: Text("${_scannedContainerIdController.text} ID'li ${_selectedMode.displayName} için ürün bulunamadı veya ID henüz getirilmedi.", textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor))),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(height: _gap),
                      _buildSearchableDropdownWithQr(
                          controller: _targetLocationController,
                          label: 'Hedef Lokasyon Seç',
                          value: _selectedTargetLocation,
                          items: _availableTargetLocations,
                          onSelected: (val) {
                            if (mounted) {
                              setState(() {
                                _selectedTargetLocation = val;
                                _targetLocationController.text = val ?? "";
                              });
                            }
                          },
                          onQrTap: () => _scanQrAndUpdateField('target'),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Hedef lokasyon seçimi zorunludur.';
                            return null;
                          }
                      ),
                    ],
                  ),
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
              _transferQuantityController.clear();
              _formKey.currentState?.reset();
            });
            _loadContainerIdsForLocation();
          }
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
          selectedBackgroundColor: Theme.of(context).colorScheme.primary,
          selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: _borderRadius),
        ),
      ),
    );
  }

  Widget _buildSearchableDropdownWithQr({
    required TextEditingController controller,
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onSelected,
    String Function(String)? itemLabelBuilder,
    bool Function(String, String)? filterFn,
    required VoidCallback onQrTap,
    required FormFieldValidator<String>? validator,
  }) {
    return SizedBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              readOnly: true,
              decoration: _inputDecoration(label, filled: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
              onTap: () async {
                final String? selected = await _showSearchableDropdownDialog<String>(
                  context: context,
                  title: label,
                  items: items,
                  itemToString: (item) => itemLabelBuilder != null ? itemLabelBuilder(item) : item,
                  filterCondition: (item, query) => filterFn != null
                      ? filterFn(item, query)
                      : item.toLowerCase().contains(query.toLowerCase()),
                  initialValue: value,
                );
                onSelected(selected);
              },
              validator: validator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ),
          const SizedBox(width: _smallGap),
          _QrButton(onTap: onQrTap, size: _fieldHeight),
        ],
      ),
    );
  }

  Widget _buildScannedIdSection() {
    return _buildSearchableDropdownWithQr(
      controller: _scannedContainerIdController,
      label: '${_selectedMode.displayName} ID Seç',
      value: _scannedContainerIdController.text.isEmpty ? null : _scannedContainerIdController.text,
      items: _availableContainerIds,
      itemLabelBuilder: (id) =>
          _selectedMode == AssignmentMode.kutu ? (_boxIdToName[id] ?? id) : id,
      filterFn: (id, query) {
        final label = _selectedMode == AssignmentMode.kutu ? (_boxIdToName[id] ?? id) : id;
        return label.toLowerCase().contains(query.toLowerCase());
      },
      onSelected: (val) async {
        if (mounted) {
          setState(() {
            _scannedContainerIdController.text = val ?? '';
          });
          if (val != null) await _fetchContainerContents();
        }
      },
      onQrTap: () => _scanQrAndUpdateField('scannedId'),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '${_selectedMode.displayName} ID boş olamaz.';
        }
        return null;
      },
    );
  }

  Widget _buildProductsList() {
    final bool isBox = _selectedMode == AssignmentMode.kutu;
    final ProductItem? boxProduct = isBox && _productsInContainer.isNotEmpty ? _productsInContainer.first : null;

    return Container(
      margin: const EdgeInsets.only(top: _smallGap),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha((255 * 0.5).round())),
        borderRadius: _borderRadius,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha((255 * 0.2).round()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(_smallGap),
            child: Text(
              isBox
                  ? "${_scannedContainerIdController.text} İçeriği:"
                  : "${_scannedContainerIdController.text} İçeriği (${_productsInContainer.length} ürün):",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Flexible(
            child: _productsInContainer.isEmpty
                ? Padding(
              padding: const EdgeInsets.all(_gap),
              child: Center(
                  child: Text("${_selectedMode.displayName} içeriği boş.",
                      style: TextStyle(color: Theme.of(context).hintColor))),
            )
                : isBox && boxProduct != null
                ? Padding(
              padding: const EdgeInsets.all(_smallGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, // Ensure Column takes minimum space
                      children: [
                        Text(boxProduct.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w500)),
                        Text("Mevcut: ${boxProduct.currentQuantity}",
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: _smallGap),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller: _transferQuantityController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('Miktar', filled: true),
                      validator: (value) {
                        if (!isBox) return null;
                        if (value == null || value.isEmpty) {
                          return 'Miktar gerekli';
                        }
                        final qty = int.tryParse(value);
                        if (qty == null) return 'Geçersiz';
                        if (qty <= 0) return 'Miktar > 0 olmalı';
                        if (boxProduct.currentQuantity < qty ) { // Check against the current quantity of the product in the box
                          return 'En fazla ${boxProduct.currentQuantity}';
                        }
                        return null;
                      },
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
            )
                : ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: _smallGap),
              itemCount: _productsInContainer.length,
              separatorBuilder: (context, index) => const Divider(
                  height: 1, indent: 16, endIndent: 16, thickness: 0.5),
              itemBuilder: (context, index) {
                final product = _productsInContainer[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: _smallGap, vertical: _smallGap / 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w500)),
                            Text("Miktar: ${product.currentQuantity}",
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
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
  const _QrButton({required this.onTap, required this.size});


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
