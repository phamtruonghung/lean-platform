/// The triage queue (issue #72): every open Request across the Site, and the
/// decisions maintenance makes on each. Offered to the maintenance roles, not
/// to an operator — the operator's whole surface is `RequestsScreen`, which
/// lets them raise and follow their own; triaging is the commitment half this
/// Screen owns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/skeleton_list.dart';
import 'maintenance_request.dart';
import 'triage_bloc.dart';
import 'triage_dialogs.dart';

class TriageScreen extends StatelessWidget {
  const TriageScreen({super.key, required this.canTriage});

  /// Whether this caller holds a write Grant reaching some Open Request's
  /// Asset Org Unit. Accepting, declining and marking a duplicate are all
  /// writes (issue #72), so a caller the server would refuse on every one is
  /// offered none of them; the queue itself stays readable Site-wide.
  final bool canTriage;

  static const double maxWidth = 900;
  static const ValueKey<String> siteKey = ValueKey<String>('triage-site');
  static const ValueKey<String> noticeKey = ValueKey<String>('triage-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('triage-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('triage-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('triage-failed');
  static ValueKey<String> rowKey(String id) => ValueKey<String>('triage-row-$id');
  static ValueKey<String> acceptKey(String id) => ValueKey<String>('triage-accept-$id');
  static ValueKey<String> declineKey(String id) => ValueKey<String>('triage-decline-$id');
  static ValueKey<String> duplicateKey(String id) => ValueKey<String>('triage-duplicate-$id');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TriageBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          if (state is TriageLoaded && state.notice != null) _Notice(message: state.notice!),
          if (state is TriageLoaded && state.actionFailure != null)
            _Notice(message: state.actionFailure!, isError: true),
          Expanded(
            child: switch (state) {
              TriageLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              TriageUnavailable(message: final message) => _TriageFailed(message: message),
              TriageLoaded(isLoadingRequests: true) =>
                const SkeletonList(rows: 4, maxWidth: maxWidth),
              TriageLoaded(requests: final requests) when requests.isEmpty => const _TriageEmpty(),
              TriageLoaded(requests: final requests, actingOnId: final actingOnId) =>
                _TriageList(requests: requests, canTriage: canTriage, actingOnId: actingOnId),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final TriageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = state is TriageLoaded ? state as TriageLoaded : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TriageScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Triage', style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xs),
              Text(
                'Every open Request at this Site, waiting for a decision — '
                'accept it into a Work order, decline it, or mark it a duplicate.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (loaded != null && loaded.sites.length > 1) ...[
                const SizedBox(height: Spacing.md),
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: TriageScreen.siteKey,
                    initialValue: loaded.siteId,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
                    items: [
                      for (final site in loaded.sites)
                        DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
                    ],
                    onChanged: (siteId) {
                      if (siteId == null) return;
                      context.read<TriageBloc>().add(TriageSiteSelected(siteId));
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final containerColor =
        isError ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer;
    final contentColor =
        isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TriageScreen.maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: TriageScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(isError ? Icons.error_outline : Icons.info_outline,
                    size: 20, color: contentColor),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(message,
                      style: theme.textTheme.bodyMedium?.copyWith(color: contentColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TriageList extends StatelessWidget {
  const _TriageList({
    required this.requests,
    required this.canTriage,
    required this.actingOnId,
  });

  final List<MaintenanceRequest> requests;
  final bool canTriage;
  final String? actingOnId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TriageScreen.maxWidth),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) => _TriageRow(
            request: requests[index],
            canTriage: canTriage,
            isActing: actingOnId == requests[index].id,
            allRequests: requests,
          ),
        ),
      ),
    );
  }
}

class _TriageRow extends StatelessWidget {
  const _TriageRow({
    required this.request,
    required this.canTriage,
    required this.isActing,
    required this.allRequests,
  });

  final MaintenanceRequest request;
  final bool canTriage;
  final bool isActing;
  final List<MaintenanceRequest> allRequests;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: TriageScreen.rowKey(request.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.summary, style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${request.assetName} (${request.assetCode}) · ${request.urgencyLabel}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Chip(label: Text(request.statusLabel), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                Text(request.requestedByName ?? 'A floor requester',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(width: Spacing.lg),
                Icon(Icons.warning_amber_outlined, size: 16,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                Text(request.productionStopped ? 'Stopped now' : 'Running',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
            if (canTriage) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    key: TriageScreen.acceptKey(request.id),
                    onPressed: isActing
                        ? null
                        : () => AcceptRequestDialog.open(context, request: request),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Accept'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton(
                    key: TriageScreen.declineKey(request.id),
                    onPressed: isActing
                        ? null
                        : () => DeclineRequestDialog.open(context, request: request),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  TextButton(
                    key: TriageScreen.duplicateKey(request.id),
                    onPressed: isActing
                        ? null
                        : () => DuplicateRequestDialog.open(
                              context,
                              request: request,
                              queue: allRequests,
                            ),
                    child: const Text('Duplicate'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TriageEmpty extends StatelessWidget {
  const _TriageEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: TriageScreen.emptyKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_email_read_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('Nothing waiting', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(
                'Every open Request at this Site has been answered. When the '
                'floor raises something new, it will appear here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TriageFailed extends StatelessWidget {
  const _TriageFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: TriageScreen.failedKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Spacing.md),
              Text('The queue could not be read', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Text(message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                key: TriageScreen.retryKey,
                onPressed: () => context.read<TriageBloc>().add(const TriageStarted()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}