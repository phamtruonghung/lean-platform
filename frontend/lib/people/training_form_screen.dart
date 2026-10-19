/// The Training record as HR files it (issue #292, parent #286): one record
/// laid out as the plant's own bilingual printed form at `/training/:id/form`,
/// printable from the browser.
///
/// **A read and a layout, and nothing recorded.** Everything below renders what
/// ONE request already answers — `GET /api/people/training/:id`, the read
/// `TrainingDetailScreen` makes, through the same `TrainingDetailBloc` — so
/// there is no form endpoint and no second address for the same rows,
/// deliberately: a second answer to one question is the first thing to drift.
/// Nothing here writes, and the loaded form carries no control at all (no back
/// link, no button, no sidebar), because a page with chrome on it prints the
/// chrome. A draft and a partly answered record both render in full; the form
/// says what is true of the record rather than refusing to show it.
///
/// **What the form prints.** The record's facts, then one row per Trainee in
/// the order they were added (never re-sorted, never padded to a fixed count),
/// with the Signature cell reading the Trainee's answer: the day it came for a
/// confirmation, empty for a Trainee who has not answered (so a hand signature
/// can be collected on paper), and `Declined` with the day for a decline, so a
/// decline is never read as a signature. The two Evaluation columns carry an
/// `X` where the trainer recorded how that Trainee was evaluated. The Human
/// Resources cell at the foot is left blank on purpose: the Platform does not
/// know who files the record, and a name printed there would be a guess.
///
/// **Why it is bilingual, and only here.** The plant's printed form is
/// bilingual (English over Vietnamese), so this one document is. The app's own
/// Screens stay English: there is no translation layer, no `intl` and no
/// locale switch, and the Vietnamese below is fixed text copied from the plant's
/// template, the same way a printed form's wording is not a setting.
///
/// **Why the record number is printed.** The plant's controlled document
/// carries no record number; this form prints one beside its title anyway. That
/// is a deliberate departure, recorded on #286, and cheap to flip: it is one
/// `Text` ([TrainingFormScreen.numberKey]).
///
/// **Its width is its own, deliberately.** `AppLayout.pageWidth` (900) is what
/// a catalogue spends; this is a sheet of paper, and the table on it has six
/// columns, two of them for marks and one for a signature. 800 is about an A4
/// page at screen resolution — narrow enough that the browser's print scales it
/// to one page without shrinking the writing, wide enough that "Employee
/// Number" and the Vietnamese headings do not wrap mid-word.
///
/// **Colour carries no meaning.** The form is the Platform's darkest text on
/// white with plain borders, so a black-and-white printer loses nothing; every
/// colour is a theme token.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'training_detail_bloc.dart';
import 'training_record.dart';

class TrainingFormScreen extends StatelessWidget {
  const TrainingFormScreen({super.key, required this.trainingRecordId});

  /// The record this form is of — carried down from the route rather than
  /// re-read off the Bloc, so a retry asks for the same record.
  final String trainingRecordId;

  /// The form's own page width: roughly an A4 sheet at screen resolution (see
  /// this file's header for why that is a decision rather than an omission).
  static const double maxWidth = 800;

  static const ValueKey<String> loadedKey = ValueKey<String>('training-form-loaded');
  /// The record is not there (a 404, also what a draft the caller could not send
  /// answers) — worded as `TrainingDetailScreen` words it, so one fact has one
  /// wording.
  static const ValueKey<String> missingKey = ValueKey<String>('training-form-missing');
  static const ValueKey<String> backKey = ValueKey<String>('training-form-back');
  static const ValueKey<String> failedKey = ValueKey<String>('training-form-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('training-form-retry');

  /// The record number printed beside the title.
  static const ValueKey<String> numberKey = ValueKey<String>('training-form-number');

  /// The Human Resources cell at the foot — always blank.
  static const ValueKey<String> hrSignatureKey = ValueKey<String>('training-form-hr-signature');

  static ValueKey<String> traineeRowKey(String id) => ValueKey<String>('training-form-trainee-$id');
  static ValueKey<String> signatureCellKey(String id) =>
      ValueKey<String>('training-form-signature-$id');
  static ValueKey<String> paperMarkKey(String id) => ValueKey<String>('training-form-paper-$id');
  static ValueKey<String> jobTrainingMarkKey(String id) =>
      ValueKey<String>('training-form-job-training-$id');

  /// The form is its own `Scaffold` and nothing else: it is reached outside the
  /// Shell (see `buildRouter`), so there is no sidebar, brand header or account
  /// footer above it — which is what makes the browser's own print produce the
  /// form rather than the navigation around it.
  @override
  Widget build(BuildContext context) {
    final state = context.watch<TrainingDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        TrainingDetailDiscarded() => const SizedBox.shrink(),
        TrainingDetailLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
        TrainingDetailUnavailable(isMissing: true) => PlatformEmptyState.noneExist(
            key: missingKey,
            title: 'No such Training record',
            message: 'Nothing is recorded at this address. It may have been removed, or '
                'the address may be wrong.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Back to Training records',
            actionKey: backKey,
            onAction: () => context.go(Routes.training),
          ),
        TrainingDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That training form could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () =>
                context.read<TrainingDetailBloc>().add(TrainingDetailRequested(trainingRecordId)),
          ),
        TrainingDetailLoaded(record: final record) => _Form(record: record),
      },
    );
  }
}

