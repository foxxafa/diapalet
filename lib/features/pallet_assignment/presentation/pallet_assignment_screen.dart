import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:diapalet/features/pallet_assignment/data/mock_pallet_service.dart';
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';

enum Mode { palet, kutu }

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  Mode selectedMode = Mode.palet;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Raf Ayarla'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FormBuilder(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Palet / Kutu Seçimi
                Center(
                  child: SegmentedButton<Mode>(
                    segments: const [
                      ButtonSegment(value: Mode.palet, label: Text('Palet')),
                      ButtonSegment(value: Mode.kutu, label: Text('Kutu')),
                    ],
                    selected: {selectedMode},
                    onSelectionChanged: (val) => setState(() => selectedMode = val.first),
                    style: SegmentedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                      selectedForegroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Dropdown + QR
                _buildWithQr(
                  FormBuilderDropdown<String>(
                    name: 'pallet',
                    decoration: InputDecoration(
                      labelText: selectedMode == Mode.palet ? 'Palet Seç' : 'Kutu Seç',
                    ),
                    items: _pallets.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                _buildHarmonizedField(
                  FormBuilderTextField(
                    name: 'quantity',
                    decoration: const InputDecoration(labelText: 'Miktar'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: 16),

                _buildHarmonizedField(
                  FormBuilderTextField(
                    name: 'corridor',
                    decoration: const InputDecoration(labelText: 'KORİDOR'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: 16),

                _buildWithQr(
                  FormBuilderTextField(
                    name: 'shelf',
                    decoration: const InputDecoration(labelText: 'RAF'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: 16),

                _buildHarmonizedField(
                  FormBuilderTextField(
                    name: 'floor',
                    decoration: const InputDecoration(labelText: 'KAT'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: 24),

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
                      Divider(),
                      _ProductRow(name: 'Gofret', quantity: '50x'),
                      Divider(),
                      _ProductRow(name: 'Sucuk', quantity: '100x'),
                      Divider(),
                      _ProductRow(name: 'Bal', quantity: '23x'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Kaydet Butonu
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_formKey.currentState?.saveAndValidate() ?? false) {
                        debugPrint(_formKey.currentState!.value.toString());
                      }
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Kaydet ve Onayla'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWithQr(Widget field) {
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 12),
        _QrButton(onTap: () {
          // TODO: QR kamera aç
        }),
      ],
    );
  }

  Widget _buildHarmonizedField(Widget field) {
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 60), // QR buton kadar boşluk bırakarak hizalama
      ],
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
  final String name;
  final String quantity;
  const _ProductRow({required this.name, required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name),
          Text(quantity),
        ],
      ),
    );
  }
}
