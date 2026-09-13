/// Classifying a Downtime event against the reason tree (issue #73).
///
/// The reason picker reads `GET /api/maintenance/downtime-reasons` when the
/// dialog opens. A reason whose `requiresComment` is true forces a free-text
/// note — "so 'Other — 340 minutes' at the top of the Pareto is at least
/// investigable" — so the submit button stays disabled until the description
/// says something, the same discipline `RequestDeclineDialog` keeps for its
/// required reason. When the catalogue cannot be fetched the field shows a
/// failure and submission is blocked rather than falling back to free text
/// (ADR-0023).
///
/// This is a dialog, not a Screen and not a Destination — CONTEXT.md's own
/// Screen entry says a dialog inside a Screen is not a Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'downtime_bloc.dart';
import 'downtime_event.dart';
import 'maintenance_api.dart';

class DowntimeClassifyDialog extends StatefulWidget {
  const DowntimeClassifyDialog({super.key, required this.downtimeEvent});

  /// The stop being classified.
  final DowntimeEvent downtimeEvent;

  static const ValueKey<String> reasonKey = ValueKey<String>('downtime-classify-reason');
  static const ValueKey<String> reasonsFailedKey =
      ValueKey<String>('downtime-classify-reasons-failed');
  static const ValueKey<String> descriptionKey = ValueKey<String>('downtime-classify-description');
  static const ValueKey<String> submitKey = ValueKey<String>('downtime-classify-submit');
  static const ValueKey<String> dismissKey = ValueKey<String>('downtime-classify-dismiss');
  static const ValueKey<String> failureKey = ValueKey<String>('downtime-classify-failure');

  @override
  State<DowntimeClassifyDialog> createState() => _DowntimeClassifyDialogState();
}

enum _ReasonsStatus { loading, ready, failed }

class _DowntimeClassifyDialogState extends State<DowntimeClassifyDialog> {
  final TextEditingController _description = TextEditingController();

  _ReasonsStatus _reasonsStatus = _ReasonsStatus.loading;
  List<DowntimeReason> _reasons = const [];
  String? _reasonsFailure;

  /// Null until chosen — never defaulted, so a classification is never made
  /// without somebody choosing a reason.
  DowntimeReason? _reason;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadReasons() async {
    setState(() {
      _reasonsStatus = _ReasonsStatus.loading;
      _reasonsFailure = null;
    });
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() {
        _reasonsStatus = _ReasonsStatus.failed;
        _reasonsFailure = DowntimeBloc.signedOutMessage;
      });
      return;
    }
    try {
      final reasons = await context.read<MaintenanceApi>().fetchDowntimeReasons(token);
      if (!mounted) return;
      setState(() {
        _reasons = reasons;
        _reasonsStatus = _ReasonsStatus.ready;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _reasonsStatus = _ReasonsStatus.failed;
        _reasonsFailure = error.message;
      });
    }
  }

  /// A reason whose `requiresComment` is true needs a non-blank description;
  /// any other reason may go without one.
  bool get _complete {
    final reason = _reason;
    if (reason == null) return false;
    if (reason.requiresComment && _description.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final description = _description.text.trim();
    context.read<DowntimeBloc>().add(
          DowntimeClassifyConfirmed(
            downtimeEventId: widget.downtimeEvent.id,
            downtimeReasonId: _reason!.id,
            description: description.isEmpty ? null : description,
          ),
        );
  }

  void _onDowntimeChanged(BuildContext context, DowntimeState state) {
    if (!_awaiting || state is! DowntimeLoaded || state.isActing) return;
    if (state.actionFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.actionFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiresComment = _reason?.requiresComment ?? false;
    return BlocListener<DowntimeBloc, DowntimeState>(
      listener: _onDowntimeChanged,
      child: AlertDialog(
        title: Text('Classify the stop for ${widget.downtimeEvent.assetName}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReasonField(
                  status: _reasonsStatus,
                  reasons: _reasons,
                  failure: _reasonsFailure,
                  selectedId: _reason?.id,
                  enabled: !_awaiting,
                  onRetry: _loadReasons,
                  onChanged: (reason) => setState(() => _reason = reason),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: DowntimeClassifyDialog.descriptionKey,
                  controller: _description,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: requiresComment ? 'Description (required)' : 'Description (optional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: DowntimeClassifyDialog.failureKey,
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
            key: DowntimeClassifyDialog.dismissKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Keep it unclassified'),
          ),
          FilledButton(
            key: DowntimeClassifyDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: const Text('Classify'),
          ),
        ],
      ),
    );
  }
}

class _ReasonField extends StatelessWidget {
  const _ReasonField({
    required this.status,
    required this.reasons,
    required this.failure,
    required this.selectedId,
    required this.enabled,
    required this.onRetry,
    required this.onChanged,
  });

  final _ReasonsStatus status;
  final List<DowntimeReason> reasons;
  final String? failure;
  final String? selectedId;
  final bool enabled;
  final VoidCallback onRetry;
  final ValueChanged<DowntimeReason?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case _ReasonsStatus.loading:
        return const SizedBox(
          height: 48,
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        );
      case _ReasonsStatus.failed:
        return Column(
          key: DowntimeClassifyDialog.reasonsFailedKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failure ?? 'The Downtime reasons could not be read.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
            TextButton(onPressed: enabled ? onRetry : null, child: const Text('Try again')),
          ],
        );
      case _ReasonsStatus.ready:
        return DropdownButtonFormField<String>(
          key: DowntimeClassifyDialog.reasonKey,
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
          items: [
            for (final reason in reasons)
              DropdownMenuItem<String>(value: reason.id, child: Text(reason.name)),
          ],
          onChanged: enabled
              ? (id) {
                  for (final reason in reasons) {
                    if (reason.id == id) {
                      onChanged(reason);
                      return;
                    }
                  }
                  onChanged(null);
                }
              : null,
        );
    }
  }
}
