/// Adding a Customer, and correcting one (issue #214): the Customer list's own
/// write surface (`POST`/`PATCH /api/quality/customers`, customer-routes.js,
/// administrator only).
///
/// One dialog for both, the same choice `ProductFormDialog` makes: a Customer
/// carries a code, a name and an optional contact address, and the Active
/// switch — not enough surface to earn two files. [customer] null means Add;
/// non-null means Correct, and Correct sends only the fields that actually
/// changed, which is `updateCustomer`'s (customers.js) own `hasOwnProperty`
/// contract on the other end.
///
/// **A code is not correctable**, exactly as a Product's is not: it is what a
/// complaint quotes and what a person searches by, so it is shown read-only
/// while correcting and never sent (customers.js refuses it as a 400 rather
/// than ignoring it, which is why this dialog does not offer it).
///
/// A Customer is deactivated, never deleted — the Active switch, offered only
/// while correcting an existing row, is the one way this dialog ever reaches
/// `isActive`; there is no delete anywhere on this Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'customer.dart';
import 'customers_bloc.dart';

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({super.key, this.customer});

  /// Null for Add; the row being corrected otherwise.
  final Customer? customer;

  static const ValueKey<String> codeKey = ValueKey<String>('customer-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('customer-form-name');
  static const ValueKey<String> emailKey = ValueKey<String>('customer-form-email');
  static const ValueKey<String> activeKey = ValueKey<String>('customer-form-active');
  static const ValueKey<String> submitKey = ValueKey<String>('customer-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('customer-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('customer-form-failure');

  /// Opens the form over the Customer list. `showDialog` builds its route
  /// under the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<CustomersBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly, the same device every other dialog in this
  /// Platform uses.
  static Future<void> open(BuildContext context, {Customer? customer}) {
    final bloc = context.read<CustomersBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<CustomersBloc>.value(
        value: bloc,
        child: CustomerFormDialog(customer: customer),
      ),
    );
  }

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.customer?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.customer?.name ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.customer?.contactEmail ?? '');
  late bool _isActive = widget.customer?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.customer != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  /// A code and a name are what a Customer is; the contact address is
  /// optional, and blank means "not known" rather than an empty string.
  bool get _complete =>
      _isCorrection ? _name.text.trim().isNotEmpty : _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  /// Only the keys whose value actually changed from what this dialog opened
  /// with — never the whole form. The code is absent by construction: it is
  /// not correctable, so it is never sent. A blanked address sends `null`,
  /// which is how customers.js's `PATCH` clears one.
  Map<String, Object?> get _changes {
    final original = widget.customer!;
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name != original.name) changes['name'] = name;
    if (email != (original.contactEmail ?? '')) {
      changes['contactEmail'] = email.isEmpty ? null : email;
    }
    if (_isActive != original.isActive) changes['isActive'] = _isActive;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    if (_isCorrection) {
      final changes = _changes;
      if (changes.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context
          .read<CustomersBloc>()
          .add(CustomersCorrectionConfirmed(id: widget.customer!.id, changes: changes));
    } else {
      final email = _email.text.trim();
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<CustomersBloc>().add(
            CustomersAddConfirmed(
              code: _code.text.trim(),
              name: _name.text.trim(),
              contactEmail: email.isEmpty ? null : email,
            ),
          );
    }
  }

  void _onCustomersChanged(BuildContext context, CustomersState state) {
    if (!_awaiting || state is! CustomersLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<CustomersBloc, CustomersState>(
      listener: _onCustomersChanged,
      child: AlertDialog(
        title: Text(_isCorrection ? 'Correct Customer' : 'Add Customer'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: CustomerFormDialog.codeKey,
                  controller: _code,
                  // A code is the one field a correction cannot rewrite.
                  enabled: !_isCorrection && !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Code',
                    border: const OutlineInputBorder(),
                    helperText: _isCorrection ? 'A Customer\'s code cannot be corrected' : null,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: CustomerFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: CustomerFormDialog.emailKey,
                  controller: _email,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Contact email (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_isCorrection) ...[
                  const SizedBox(height: Spacing.md),
                  SwitchListTile(
                    key: CustomerFormDialog.activeKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
                  ),
                ],
                if (_failure != null)
                  Padding(
                    key: CustomerFormDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: CustomerFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: CustomerFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : (_isCorrection ? 'Save' : 'Add Customer')),
          ),
        ],
      ),
    );
  }
}
