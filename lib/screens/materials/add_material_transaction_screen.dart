import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/voice_assistant_sheet.dart';
import '../../core/services/voice_parser.dart';

class AddMaterialTransactionScreen extends StatefulWidget {
  const AddMaterialTransactionScreen({super.key});

  @override
  State<AddMaterialTransactionScreen> createState() =>
      _AddMaterialTransactionScreenState();
}

class _AddMaterialTransactionScreenState
    extends State<AddMaterialTransactionScreen> {
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> materials = [];
  List<Map<String, dynamic>> activeSites = [];
  String? selectedSiteId;
  String? selectedSiteName;

  String? selectedMaterialId;
  String transactionType = 'RECEIVED';

  final quantityController = TextEditingController();
  final siteController = TextEditingController();
  final remarksController = TextEditingController();

  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadMaterials();
  }

  @override
  void dispose() {
    quantityController.dispose();
    siteController.dispose();
    remarksController.dispose();
    super.dispose();
  }

  Future<void> loadMaterials() async {
    try {
      final data = await Supabase.instance.client
          .from('materials')
          .select()
          .order('name');

      // Fetch all sites that are not archived — handles any casing of status
      final sitesData = await Supabase.instance.client
          .from('sites')
          .select('id, name, status')
          .not('status', 'ilike', 'archived')
          .order('name');

      setState(() {
        materials = List<Map<String, dynamic>>.from(data);
        activeSites = List<Map<String, dynamic>>.from(sitesData);
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final quantity =
          double.tryParse(quantityController.text.trim()) ?? 0;

      final material = materials.firstWhere(
        (m) => m['id'] == selectedMaterialId,
      );

      final currentStock =
          (material['balance_qty'] ?? 0).toDouble();

      double newStock = currentStock;

      if (transactionType == 'USED' && (selectedSiteName == null || selectedSiteName!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecting an active site is required for stock usage.'),
            backgroundColor: AppColors.danger,
          ),
        );
        setState(() => saving = false);
        return;
      }

      if (transactionType == 'RECEIVED') {
        newStock += quantity;
      } else {
        newStock -= quantity;
        if (newStock < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Insufficient Stock'),
              backgroundColor: AppColors.danger,
            ),
          );
          setState(() => saving = false);
          return;
        }
      }

      await Supabase.instance.client
          .from('material_transactions')
          .insert({
        'material_id': selectedMaterialId,
        'transaction_type': transactionType,
        'quantity': quantity,
        'site_name': selectedSiteName ?? '',
        'remarks': remarksController.text.trim(),
      });

      await Supabase.instance.client
          .from('materials')
          .update({
        'balance_qty': newStock,
      })
          .eq('id', selectedMaterialId!);

      await activityLog.log(
        action: 'Material Transaction',
        module: 'Materials',
        description: 'Logged transaction: $transactionType $quantity units of ${material['name']}',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction Saved Successfully'),
          backgroundColor: AppColors.success,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save transaction: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  void _openVoiceAssistant() {
    final List<String> materialNames = materials
        .map((m) => (m['name'] as String?) ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    VoiceAssistantSheet.show(
      context,
      materialNames: materialNames,
      onActionConfirmed: (action) {
        if (action.type == VoiceActionType.material && action.targetName != null) {
          Map<String, dynamic>? matchedMaterial;
          for (final m in materials) {
            final name = (m['name'] as String?)?.toLowerCase().trim() ?? '';
            final target = action.targetName!.toLowerCase().trim();
            if (name == target || name.contains(target) || target.contains(name)) {
              matchedMaterial = m;
              break;
            }
          }

          if (matchedMaterial != null) {
            setState(() {
              selectedMaterialId = matchedMaterial!['id'];
              transactionType = action.value == 'IN' ? 'RECEIVED' : 'USED';
              quantityController.text = action.quantity?.toInt().toString() ?? '1';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Voice set ${matchedMaterial['name']}: ${action.quantity?.toInt()} units (${action.value == 'IN' ? 'Received' : 'Used'})',
                ),
                backgroundColor: AppColors.roseGold,
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Stock Movement'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic, color: AppColors.roseGold),
            onPressed: _openVoiceAssistant,
            tooltip: 'Voice Entry (Tamil/English)',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Log Stock Movement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select a material and transaction type, or tap the microphone to speak your command.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),

              DropdownButtonFormField<String>(
                value: selectedMaterialId,
                dropdownColor: AppColors.card,
                decoration: const InputDecoration(
                  labelText: 'Material',
                  border: OutlineInputBorder(),
                ),
                items: materials.map((material) {
                  return DropdownMenuItem<String>(
                    value: material['id'],
                    child: Text(material['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedMaterialId = value;
                  });
                },
                validator: (value) =>
                    value == null ? 'Select Material' : null,
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: transactionType,
                dropdownColor: AppColors.card,
                decoration: const InputDecoration(
                  labelText: 'Transaction Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'RECEIVED',
                    child: Text('Received (Stock In)'),
                  ),
                  DropdownMenuItem(
                    value: 'USED',
                    child: Text('Used (Stock Out)'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    transactionType = value!;
                  });
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter Quantity';
                  }
                  final qty = double.tryParse(value);
                  if (qty == null) {
                    return 'Enter a valid number';
                  }
                  if (qty <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  if (selectedMaterialId != null) {
                    final selectedMaterial = materials.firstWhere(
                      (m) => m['id'] == selectedMaterialId,
                      orElse: () => {},
                    );
                    final unit = selectedMaterial['unit'] as String? ?? '';
                    if (unit.toLowerCase() == 'loads' && qty < 0.5) {
                      return 'Minimum quantity for loads is 0.5';
                    }
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: selectedSiteId,
                decoration: InputDecoration(
                  labelText: transactionType == 'USED' 
                      ? 'Select Active Site (Required)' 
                      : 'Select Active Site (Optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_city),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('None (Central Stock)'),
                  ),
                  ...activeSites.map((site) => DropdownMenuItem<String>(
                        value: site['id'] as String,
                        child: Text(site['name'] as String? ?? ''),
                      )),
                ],
                onChanged: (val) {
                  setState(() {
                    selectedSiteId = val;
                    selectedSiteName = val == null || val.isEmpty
                        ? null
                        : activeSites
                            .firstWhere(
                              (s) => s['id'] == val,
                              orElse: () => {'name': ''},
                            )['name'] as String?;
                  });
                },
                validator: (val) {
                  if (transactionType == 'USED' && (val == null || val.isEmpty)) {
                    return 'Please select an active site';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: remarksController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Remarks (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: saving ? null : saveTransaction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roseGold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: saving
                      ? const SizedBox.shrink()
                      : const Icon(Icons.save),
                  label: saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Save Transaction',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openVoiceAssistant,
        backgroundColor: AppColors.roseGold,
        child: const Icon(Icons.mic, color: Colors.white),
      ),
    );
  }
}