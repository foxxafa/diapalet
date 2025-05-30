import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:diapalet/features/pallet_assignment/data/mock_pallet_service.dart';
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  String selectedMode = 'Palet';

  late final PalletRepository _repo;
  late final List<String> _pallets;

  @override
  void initState() {
    super.initState();
    _repo = MockPalletService();
    _pallets = _repo.getPalletList();
  }

  @override
  Widget build(BuildContext context) {
    // Tema renklerine ulaşmak
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Raf Ayarla'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FormBuilder(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Toggle
              Center(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Palet'),
                      selected: selectedMode == 'Palet',
                      onSelected: (_) => setState(() => selectedMode = 'Palet'),
                    ),
                    ChoiceChip(
                      label: const Text('Kutu'),
                      selected: selectedMode == 'Kutu',
                      onSelected: (_) => setState(() => selectedMode = 'Kutu'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Palet/Kutu + QR
              Row(children: [
                Expanded(
                  child: FormBuilderDropdown<String>(
                    name: 'pallet',
                    decoration: InputDecoration(
                      labelText: selectedMode == 'Palet' ? 'Palet Seç' : 'Kutu Seç',
                    ),
                    items: _pallets.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  ),
                ),
                const SizedBox(width: 12),
                _QrButton(onTap: () {/* TODO: Kamera aç */}),
              ]),
              const SizedBox(height: 24),

              // Miktar
              FormBuilderTextField(
                name: 'quantity',
                decoration: const InputDecoration(labelText: 'Miktar'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),

              // Koridor (QR yok)
              FormBuilderTextField(
                name: 'corridor',
                decoration: const InputDecoration(labelText: 'KORİDOR'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),

              // Raf + QR
              Row(children: [
                Expanded(
                  child: FormBuilderTextField(
                    name: 'shelf',
                    decoration: const InputDecoration(labelText: 'RAF'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                _QrButton(onTap: () {/* TODO: Kamera aç */}),
              ]),
              const SizedBox(height: 24),

              // Kat (QR yok)
              FormBuilderTextField(
                name: 'floor',
                decoration: const InputDecoration(labelText: 'KAT'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),

              // Ürün Kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paletteki Ürünler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    SizedBox(height: 12),
                    Divider(height: 1),
                    _ProductRow(name: 'Gofret', quantity: '50x'),
                    Divider(height: 1),
                    _ProductRow(name: 'Sucuk', quantity: '100x'),
                    Divider(height: 1),
                    _ProductRow(name: 'Bal', quantity: '23x'),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Kaydet Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_formKey.currentState?.saveAndValidate() ?? false) {
                      debugPrint(_formKey.currentState!.value.toString());
                    }
                  },
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Kaydet ve Onayla', style: TextStyle(color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QrButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.qr_code_scanner, size: 28),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final String name, quantity;
  const _ProductRow({required this.name, required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(name),
        Text(quantity),
      ]),
    );
  }
}
