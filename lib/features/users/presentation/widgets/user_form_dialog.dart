import 'package:flutter/material.dart';

import '../../../../core/services/permissions.dart';
import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/validators.dart';

/// Adds a staff member or edits an existing one.
class UserFormDialog extends StatefulWidget {
  const UserFormDialog({required this.store, this.user, super.key});

  final RetailStore store;
  final AppUser? user;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _username;
  final _password = TextEditingController();
  late AppRole _role;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.user == null;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController(text: widget.user?.name ?? '');
    _username = TextEditingController(text: widget.user?.username ?? '');
    _role = widget.user?.role ?? AppRole.cashier;
    _isActive = widget.user?.isActive ?? true;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'Add staff' : 'Edit ${widget.user!.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _fullName,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: Validators.requiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText: 'What they type to sign in. Lower case.',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.length < 3) return 'At least 3 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _isNew ? 'Password' : 'New password',
                    helperText: _isNew
                        ? 'At least 4 characters.'
                        : 'Leave blank to keep their current password.',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (_isNew && text.length < 4) {
                      return 'At least 4 characters';
                    }
                    if (!_isNew && text.isNotEmpty && text.length < 4) {
                      return 'At least 4 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AppRole>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final role in AppRole.values)
                      DropdownMenuItem(
                        value: role,
                        child: Text('${role.label} — ${role.description}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _role = value ?? _role),
                ),
                const SizedBox(height: 8),
                // Spelling out the grants avoids the owner having to guess what
                // a role name implies.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final permission in permissionsFor(_role))
                      Chip(
                        label: Text(_short(permission)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Account is active'),
                  subtitle: const Text(
                    'Turn off to stop them signing in without deleting their '
                    'history.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await widget.store.saveUser(
      id: widget.user?.id ?? 0,
      fullName: _fullName.text,
      username: _username.text,
      role: _role,
      password: _password.text,
      isActive: _isActive,
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    Navigator.of(context).pop();
  }
}

String _short(Permission permission) => switch (permission) {
  Permission.viewDashboard => 'Dashboard',
  Permission.viewProfit => 'Profit & GST',
  Permission.sellAtPos => 'Billing',
  Permission.giveDiscount => 'Discounts',
  Permission.viewProducts => 'View stock',
  Permission.editProducts => 'Edit stock',
  Permission.viewCustomers => 'View customers',
  Permission.editCustomers => 'Edit customers',
  Permission.viewSuppliers => 'View suppliers',
  Permission.editSuppliers => 'Edit suppliers',
  Permission.viewReports => 'Reports',
  Permission.manageSettings => 'Settings',
  Permission.manageUsers => 'Staff',
  Permission.backupRestore => 'Backup',
  Permission.processReturns => 'Returns',
  Permission.manageShift => 'Till session',
  Permission.recordPurchases => 'Purchases',
  Permission.recordExpenses => 'Expenses',
  Permission.recordPayments => 'Payments',
  Permission.adjustStock => 'Stock counts',
};
