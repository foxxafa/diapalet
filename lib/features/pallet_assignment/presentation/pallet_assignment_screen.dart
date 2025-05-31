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
  // _fieldHeight is now primarily for elements that need a fixed height, like QR buttons
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
    // Simulate async loading if necessary for repo methods
    await Future.delayed(Duration.zero); // Ensure build happens after state change
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
    // If form is already built, update its field
    if (_formKey.currentState != null) {
      _formKey.currentState!.patchValue({'option': _selectedOption});
    }
  }

  Future<void> _onConfirmSave() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() => _isSaving = true);
      final formData = Map<String, dynamic>.from(_formKey.currentState!.value);
      try {
        // _selectedMode is now the Mode from the domain layer
        await _repo.saveAssignment(formData, _selectedMode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_selectedMode == Mode.palet ? "Palet" : "Kutu"} bilgileri başarıyla kaydedildi!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
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
            content: Text('Lütfen gerekli tüm alanları doldurun! Formda hatalar var.'), // Updated message
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
      // Explicitly define errorBorder
      errorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
      ),
      // Explicitly define focusedErrorBorder for consistency when error field is focused
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _borderRadius,
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2.0),
      ),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      suffixIcon: suffixIcon,
      // Remove helperText and helperStyle that reserved space for error text
      // Make error text itself invisible and take no vertical space
      errorStyle: const TextStyle(fontSize: 0, height: 0.01),
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
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(bottom: 8.0, left: 20.0, right: 20.0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        height: bottomNavHeight,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _onConfirmSave,
          icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: FormBuilder(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SegmentedButton<Mode>( // Uses Mode from domain
                    segments: const [
                      ButtonSegment(value: Mode.palet, label: Text('Palet')),
                      ButtonSegment(value: Mode.kutu, label: Text('Kutu')),
                    ],
                    selected: {_selectedMode},
                    onSelectionChanged: (val) => setState(() {
                      _selectedMode = val.first;
                      _refreshOptions();
                      _formKey.currentState?.patchValue({'option': _selectedOption});
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
                        validator: FormBuilderValidators.required(errorText: "Lütfen bir seçim yapın."), // Validator still provides error string internally
                        isExpanded: true,
                      ),
                    ),
                    const SizedBox(width: _gap),
                    SizedBox(
                      width: qrButtonSize,
                      height: _fieldHeight, // QR button maintains fixed height
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
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: _borderRadius,
                        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5))
                    ),
                    child: _products.isEmpty
                        ? Center(
                      child: Text(
                        '${_selectedOption ?? (_selectedMode == Mode.palet ? "Seçili palet" : "Seçili kutu")} için ürün bulunmuyor.',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                        textAlign: TextAlign.center,
                      ),
                    )
                        : ListView.separated(
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
                ),
                const SizedBox(height: _gap),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldRow(String name, String label, TextInputType inputType, FormFieldValidator<String>? validator, double qrButtonSize, {bool hasQr = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FormBuilderTextField(
            name: name,
            decoration: _inputDecoration(label),
            keyboardType: inputType,
            validator: validator, // Validator still provides error string internally
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ),
        const SizedBox(width: _gap),
        SizedBox(
          width: qrButtonSize,
          height: _fieldHeight, // QR button maintains fixed height
          child: hasQr ? _QrButton(
            onTap: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label QR okuyucu açılacak.')));
              }
            },
            size: qrButtonSize,
          ) : null,
        ),
      ],
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const _QrButton({required this.onTap, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
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
