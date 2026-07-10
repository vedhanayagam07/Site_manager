import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';

class MaterialDetailScreen extends StatefulWidget {
  final Map material;

  const MaterialDetailScreen({
    super.key,
    required this.material,
  });

  @override
  State<MaterialDetailScreen> createState() =>
      _MaterialDetailScreenState();
}

class _MaterialDetailScreenState
    extends State<MaterialDetailScreen> {
  List transactions = [];
  List<String> activeSites = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTransactions();
    loadActiveSites();
  }

  Future<void> loadActiveSites() async {
    try {
      // Use ilike so it matches 'active', 'Active', 'ACTIVE' etc.
      final data = await Supabase.instance.client
          .from('sites')
          .select('name')
          .not('status', 'ilike', 'archived')
          .order('name');
      setState(() {
        activeSites = (data as List).map((s) => s['name'] as String).toList();
      });
    } catch (e) {
      debugPrint('Error loading active sites: $e');
    }
  }

  Future<void> loadTransactions() async {
    try {
      final data = await Supabase.instance.client
          .from('material_transactions')
          .select()
          .eq('material_id', widget.material['id'])
          .order('created_at', ascending: false);

      setState(() {
        transactions = data;
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> stockMovement(bool isReceive) async {
  final qtyController = TextEditingController();
  final remarksController = TextEditingController();
  String? selectedSiteName;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(
              isReceive ? 'Received Stock' : 'Used Stock',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedSiteName,
                  decoration: InputDecoration(
                    labelText: !isReceive 
                        ? 'Select Active Site (Required)' 
                        : 'Select Active Site (Optional)',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('None (Central Stock)'),
                    ),
                    ...activeSites.map((site) => DropdownMenuItem<String>(
                          value: site,
                          child: Text(site),
                        )),
                  ],
                  onChanged: (val) {
                    setStateDialog(() {
                      selectedSiteName = val;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: remarksController,
                  decoration: const InputDecoration(
                    labelText: 'Remarks',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != true) return;
  if (!mounted) return;

  final qty = double.tryParse(qtyController.text) ?? 0;

  if (qty <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enter a valid quantity'),
      ),
    );
    return;
  }

  final unit = widget.material['unit'] as String? ?? '';
  if (unit.toLowerCase() == 'loads' && qty < 0.5) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Minimum quantity for loads is 0.5'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  if (!isReceive && (selectedSiteName == null || selectedSiteName!.isEmpty)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Selecting an active site is required for stock usage.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  try {
    final materialId = widget.material['id'];

    final latestMaterial = await Supabase.instance.client
        .from('materials')
        .select()
        .eq('id', materialId)
        .single();

   debugPrint(widget.material.toString());

final currentStock =
    (latestMaterial['balance_qty'] ?? 0).toDouble();

    final receivedQty =
        (latestMaterial['received_qty'] ?? 0).toDouble();

    final usedQty =
        (latestMaterial['used_qty'] ?? 0).toDouble();

    if (!isReceive && qty > currentStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough stock available'),
        ),
      );
      return;
    }

    final newStock = isReceive
        ? currentStock + qty
        : currentStock - qty;

    await Supabase.instance.client
        .from('material_transactions')
        .insert({
      'material_id': materialId,
      'site_name': selectedSiteName ?? '',
      'transaction_type': isReceive ? 'RECEIVED' : 'USED',
      'quantity': qty,
      'remarks': remarksController.text.trim(),
    });

    await Supabase.instance.client
        .from('materials')
        .update({
  'balance_qty': newStock,
  'received_qty': isReceive
      ? receivedQty + qty
      : receivedQty,
  'used_qty': !isReceive
      ? usedQty + qty
      : usedQty,
})
        .eq('id', materialId);

    await activityLog.log(
      action: 'Material Transaction',
      module: 'Materials',
      description: 'Logged transaction: ${isReceive ? 'RECEIVED' : 'USED'} $qty units of ${widget.material['name']}',
    );

   setState(() {
  widget.material['balance_qty'] = newStock;
});

    await loadTransactions();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isReceive
              ? 'Stock Received Successfully'
              : 'Stock Used Successfully',
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
      ),
    );

    debugPrint(e.toString());
  }
}
Future<void> editMaterialDialog() async {
  final nameController =
      TextEditingController(text: widget.material['name']);

  final supplierController =
      TextEditingController(text: widget.material['supplier'] ?? '');

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Edit Material'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Material Name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: supplierController,
              decoration: const InputDecoration(
                labelText: 'Supplier',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (result != true) return;

  try {
    await Supabase.instance.client
        .from('materials')
        .update({
      'name': nameController.text.trim(),
      'supplier': supplierController.text.trim(),
    })
        .eq('id', widget.material['id']);

    setState(() {
      widget.material['name'] =
          nameController.text.trim();

      widget.material['supplier'] =
          supplierController.text.trim();
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Material Updated Successfully',
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
      ),
    );
  }
}
Future<void> deleteMaterial() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Delete Material'),
        content: Text(
          'Delete ${widget.material['name']}?\n\n'
          'All transaction history will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );

  if (confirm != true) return;

  try {
    await Supabase.instance.client
        .from('materials')
        .delete()
        .eq('id', widget.material['id']);

    await activityLog.log(
      action: 'Material Deleted',
      module: 'Materials',
      description: 'Deleted material: ${widget.material['name']}',
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Material Deleted Successfully',
        ),
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
  Widget build(BuildContext context) {
    final stock =
    widget.material['balance_qty'] ?? 0;

    final unit =
        widget.material['unit'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.material['name'],
        ),
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title:
                    const Text('Current Stock'),
                subtitle:
                    Text('$stock $unit'),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton.icon(
                onPressed: () =>
                    stockMovement(true),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Receive Stock',
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton.icon(
                onPressed: () =>
                    stockMovement(false),
                icon:
                    const Icon(Icons.remove),
                label:
                    const Text('Use Stock'),
              ),
            ),
            const SizedBox(height: 12),

SizedBox(
  width: double.infinity,
  height: 55,
  child: FilledButton.icon(
    onPressed: () {
      editMaterialDialog();
    },
    icon: const Icon(Icons.edit),
    label: const Text('Edit Material'),
  ),
),

const SizedBox(height: 12),

SizedBox(
  width: double.infinity,
  height: 55,
  child: FilledButton.icon(
    onPressed: () {
      deleteMaterial();
    },
    icon: const Icon(Icons.delete),
    label: const Text('Delete Material'),
  ),
),

            const SizedBox(height: 24),

            const Align(
              alignment:
                  Alignment.centerLeft,
              child: Text(
                'Transaction History',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(),
                    )
                  : transactions.isEmpty
                      ? const Center(
                          child: Text(
                            'No Transactions Yet',
                          ),
                        )
                      : ListView.builder(
                          itemCount:
                              transactions.length,
                          itemBuilder:
                              (context,
                                  index) {
                            final txn =
                                transactions[
                                    index];

                            final isReceive =
                                txn['transaction_type'] ==
                                    'RECEIVED';

                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  isReceive
                                      ? Icons.arrow_downward
                                      : Icons.arrow_upward,
                                ),
                                title: Text(
                                  '${txn['quantity']} $unit',
                                ),
                                subtitle:
                                    Text(
                                  '${txn['site_name'] ?? ''}\n${txn['remarks'] ?? ''}',
                                ),
                                trailing:
                                    Text(
                                  DateFormat(
                                    'dd MMM\nhh:mm a',
                                  ).format(
                                    DateTime.parse(
                                      txn['created_at'],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
    }

