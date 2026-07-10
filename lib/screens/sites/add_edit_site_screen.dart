import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';

class AddEditSiteScreen extends StatefulWidget {
  final Map<String, dynamic>? site; // null = Add mode

  const AddEditSiteScreen({super.key, this.site});

  @override
  State<AddEditSiteScreen> createState() => _AddEditSiteScreenState();
}

class _AddEditSiteScreenState extends State<AddEditSiteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();
  final _progressCtrl = TextEditingController();

  String _status = 'Active';
  bool _saving = false;

  bool get _isEdit => widget.site != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final s = widget.site!;
      _nameCtrl.text = s['name'] ?? '';
      _locationCtrl.text = s['location'] ?? '';
      _managerCtrl.text = s['project_manager'] ?? '';
      _progressCtrl.text = (s['progress'] ?? 0).toString();
      _status = s['status'] ?? 'Active';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _managerCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final payload = {
      'name': _nameCtrl.text.trim(),
      'location': _locationCtrl.text.trim(),
      'project_manager': _managerCtrl.text.trim(),
      'status': _status,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isEdit) {
        await Supabase.instance.client
            .from('sites')
            .update(payload)
            .eq('id', widget.site!['id']);
        await prefs.setInt('site_progress_${widget.site!['id']}', int.tryParse(_progressCtrl.text) ?? 0);
        await activityLog.log(
          action: 'Site Updated',
          module: 'Sites',
          description: 'Updated site: ${payload['name']}',
        );
      } else {
        final newSite = await Supabase.instance.client
            .from('sites')
            .insert(payload)
            .select()
            .single();
        await prefs.setInt('site_progress_${newSite['id']}', int.tryParse(_progressCtrl.text) ?? 0);
        await activityLog.log(
          action: 'Site Created',
          module: 'Sites',
          description: 'Created site: ${payload['name']}',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_isEdit ? 'Site updated successfully' : 'Site added successfully'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Site' : 'Add Site'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _field(
              controller: _nameCtrl,
              label: 'Site Name',
              icon: Icons.location_city,
              validator: (v) =>
                  v == null || v.isEmpty ? 'Enter site name' : null,
            ),
            const SizedBox(height: 16),
            _field(
              controller: _locationCtrl,
              label: 'Location / Address',
              icon: Icons.place,
            ),
            const SizedBox(height: 16),
            _field(
              controller: _managerCtrl,
              label: 'Project Manager',
              icon: Icons.manage_accounts,
            ),
            const SizedBox(height: 16),
            _field(
              controller: _progressCtrl,
              label: 'Progress (0–100%)',
              icon: Icons.trending_up,
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 0 || n > 100) {
                  return 'Enter a number between 0 and 100';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Site Status',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: ['Active', 'On Hold', 'Completed'].map((s) {
                      final selected = _status == s;
                      return ChoiceChip(
                        label: Text(s),
                        selected: selected,
                        selectedColor: AppColors.roseGold,
                        onSelected: (_) => setState(() => _status = s),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 55,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_isEdit ? 'Update Site' : 'Save Site'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.roseGold),
      ),
    );
  }
}
