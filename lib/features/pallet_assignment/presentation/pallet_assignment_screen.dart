import 'package:flutter/material.dart';
import 'package:diapalet/features/pallet_assignment/data/mock_pallet_service.dart';
import 'package:diapalet/features/pallet_assignment/domain/pallet_repository.dart';


class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  String selectedMode = 'Palet';
  late final PalletRepository palletRepository;
  late final List<String> palletList;
  String? selectedPallet;

  @override
  void initState() {
    super.initState();
    palletRepository = MockPalletService();
    palletList = palletRepository.getPalletList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raf Ayarla'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Palet'),
                    selected: selectedMode == 'Palet',
                    onSelected: (_) => setState(() => selectedMode = 'Palet'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Kutu'),
                    selected: selectedMode == 'Kutu',
                    onSelected: (_) => setState(() => selectedMode = 'Kutu'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Dropdown: Palet/Kutu
              DropdownButtonFormField<String>(
                value: selectedPallet,
                decoration: InputDecoration(labelText: selectedMode == 'Palet' ? 'Palet Seç' : 'Kutu Seç'),
                items: palletList
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) => setState(() => selectedPallet = value),
              ),
              const SizedBox(height: 12),

              // Miktar
              const TextField(
                decoration: InputDecoration(labelText: 'Miktar'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              // Konum Bilgileri
              const TextField(
                decoration: InputDecoration(labelText: 'KORİDOR'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              const TextField(
                decoration: InputDecoration(labelText: 'RAF'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              const TextField(
                decoration: InputDecoration(labelText: 'KAT'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),

              // Ürünler Listesi
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Paletteki Ürünler',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    _ProductRow(name: 'Gofret', quantity: '50x'),
                    _ProductRow(name: 'Sucuk', quantity: '100x'),
                    _ProductRow(name: 'Bal', quantity: '23x'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Kaydet Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.check),
                  label: const Text('Kaydet Ve Onayla'),
                ),
              )
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