/// `2`, `1.5` — the label already says hours.
String _hours(double hours) =>
    hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();

/// The date part of an ISO timestamp, or empty when there is none.
String _day(String? timestamp) =>
    timestamp == null || timestamp.length < 10 ? '' : timestamp.substring(0, 10);

class _Form extends StatelessWidget {
  const _Form({required this.record});

  final TrainingRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final side = BorderSide(color: ink);
    final title = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600);
    final trainerName = record.trainerName;

    return Center(
      child: AppPageFrame(
        maxWidth: TrainingFormScreen.maxWidth,
        child: SingleChildScrollView(
          // A `SingleChildScrollView` rather than a `ListView`, deliberately: a form
          // is a document of a bounded length, so every row is built whether or not
          // it is on screen — what a test can read and what a printer paginates. A
          // lazily-built list would leave the foot of the form out of the tree until
          // somebody scrolled to it.
          key: TrainingFormScreen.loadedKey,
          padding: const EdgeInsets.all(Spacing.xl),
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.card, border: Border.fromBorderSide(side)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Band(
                  side: side,
                  child: Column(
                    children: [
                      Text('Training Record', style: title),
                      Text(
                        'Biên bản ghi nhận đào tạo',
                        style: theme.textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(record.number, key: TrainingFormScreen.numberKey),
                    ],
                  ),
                ),
                _Fact(
                  side: side,
                  english: 'Training title:',
                  vietnamese: 'Nội dung đào tạo:',
                  value: record.title,
                ),
                _Fact(
                  side: side,
                  english: 'Date of Training:',
                  vietnamese: 'Ngày đào tạo:',
                  value: record.trainedOn,
                ),
                _Fact(
                  side: side,
                  english: 'Training duration ( Hr):',
                  vietnamese: 'Thời gian đào tạo( giờ):',
                  value: _hours(record.durationHours),
                ),
                _Fact(
                  side: side,
                  english: 'Name of the trainer:',
                  vietnamese: 'Người đào tạo:',
                  value: trainerName ?? '',
                ),
                _Fact(
                  side: side,
                  english: 'Objective of the training:',
                  vietnamese: 'Mục tiêu của đào tạo:',
                  value: record.objective ?? '',
                ),
                _Band(
                  side: side,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Attendance list/ danh sách tham gia :',
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _Header(side: side),
                for (var index = 0; index < record.trainees.length; index++)
                  _TraineeRow(side: side, number: index + 1, trainee: record.trainees[index]),
                _SignatureBlock(side: side, trainerName: trainerName),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width band with a rule under it.
class _Band extends StatelessWidget {
  const _Band({required this.side, required this.child, this.alignment = Alignment.center});

  final BorderSide side;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(border: Border(bottom: side)),
      child: child,
    );
  }
}

/// One fact: the English label over its Vietnamese one, and the value beside.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.side,
    required this.english,
    required this.vietnamese,
    required this.value,
  });

  final BorderSide side;
  final String english;
  final String vietnamese;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(border: Border(bottom: side)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _Label(english: english, vietnamese: vietnamese)),
          Expanded(flex: 5, child: Text(value, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

/// English over Vietnamese, the way the template stacks every label.
class _Label extends StatelessWidget {
  const _Label({required this.english, required this.vietnamese, this.align = CrossAxisAlignment.start});

  final String english;
  final String vietnamese;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(english, style: theme.textTheme.bodyMedium),
        Text(
          vietnamese,
          style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

/// The columns' widths, as flex: No., Employee Number, Employee name,
/// Signature, Paper, Job-training.
const List<int> _flex = [1, 2, 4, 3, 2, 2];

/// One table cell: a fixed minimum height, a rule to its left, and its content
/// centred. [child] null is an empty cell — no widget at all, so nothing in it
/// reads as text.
class _Cell extends StatelessWidget {
  const _Cell({super.key, required this.flex, required this.side, this.child, this.first = false});

  final int flex;
  final BorderSide side;
  final Widget? child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(Spacing.xs),
        decoration: BoxDecoration(border: first ? null : Border(left: side)),
        child: child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.side});

  final BorderSide side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget center(String text) => Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium);
    final italic = theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic);

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: side, bottom: side)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cell(
              flex: _flex[0],
              side: side,
              first: true,
              child: _Label(english: 'No.', vietnamese: 'STT', align: CrossAxisAlignment.center),
            ),
            _Cell(flex: _flex[1], side: side, child: center('Employee Number')),
            _Cell(
              flex: _flex[2],
              side: side,
              child: _Label(
                english: 'Employee name',
                vietnamese: 'Họ và tên nhân viên',
                align: CrossAxisAlignment.center,
              ),
            ),
            _Cell(
              flex: _flex[3],
              side: side,
              child: _Label(english: 'Signature', vietnamese: 'Ký tên', align: CrossAxisAlignment.center),
            ),
            Expanded(
              flex: _flex[4] + _flex[5],
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border(left: side)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Spacing.xs),
                      child: Text('Evaluation', textAlign: TextAlign.center, style: italic),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(border: Border(top: side)),
                      child: Row(
                        children: [
                          _Cell(flex: _flex[4], side: side, first: true, child: center('Paper')),
                          _Cell(flex: _flex[5], side: side, child: center('Job-training.')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraineeRow extends StatelessWidget {
  const _TraineeRow({required this.side, required this.number, required this.trainee});

  final BorderSide side;
  final int number;
  final TrainingTrainee trainee;

  /// What the Signature cell prints, or null for a cell left empty for a hand
  /// signature. A decline says so, so it is never read as a signature.
  String? get _signature => switch (trainee.answer) {
        'confirmed' => _day(trainee.answeredAt),
        'declined' => 'Declined ${_day(trainee.answeredAt)}'.trim(),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    final signature = _signature;
    Widget? mark(String evaluation) =>
        trainee.evaluation == evaluation ? Text('X', style: style) : null;

    return Container(
      key: TrainingFormScreen.traineeRowKey(trainee.id),
      decoration: BoxDecoration(border: Border(bottom: side)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cell(flex: _flex[0], side: side, first: true, child: Text('$number', style: style)),
            _Cell(flex: _flex[1], side: side, child: Text(trainee.employeeNo, style: style)),
            _Cell(flex: _flex[2], side: side, child: Text(trainee.employeeName, style: style)),
            _Cell(
              key: TrainingFormScreen.signatureCellKey(trainee.id),
              flex: _flex[3],
              side: side,
              child: signature == null ? null : Text(signature, style: style),
            ),
            _Cell(
              key: TrainingFormScreen.paperMarkKey(trainee.id),
              flex: _flex[4],
              side: side,
              child: mark('paper'),
            ),
            _Cell(
              key: TrainingFormScreen.jobTrainingMarkKey(trainee.id),
              flex: _flex[5],
              side: side,
              child: mark('job_training'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The foot: the trainer's printed name with room above for a hand signature, a
/// blank Date, and a blank Human Resources cell.
class _SignatureBlock extends StatelessWidget {
  const _SignatureBlock({required this.side, required this.trainerName});

  final BorderSide side;
  final String? trainerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Text(text, style: theme.textTheme.bodyMedium),
        );
    Widget box({Key? key, Widget? child, bool first = false}) => Expanded(
          child: Container(
            key: key,
            height: 96,
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              border: Border(top: side, left: first ? BorderSide.none : side),
            ),
            child: child,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: heading('Trainer/ Người đào tạo')),
            Expanded(child: Center(child: heading('Date/ngày'))),
            Expanded(child: heading('Humans Resource/ BP NS')),
          ],
        ),
        Row(
          children: [
            box(
              first: true,
              child: trainerName == null ? null : Text(trainerName!, style: theme.textTheme.bodyMedium),
            ),
            box(),
            box(key: TrainingFormScreen.hrSignatureKey),
          ],
        ),
      ],
    );
  }
}
