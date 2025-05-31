import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:provider/provider.dart';
import '../domain/pallet_repository.dart';

enum Mode { palet, kutu }

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  Mode selectedMode = Mode.palet;

  late PalletRepository _repo;
  late List<String> _pallets;
  late String _selectedPallet;
  late List<ProductItem> _products;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = Provider.of<PalletRepository>(context, listen: false);
    _pallets = _repo.getPalletList();
    _selectedPallet = _pallets.first;
    _products = _repo.getPalletProducts(_selectedPallet);
  }

  void _onPalletChanged(String? val) {
    if (val == null) return;
    setState(() {
      _selectedPallet = val;
      _products = _repo.getPalletProducts(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double buttonHeight = screenHeight * 0.10;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raf Ayarla'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        height: buttonHeight,
        child: ElevatedButton.icon(
          onPressed: () {
            if (_formKey.currentState?.saveAndValidate() ?? false) {
              debugPrint(_formKey.currentState!.value.toString());
            }
          },
          icon: const Icon(Icons.check),
          label: const Text('Kaydet ve Onayla'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormBuilder(
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
                          selected: {selectedMode},
                          onSelectionChanged: (val) =>
                              setState(() => selectedMode = val.first),
                          style: SegmentedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                            selectedBackgroundColor:
                            Theme.of(context).colorScheme.primary,
                            selectedForegroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FormBuilderDropdown<String>(
                              name: 'pallet',
                              initialValue: _selectedPallet,
                              decoration: InputDecoration(
                                labelText: selectedMode == Mode.palet
                                    ? 'Palet Seç'
                                    : 'Kutu Seç',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: _pallets
                                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                  .toList(),
                              onChanged: _onPalletChanged,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: _QrButton(onTap: () {}),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FormBuilderTextField(
                              name: 'quantity',
                              decoration: InputDecoration(
                                labelText: 'Miktar',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FormBuilderTextField(
                              name: 'corridor',
                              decoration: InputDecoration(
                                labelText: 'KORİDOR',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FormBuilderTextField(
                              name: 'shelf',
                              decoration: InputDecoration(
                                labelText: 'RAF',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: _QrButton(onTap: () {}),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FormBuilderTextField(
                              name: 'floor',
                              decoration: InputDecoration(
                                labelText: 'KAT',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Paletteki Ürünler',
                          style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Divider(height: 1),
                      _products.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('Ürün yok')),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _products[index];
                          return ListTile(
                            title: Text(item.name),
                            trailing: Text(
                              '${item.quantity}x',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          );
                        },
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
}

class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QrButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.qr_code_scanner, size: 24),
        ),
      ),
    );
  }
}
