// File: features/pallet_assignment/presentation/pallet_assignment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:provider/provider.dart';

// Imports PalletRepository, ProductItem, AND Mode from the domain layer
import '../domain/pallet_repository.dart';

// The local enum Mode definition has been REMOVED from this file.

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  Mode _selectedMode = Mode.palet; // Now uses Mode from domain

  late PalletRepository _repo;
  bool _isRepoInitialized = false;

  List<String> _options = [];
  String? _selectedOption;
  List<ProductItem> _products = [];
  bool _isLoading = true;
  bool _isSaving = false;

  final _borderRadius = BorderRadius.circular(12.0);
  static const double _gap = 8.0;
  static const double _fieldHeight = 56.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isRepoInitialized) {
      _repo = Provider.of<PalletRepository>(context, listen: false);
      _initializeData();
      _isRepoInitialized = true;
    }
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    await Future.delayed(Duration.zero);
    _refreshOptions();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _refreshOptions() {
    if (_selectedMode == Mode.palet) {
      _options = _repo.getPalletList();
      _selectedOption = _options.isNotEmpty ? _options.first : null;
      _products = _selectedOption != null ? _repo.getPalletProducts(_selectedOption!) : [];
    } else {
      _options = _repo.getBoxList();
      _selectedOption = _options.isNotEmpty ? _options.first : null;
      _products = _selectedOption != null ? _repo.getBoxProducts(_selectedOption!) : [];
    }
    if (_formKey.currentState != null) {
      _formKey.currentState!.patchValue({'option': _selectedOption});
      // Also clear other fields when mode or main option changes
      _formKey.currentState!.patchValue({
        'quantity': null,
        'corridor': null,
        'shelf': null,
        'floor': null,
      });
    }
  }

  Future<void> _onConfirmSave() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSaving = true);
      final formData = Map<String, dynamic>.from(_formKey.currentState!.value);
      try {
        await _repo.saveAssignment(formData, _selectedMode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_selectedMode == Mode.palet ? "Palet" : "Kutu"} bilgileri başarıyla kaydedildi!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
          // Optionally reset form or navigate
          _formKey.currentState?.reset();
          _refreshOptions(); // To reset dropdown and product list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kaydetme sırasında hata: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if(mounted){
          setState(() => _isSaving = false);
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen gerekli tüm alanları doldurun! Formda hatalar var.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }
  }

  InputDecoration _inputDecoration(String labelText, {Widget? suffixIcon}) {
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
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      errorStyle: const TextStyle(fontSize: 0, height: 0.01), // Makes error text take no space
    );
  }


  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double bottomNavHeight = (screenHeight * 0.09).clamp(70.0, 90.0);
    final double qrButtonSize = (screenWidth * 0.13).clamp(48.0, _fieldHeight);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Raf Ayarla'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raf Ayarla'),
        centerTitle: true,
      ),
      // resizeToAvoidBottomInset: true, // Can be true
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(bottom: 8.0, left: 20.0, right: 20.0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _onConfirmSave,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: _borderRadius),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView( // Wrap with SingleChildScrollView
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), // Added bottom padding for scroll
            child: FormBuilder(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: SegmentedButton<Mode>(
                      segments: const [
                        ButtonSegment(value: Mode.palet, label: Text('Palet')),
                        ButtonSegment(value: Mode.kutu, label: Text('Kutu')),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (val) => setState(() {
                        _selectedMode = val.first;
                        _refreshOptions();
                      }),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                        selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: _borderRadius),
                      ),
                    ),
                  ),
                  const SizedBox(height: _gap * 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FormBuilderDropdown<String>(
                          name: 'option',
                          initialValue: _selectedOption,
                          decoration: _inputDecoration(
                            _selectedMode == Mode.palet ? 'Palet Seç' : 'Kutu Seç',
                          ),
                          items: _options.isEmpty
                              ? [DropdownMenuItem(value: null, child: Text(_selectedMode == Mode.palet ? 'Palet Yok' : 'Kutu Yok', style: const TextStyle(color: Colors.grey)))]
                              : _options.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _options.isEmpty ? null : (val) {
                            if (val == null) return;
                            setState(() {
                              _selectedOption = val;
                              _products = _selectedMode == Mode.palet
                                  ? _repo.getPalletProducts(val)
                                  : _repo.getBoxProducts(val);
                            });
                          },
                          validator: FormBuilderValidators.required(errorText: "Lütfen bir seçim yapın."),
                          isExpanded: true,
                        ),
                      ),
                      const SizedBox(width: _gap),
                      SizedBox(
                        width: qrButtonSize,
                        height: _fieldHeight,
                        child: _QrButton(
                          onTap: () {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedMode == Mode.palet ? "Palet" : "Kutu"} QR okuyucu açılacak.')));
                            }
                          },
                          size: qrButtonSize,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: _gap * 1.5),
                  _buildTextFieldRow('quantity', 'Miktar', TextInputType.number, FormBuilderValidators.compose([
                    FormBuilderValidators.required(errorText: "Miktar boş olamaz."),
                    FormBuilderValidators.integer(errorText: "Lütfen geçerli bir sayı girin."),
                    FormBuilderValidators.min(1, errorText: "Miktar en az 1 olmalı."),
                  ]), qrButtonSize),
                  const SizedBox(height: _gap * 1.5),
                  _buildTextFieldRow('corridor', 'Koridor', TextInputType.text, FormBuilderValidators.required(errorText: "Koridor boş olamaz."), qrButtonSize),
                  const SizedBox(height: _gap * 1.5),
                  _buildTextFieldRow('shelf', 'Raf', TextInputType.text, FormBuilderValidators.required(errorText: "Raf boş olamaz."), qrButtonSize, hasQr: true),
                  const SizedBox(height: _gap * 1.5),
                  _buildTextFieldRow('floor', 'Kat', TextInputType.text, FormBuilderValidators.required(errorText: "Kat boş olamaz."), qrButtonSize),
                  const SizedBox(height: _gap * 2.5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: _gap),
                    child: Text(
                      _selectedMode == Mode.palet ? 'Paletteki Ürünler' : 'Kutudaki Ürünler',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Constrain the height of the product list or make it non-scrollable
                  // if the parent SingleChildScrollView is handling the scroll.
                  Container(
                    height: 150, // Example fixed height, adjust as needed
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: _borderRadius,
                        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5))
                    ),
                    child: _products.isEmpty
                        ? Center(
                      child: Padding( // Added padding for better spacing
                        padding: const EdgeInsets.all(_gap),
                        child: Text(
                          '${_selectedOption ?? (_selectedMode == Mode.palet ? "Seçili palet" : "Seçili kutu")} için ürün bulunmuyor.',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                        : ListView.separated(
                      // shrinkWrap: true, // Use if height is not constrained and you want it to take minimum space
                      // physics: const NeverScrollableScrollPhysics(), // Use with shrinkWrap if parent scrolls
                      padding: const EdgeInsets.symmetric(vertical: _gap / 2),
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: Theme.of(context).dividerColor.withOpacity(0.5)),
                      itemBuilder: (context, index) {
                        final item = _products[index];
                        return ListTile(
                          title: Text(item.name, style: Theme.of(context).textTheme.bodyLarge),
                          trailing: Text(
                            '${item.quantity}x',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: _gap), // Space at the bottom
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldRow(String name, String label, TextInputType inputType, FormFieldValidator<String>? validator, double qrButtonSize, {bool hasQr = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Align to top for consistent appearance with/without error
      children: [
        Expanded(
          child: FormBuilderTextField(
            name: name,
            decoration: _inputDecoration(label),
            keyboardType: inputType,
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ),
        const SizedBox(width: _gap),
        SizedBox(
          width: qrButtonSize,
          height: _fieldHeight,
          child: hasQr ? _QrButton(
            onTap: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label QR okuyucu açılacak.')));
              }
            },
            size: qrButtonSize,
          ) : SizedBox(width: qrButtonSize), // Keep space consistent if no QR button
        ),
      ],
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const _QrButton({required this.onTap, required this.size}); // Removed super.key for brevity

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size, // Make it a square based on the smaller of _fieldHeight and calculated size
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: onTap,
          child: Center(
            child: Icon(
              Icons.qr_code_scanner,
              size: size * 0.6,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
