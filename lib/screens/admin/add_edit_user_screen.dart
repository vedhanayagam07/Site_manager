import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/activity_log_service.dart';
import '../../core/theme/app_colors.dart';

class AddEditUserScreen extends StatefulWidget {
  final Map<String, dynamic>? user; // null = create, non-null = edit

  const AddEditUserScreen({super.key, this.user});

  @override
  State<AddEditUserScreen> createState() => _AddEditUserScreenState();
}

class _AddEditUserScreenState extends State<AddEditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'supervisor';
  String _selectedStatus = 'active';
  bool _saving = false;
  bool _obscurePassword = true;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final u = widget.user!;
      _nameController.text = u['name'] as String? ?? '';
      _emailController.text = u['email'] as String? ?? '';
      _selectedRole = u['role'] as String? ?? 'supervisor';
      _selectedStatus = u['status'] as String? ?? 'active';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      if (_isEditing) {
        // Edit mode: invoke server-side authenticated Edge Function
        final res = await Supabase.instance.client.functions.invoke(
          'admin-manage-user',
          body: {
            'action': 'update_user',
            'userId': widget.user!['id'],
            'name': _nameController.text.trim(),
            'role': _selectedRole,
            'status': _selectedStatus,
          },
        );

        if (res.status != 200) {
          final errorMsg = (res.data is Map && res.data['error'] != null)
              ? res.data['error'].toString()
              : 'Failed to update user.';
          throw Exception(errorMsg);
        }

        await activityLog.log(
          action: 'User Updated',
          module: 'Admin',
          description:
              'Updated: ${_nameController.text.trim()} → role=$_selectedRole, status=$_selectedStatus',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        // Create mode: invoke server-side authenticated Edge Function
        final email = _emailController.text.trim();
        final password = _passwordController.text;

        final res = await Supabase.instance.client.functions.invoke(
          'admin-manage-user',
          body: {
            'action': 'create_user',
            'email': email,
            'password': password,
            'name': _nameController.text.trim(),
            'role': _selectedRole,
            'status': _selectedStatus,
          },
        );

        if (res.status != 200) {
          final errorMsg = (res.data is Map && res.data['error'] != null)
              ? res.data['error'].toString()
              : 'Failed to create user.';
          throw Exception(errorMsg);
        }

        await activityLog.log(
          action: 'User Created',
          module: 'Admin',
          description:
              'Created: ${_nameController.text.trim()} ($email) as $_selectedRole',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      String errorMsg = e.toString();
      if (e is FunctionException && e.details is Map && e.details['error'] != null) {
        errorMsg = e.details['error'].toString();
      } else if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring(11);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $errorMsg'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit User' : 'Add User'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              if (!_isEditing) ...[
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Temporary Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                dropdownColor: AppColors.card,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Admin — Full Access',
                        overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'projectManager',
                    child: Text('Project Manager — Sites & Reports',
                        overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'supervisor',
                    child: Text('Supervisor — Attendance & Materials',
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedRole = v!),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedStatus,
                dropdownColor: AppColors.card,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.toggle_on_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'active',
                    child: Text('Active'),
                  ),
                  DropdownMenuItem(
                    value: 'disabled',
                    child: Text('Disabled'),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedStatus = v!),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roseGold,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving ? 'Saving…' : (_isEditing ? 'Update User' : 'Create User'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
