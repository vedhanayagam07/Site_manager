import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';

class AddMaterialScreen extends StatefulWidget {
  const AddMaterialScreen({super.key});

  @override
  State<AddMaterialScreen> createState() => _AddMaterialScreenState();
}

class _AddMaterialScreenState extends State<AddMaterialScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final supplierController = TextEditingController();

  String selectedUnit = 'Bags';
  List sites = [];
  String? selectedSiteId;
  bool loadingSites = true;

  final units = [
    'Bags',
    'Kg',
    'Loads',
    'Nos',
  ];

  @override
  void initState() {
    super.initState();
    loadSites();
  }

  Future<void> loadSites() async {
    try {
      final data = await Supabase.instance.client
          .from('sites')
          .select()
          .order('name');
      setState(() {
        sites = data;
        loadingSites = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() => loadingSites = false);
    }
  }

  Future<void> saveMaterial() async {
    try {
      final name = nameController.text.trim();
      await Supabase.instance.client
          .from('materials')
          .insert({
        'name': name,
        'unit': selectedUnit,
        'supplier': supplierController.text.trim(),
        'site_id': selectedSiteId,
        'received_qty': 0,
        'used_qty': 0,
        'balance_qty': 0,
      });

      await activityLog.log(
        action: 'Material Created',
        module: 'Materials',
        description: 'Created material: $name ($selectedUnit)',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material Added Successfully'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    supplierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Material'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Material Name',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter material name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: selectedUnit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                ),
                items: units.map((unit) {
                  return DropdownMenuItem(
                    value: unit,
                    child: Text(unit),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedUnit = value!;
                  });
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: supplierController,
                decoration: const InputDecoration(
                  labelText: 'Supplier',
                ),
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: selectedSiteId,
                decoration: const InputDecoration(
                  labelText: 'Assign to Site (Required)',
                  border: OutlineInputBorder(),
                ),
                items: sites.map((site) {
                  return DropdownMenuItem<String>(
                    value: site['id'].toString(),
                    child: Text(site['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedSiteId = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a site';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 30),

              FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    saveMaterial();
                  }
                },
                child: const Text('Save Material'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}