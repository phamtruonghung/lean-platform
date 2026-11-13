/// The supplier NCR register's Supplier filter (issue #215): the ticket's own
/// first filter, "supplier NCRs can be listed by Supplier".
///
/// The picker is an `AppSearchField<Supplier>` over the catalogue the register
/// already read — the *choosing* control of this client's two search controls
/// (issue #187), whose `fetchSuggestions` filters that list in memory and issues
/// no request at all. A dropdown would be the wrong control here: the Supplier
/// list is a catalogue nobody can scan, which is exactly the case ADR-0023 and
/// `app_search_field.dart`'s own doc comment send to this widget.
///
/// The two buttons a *filter* needs are the two a form does not — clear back to
/// every Supplier, and cancel — the same shape
/// `SupplierNcrOrgUnitFilterDialog` keeps beside it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_search_field.dart';
import 'supplier.dart';
import 'supplier_ncrs_bloc.dart';

class SupplierNcrSupplierFilterDialog extends StatelessWidget {
  const SupplierNcrSupplierFilterDialog({super.key});

  /// The one `AppSearchField` this dialog renders, named for its keys — the
  /// same device `NonconformanceLinkConcernDialog.fieldName` uses.
  static const String fieldName = 'supplier-ncr-filter-supplier';

  static final ValueKey<String> allSuppliersKey =
      AppDialog.actionKey('supplier-ncrs-supplier-filter-all');
  static final ValueKey<String> cancelKey =
      AppDialog.actionKey('supplier-ncrs-supplier-filter-cancel');

  static ValueKey<String> get supplierFieldKey => AppSearchField.fieldKey(fieldName);

  static ValueKey<String> supplierSuggestionKey(String id) =>
      AppSearchField.suggestionKey(fieldName, id);

  /// Opens the filter over the register. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<SupplierNcrsBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly, the same device every other dialog in this
  /// Platform uses.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<SupplierNcrsBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<SupplierNcrsBloc>.value(
        value: bloc,
        child: const SupplierNcrSupplierFilterDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<SupplierNcrsBloc>().state;
    final loaded = state is SupplierNcrsLoaded ? state : null;
    final chosenId = loaded?.filters.supplierId;

    Supplier? chosen() {
      for (final supplier in loaded?.suppliers ?? const <Supplier>[]) {
        if (supplier.id == chosenId) return supplier;
      }
      return null;
    }

    return AppDialog(
      title: 'Filter by Supplier',
      size: AppDialogSize.picker,
      // Clearing is this dialog's own act (the primary, right-most); Cancel is
      // the dismiss, which is what `Esc` runs.
      actions: [
        AppDialogAction(
          id: 'supplier-ncrs-supplier-filter-cancel',
          label: 'Cancel',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'supplier-ncrs-supplier-filter-all',
          label: 'All Suppliers',
          onPressed: () {
            context.read<SupplierNcrsBloc>().add(const SupplierNcrsFiltersCleared());
            Navigator.of(context).pop();
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Choose the Supplier whose supplier NCRs you want to read, or clear back to '
            'every Supplier.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          AppSearchField<Supplier>(
            name: fieldName,
            label: 'Supplier',
            helperText: 'By name or code.',
            value: chosen(),
            fetchSuggestions: (term) async {
              final needle = term.trim().toLowerCase();
              return [
                for (final supplier in loaded?.suppliers ?? const <Supplier>[])
                  if (supplier.code.toLowerCase().contains(needle) ||
                      supplier.name.toLowerCase().contains(needle))
                    supplier,
              ];
            },
            idOf: (supplier) => supplier.id,
            displayStringFor: (supplier) => supplier.summary,
            codeOf: (supplier) => supplier.code,
            suggestionBuilder: (context, supplier) => Text(
              supplier.summary,
              style: theme.textTheme.bodyMedium,
            ),
            onChanged: (supplier) => _pick(context, supplier),
            onSelected: (supplier) => _pick(context, supplier),
          ),
        ],
      ),
    );
  }

  // The widget's own `null` is what retires a stale pick; here a pick is a
  // filter that closes the dialog, because the register behind it re-reads the
  // moment the event lands.
  static void _pick(BuildContext context, Supplier? supplier) {
    if (supplier == null) return;
    context.read<SupplierNcrsBloc>().add(
          SupplierNcrsSupplierFilterSet(supplierId: supplier.id, name: supplier.name),
        );
    Navigator.of(context).pop();
  }
}
