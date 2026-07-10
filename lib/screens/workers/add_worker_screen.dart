import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';

class AddWorkerScreen extends StatefulWidget {
  const AddWorkerScreen({super.key});

  @override
  State<AddWorkerScreen> createState() => _AddWorkerScreenState();
}

class _AddWorkerScreenState extends State<AddWorkerScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String? selectedRole;
  String? selectedSkill;
  String? selectedSiteId;
  String? selectedSiteName;

  String selectedStatus = 'Active';

  // Dynamic sites from Supabase
  List<Map<String, dynamic>> _sites = [];
  bool _sitesLoading = true;

  final roles = [
    'Mason',
    'Carpenter',
    'Electrician',
    'Plumber',
    'Painter',
    'Supervisor',
    'Site Engineer',
    'Contractor',
  ];

  final skills = [
    'Civil Work',
    'Electrical',
    'Plumbing',
    'Steel Fixing',
    'Concrete Work',
    'Finishing',
  ];

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSites() async {
    setState(() => _sitesLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('sites')
          .select('id, name, status')
          .not('status', 'ilike', 'archived')
          .order('name');
      if (mounted) {
        setState(() {
          _sites = List<Map<String, dynamic>>.from(data);
          _sitesLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AddWorkerScreen] Error loading sites: $e');
      if (mounted) {
        setState(() => _sitesLoading = false);
      }
    }
  }

  Future<void> _saveWorker() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final name = _nameController.text.trim();
      final role = selectedRole ?? 'Worker';
      await Supabase.instance.client.from('workers').insert({
        'name': name,
        'phone': _phoneController.text.trim(),
        'role': selectedRole,
        'skill': selectedSkill,
        'status': selectedStatus,
        'site_id': selectedSiteId,
        'assigned_site': selectedSiteName,
      });

      await activityLog.log(
        action: 'Worker Created',
        module: 'Workers',
        description: 'Created worker: $name ($role)',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Worker Saved Successfully'),
          backgroundColor: AppColors.success,
        ),
      );
      _nameController.clear();
      _phoneController.clear();

      Navigator.pop(context, true); // return true so caller can refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save worker: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Worker'),
        actions: [
          // Refresh sites button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Sites',
            onPressed: _loadSites,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'Worker Information',
                style: theme.textTheme.headlineSmall,
              ),

              const SizedBox(height: 24),

              TextFormField(
                controller: _nameController,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter worker name';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'Worker Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter phone number';
                  }
                  if (value.length != 10) {
                    return 'Phone number must be 10 digits';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                dropdownColor: AppColors.card,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
                items: roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedRole = value;
                  });
                },
              ),

              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: selectedSkill,
                dropdownColor: AppColors.card,
                decoration: const InputDecoration(
                  labelText: 'Skill Set',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.engineering),
                ),
                items: skills
                    .map(
                      (skill) => DropdownMenuItem(
                        value: skill,
                        child: Text(skill),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedSkill = value;
                  });
                },
              ),

              const SizedBox(height: 16),

              // ── Assigned Site — dynamic from Supabase ──────────────────────
              if (_sitesLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Loading sites…',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              else if (_sites.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.warning),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No sites available. Please create a site first.',
                          style: TextStyle(color: AppColors.warning),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadSites,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: selectedSiteId,
                  dropdownColor: AppColors.card,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Site (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('— No site assigned —'),
                    ),
                    ..._sites.map(
                      (site) => DropdownMenuItem<String>(
                        value: site['id'] as String,
                        child: Text(site['name'] as String? ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedSiteId = value;
                      selectedSiteName = value == null
                          ? null
                          : _sites.firstWhere(
                              (s) => s['id'] == value,
                              orElse: () => {'name': ''},
                            )['name'] as String?;
                    });
                  },
                ),

              const SizedBox(height: 20),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Worker Status',
                        style: theme.textTheme.titleMedium,
                      ),

                      RadioListTile<String>(
                        title: const Text('Active'),
                        value: 'Active',
                        groupValue: selectedStatus,
                        onChanged: (value) {
                          setState(() {
                            selectedStatus = value!;
                          });
                        },
                      ),

                      RadioListTile<String>(
                        title: const Text('Inactive'),
                        value: 'Inactive',
                        groupValue: selectedStatus,
                        onChanged: (value) {
                          setState(() {
                            selectedStatus = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                height: 55,
                child: FilledButton.icon(
                  onPressed: _saveWorker,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roseGold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.save),
                  label: const Text(
                    'Save Worker',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
