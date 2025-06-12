import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/shared_app_bar.dart';
import '../../../core/widgets/barcode_scanner_button.dart';
import '../../../core/widgets/custom_text_field.dart';

class PalletAssignmentScreen extends StatefulWidget {
  const PalletAssignmentScreen({super.key});

  @override
  State<PalletAssignmentScreen> createState() => _PalletAssignmentScreenState();
}

class _PalletAssignmentScreenState extends State<PalletAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _palletIdController = TextEditingController();
  final _boxIdController = TextEditingController();
  final _locationController = TextEditingController();

  final List<String> _assignedBoxes = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _palletIdController.dispose();
    _boxIdController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _onPalletIdScanned(String barcode) {
    setState(() {
      _palletIdController.text = barcode;
    });
    // You might want to fetch pallet details here
  }

  void _onBoxIdScanned(String barcode) {
    setState(() {
      _boxIdController.text = barcode;
    });
    _addBoxToList();
  }

  void _onLocationScanned(String barcode) {
    setState(() {
      _locationController.text = barcode;
    });
  }

  void _addBoxToList() {
    if (_boxIdController.text.isNotEmpty) {
      setState(() {
        final boxId = _boxIdController.text;
        if (!_assignedBoxes.contains(boxId)) {
          _assignedBoxes.insert(0, boxId);
          _boxIdController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('pallet_assignment.box_already_added'.tr()),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
      // FocusScope.of(context).requestFocus(_boxIdFocusNode); // If you have a focus node
    }
  }

  void _removeBox(String boxId) {
    setState(() {
      _assignedBoxes.remove(boxId);
    });
  }

  Future<void> _submitAssignment() async {
    if (_formKey.currentState!.validate()) {
      if (_assignedBoxes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('pallet_assignment.add_at_least_one_box'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        // TODO: Implement the actual logic for pallet assignment
        // final success = await palletRepository.assignBoxesToPallet(
        //   palletId: _palletIdController.text,
        //   boxIds: _assignedBoxes,
        //   location: _locationController.text,
        // );
        
        // Simulating network delay
        await Future.delayed(const Duration(seconds: 2));
        final success = true; // Placeholder

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('pallet_assignment.assignment_successful'.tr()),
              backgroundColor: Colors.green,
            ),
          );
          _resetForm();
        } else {
          throw Exception('Failed to assign pallet');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetForm() {
    setState(() {
      _formKey.currentState?.reset();
      _palletIdController.clear();
      _boxIdController.clear();
      _locationController.clear();
      _assignedBoxes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SharedAppBar(
        title: 'pallet_assignment.title'.tr(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildFormFields(),
              const SizedBox(height: 20),
              _buildAssignedBoxesList(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        CustomTextField(
          controller: _palletIdController,
          labelText: 'pallet_assignment.pallet_id'.tr(),
          hintText: 'pallet_assignment.scan_or_enter_pallet_id'.tr(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'pallet_assignment.pallet_id_required'.tr();
            }
            return null;
          },
          suffixIcon: BarcodeScannerButton(onScan: _onPalletIdScanned),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: _locationController,
          labelText: 'pallet_assignment.location'.tr(),
          hintText: 'pallet_assignment.scan_or_enter_location'.tr(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'pallet_assignment.location_required'.tr();
            }
            return null;
          },
          suffixIcon: BarcodeScannerButton(onScan: _onLocationScanned),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: _boxIdController,
          labelText: 'pallet_assignment.box_id'.tr(),
          hintText: 'pallet_assignment.scan_box_to_add'.tr(),
          onSubmitted: (_) => _addBoxToList(),
          suffixIcon: BarcodeScannerButton(onScan: _onBoxIdScanned),
        ),
      ],
    );
  }

  Widget _buildAssignedBoxesList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'pallet_assignment.assigned_boxes'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${_assignedBoxes.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _assignedBoxes.isEmpty
                ? Center(
                    child: Text(
                      'pallet_assignment.no_boxes_added'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: _assignedBoxes.length,
                    itemBuilder: (context, index) {
                      final boxId = _assignedBoxes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text((index + 1).toString()),
                          ),
                          title: Text(boxId),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => _removeBox(boxId),
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _submitAssignment,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check),
        label: Text('pallet_assignment.complete_assignment'.tr()),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          textStyle: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
} 