/// One CAPA as `/api/actions/capas/:id` sends it (issue #209) — the
/// investigation opened on a Concern, and the Concern it is about.
///
/// ADR-0034's shape is what this model holds: a CAPA is not a record that runs
/// beside a Concern, so there is no list of the investigation's own steps here.
/// What the CAPA carries beyond the Concern is the team, the problem
/// description and — as later tickets land — the root causes, the effectiveness
/// check and the report; what the *work* is, the Concern already answers, and
/// [concern] carries it with its Containments, Countermeasures and Preventive
/// actions and every phase each one has been round.
///
/// CONTEXT.md's words are the field names, as everywhere in this client: a CAPA
/// and its team, never a "ticket" and never a "case".
library;

import 'package:flutter/foundation.dart';

import '../status_tone.dart';
import 'action.dart';

/// One Employee on a CAPA's team, as the server names them — the lead or a
/// member. Deliberately not People's `Employee`: this is a name on an
/// investigation, not a directory record, and the two facts a reader of a CAPA
/// needs are the id and what to call the person.
@immutable
class CapaTeamMember {
  const CapaTeamMember({required this.employeeId, required this.name});

  final String employeeId;
  final String name;
}

/// The seven states an investigation can be in, mirroring the CHECK constraint
/// on `capas.status`.
///
/// One map carrying the label and the tone TOGETHER, the rule every status set
/// in this client follows (issue #168): a status cannot arrive with one and not
/// the other. The tones answer the same scanning question — "what wants me?" —
/// and `verifying` is the one `warning` for the reason `blocked` is on an
/// Action: the fix is in, nobody has proved it held, and a person has to decide
/// something. `open`, `containment`, `root_cause` and `actions` are all live and
/// asking nothing of the reader, so they are `info`.
const Map<String, (String, StatusTone)> capaStatuses = {
  'open': ('Open', StatusTone.info),
  'containment': ('Contained', StatusTone.info),
  'root_cause': ('Root cause', StatusTone.info),
  'actions': ('Actions', StatusTone.info),
  'verifying': ('Verifying', StatusTone.warning),
  'closed': ('Closed', StatusTone.success),
  'cancelled': ('Cancelled', StatusTone.neutral),
};

/// A status this build does not know about renders as its own wire value, the
/// same fallback `actionStatusLabel` takes: a server that gains a state shows
/// it rather than throwing.
String capaStatusLabel(String wire) => capaStatuses[wire]?.$1 ?? wire;

StatusTone capaStatusTone(String wire) => capaStatuses[wire]?.$2 ?? StatusTone.neutral;

/// The one method this slice opens a CAPA by (ADR-0034: an 8D). The baseline's
/// CHECK accepts four; the label map exists so the Screen names the one it has
/// rather than printing the wire value.
const Map<String, String> capaMethodLabels = {
  '8d': '8D',
  '5why': '5 Why',
  'a3': 'A3',
  'simple': 'Simple',
};

String capaMethodLabel(String wire) => capaMethodLabels[wire] ?? wire;

/// The two verdicts an effectiveness check records (issue #211), mirroring the
/// API's own closed set. They are the plant's words rather than a boolean: a
/// check that did not hold is not "false", it is the sentence that sends a
/// Concern round again — which is why the tone travels with the label, the rule
/// every status set in this client follows.
const Map<String, (String, StatusTone)> capaEffectivenessOutcomes = {
  'effective': ('The fix held', StatusTone.success),
  'not_effective': ('The fix did not hold', StatusTone.warning),
};

/// The order the two verdicts are offered in: the one that closes the
/// investigation first, because that is what a check is usually for.
const List<String> capaEffectivenessOutcomeOrder = ['effective', 'not_effective'];

String capaEffectivenessOutcomeLabel(String wire) =>
    capaEffectivenessOutcomes[wire]?.$1 ?? wire;

StatusTone capaEffectivenessOutcomeTone(String wire) =>
    capaEffectivenessOutcomes[wire]?.$2 ?? StatusTone.neutral;

/// The two 5 Why chains a CAPA's team reasons with (issue #210), and the words
/// this client reads them by.
///
/// The wire values are `occurrence` and `escape` — 8D's own names for "why the
/// problem happened" and "why it was not detected", which is what ADR-0034
/// calls them. The labels are the question each chain asks, because that is
/// what a person writing the chain is answering; a chain this build does not
/// know renders as its own wire value rather than throwing, the same fallback
/// [capaStatusLabel] takes.
const Map<String, String> capaChainLabels = {
  'occurrence': 'Why it happened',
  'escape': 'Why it was not detected',
};

String capaChainLabel(String wire) => capaChainLabels[wire] ?? wire;

/// The order the two chains are read in: why the problem happened before why it
/// was not detected. The server returns them in this order too (see
/// `listCapaWhys` in the Actions Module), so a Screen written against this list
/// and one written against the server's own order agree.
const List<String> capaChainOrder = ['occurrence', 'escape'];

/// One Why in one of a CAPA's two chains (issue #210).
///
/// [sequence] is the Why's position in *its own chain*, counting from 1 — the
/// server keeps a chain contiguous, so the positions a Screen renders are the
/// order the team reasoned them in. [isRoot] marks where the chain stopped: at
/// most one Why per chain is the confirmed root cause, which the server
/// guarantees and replaces rather than refuses when a second is marked.
@immutable
class CapaWhy {
  const CapaWhy({
    required this.id,
    required this.chain,
    required this.sequence,
    required this.statement,
    this.isRoot = false,
  });

  final String id;
  final String chain;

  /// The 1-based position in [chain].
  final int sequence;

  final String statement;

  /// Whether this is the chain's confirmed root cause.
  final bool isRoot;

  String get chainLabel => capaChainLabel(chain);
}

/// The 6M categories a candidate cause is filed under (issue #213), and the
/// words this client reads them by.
///
/// The wire values are Ishikawa's own six, which is what the schema's
/// `capa_root_causes.category` CHECK carries; the labels are the capitalised
/// words a Screen and a report print, because a fishbone is drawn with "Man",
/// "Machine" and the rest on its bones and a printed report may not link to a
/// map. A category this build does not know renders as its own wire value
/// rather than throwing, the same fallback [capaStatusLabel] takes.
const Map<String, String> capaCauseCategoryLabels = {
  'man': 'Man',
  'machine': 'Machine',
  'method': 'Method',
  'material': 'Material',
  'measurement': 'Measurement',
  'environment': 'Environment',
};

String capaCauseCategoryLabel(String wire) => capaCauseCategoryLabels[wire] ?? wire;

/// The order the six are read in: the order an Ishikawa diagram is drawn, not
/// alphabetical, which would read Machine, Man, Method … and put the bones in
/// an order nobody draws them in. The server returns them in this order too
/// (see `listCapaCauses` in the Actions Module), so a Screen written against
/// this list and one written against the server's own order agree.
const List<String> capaCauseCategoryOrder = [
  'man',
  'machine',
  'method',
  'material',
  'measurement',
  'environment',
];

/// The three verdicts a candidate cause can carry (issue #213), mirroring the
/// API's own closed set, with the tone travelling with the label — the rule
/// every status set in this client follows.
///
/// `candidate` is `neutral` rather than `warning`: a cause nobody has looked at
/// yet is the ordinary state of a fishbone being built, and painting every
/// fresh branch as a decision wanted would make the one that is genuinely open
/// — a confirmed cause whose chain has not been started — impossible to pick
/// out. `confirmed` is `success` (the evidence backed it) and `ruled_out` is
/// `neutral` (the evidence settled it, and the answer was no: a decision
/// somebody made on purpose is not a fault).
const Map<String, (String, StatusTone)> capaCauseVerdicts = {
  'candidate': ('Candidate', StatusTone.neutral),
  'confirmed': ('Confirmed', StatusTone.success),
  'ruled_out': ('Ruled out', StatusTone.neutral),
};

/// The verdicts a cause can be *decided* with, in the order the dialog offers
/// them: the one the team is looking for first, because a fishbone usually ends
/// with one cause confirmed and several ruled out.
const List<String> capaCauseDecisions = ['confirmed', 'ruled_out'];

String capaCauseVerdictLabel(String wire) => capaCauseVerdicts[wire]?.$1 ?? wire;

StatusTone capaCauseVerdictTone(String wire) => capaCauseVerdicts[wire]?.$2 ?? StatusTone.neutral;

/// One candidate cause on a CAPA's fishbone (issue #213).
///
/// [category] is the one 6M bone it hangs from, and [sequence] is its position
/// among that category's own causes — the order the team wrote them in, which
/// the server keeps and never renumbers. [verdict] is [capaCauseVerdicts]'s
/// value and [evidenceNote] is the evidence for it, written with the verdict
/// and null while the cause is still a `candidate`.
@immutable
class CapaCause {
  const CapaCause({
    required this.id,
    required this.category,
    required this.sequence,
    required this.statement,
    this.verdict = 'candidate',
    this.evidenceNote,
  });

  final String id;
  final String category;

  /// The 1-based position among [category]'s own causes.
  final int sequence;

  final String statement;

  /// `candidate`, `confirmed` or `ruled_out`.
  final String verdict;

  /// The evidence for [verdict], in the words of whoever wrote it — null on a
  /// candidate, and never null on a decided cause, which is the server's rule
  /// said as a 400.
  final String? evidenceNote;

  String get categoryLabel => capaCauseCategoryLabel(category);
  String get verdictLabel => capaCauseVerdictLabel(verdict);
  StatusTone get verdictTone => capaCauseVerdictTone(verdict);

  /// Whether the evidence backed this cause — the one state a Why chain may be
  /// started from, which is why a Screen reads it to decide what to offer.
  bool get isConfirmed => verdict == 'confirmed';

  /// Whether anybody has decided about it yet, either way.
  bool get isDecided => verdict != 'candidate';
}

/// The CAPA a Concern has been turned into, as the Concern's own read names it
/// (issue #209) — its id, the number a person quotes, and how the investigation
/// is going.
///
/// Named rather than nested, and deliberately not a whole [Capa]: a reader of a
/// Concern needs to know that the problem is under investigation and to be able
/// to go there, not to receive the investigation's team, description and
/// measures alongside the Concern's own. The one thing that crosses the two
/// records is what makes the link legible: "under investigation, as
/// CA-HCM-2026-00001, verifying".
@immutable
class CapaLink {
  const CapaLink({required this.id, required this.capaNo, required this.status});

  final String id;
  final String capaNo;
  final String status;

  String get statusLabel => capaStatusLabel(status);
  StatusTone get statusTone => capaStatusTone(status);
}

/// The Account that recorded a CAPA's effectiveness check (issue #211), named
/// rather than nested, the shape [CapaTeamMember] takes: a reader of an
/// investigation wants who decided the fix held, which is a name, and the id
/// only matters to an address.
///
/// Deliberately not People's `Account`: an administrator need not be an
/// Employee, so this is a name on a verification and not a directory record.
@immutable
class CapaVerifier {
  const CapaVerifier({required this.accountId, required this.name});

  final String accountId;
  final String name;
}

@immutable
class Capa {
  const Capa({
    required this.id,
    required this.capaNo,
    required this.title,
    required this.method,
    required this.status,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.teamMembers,
    this.whys = const [],
    this.causes = const [],
    this.problemStatement,
    this.orgUnitCode,
    this.teamLead,
    this.openedAt,
    this.dueDate,
    this.closedAt,
    this.effectivenessCheckDelayDays = 30,
    this.effectivenessCheckDueAt,
    this.effectivenessCheckOverdue = false,
    this.effectivenessVerifiedAt,
    this.effectivenessVerifiedBy,
    this.effectivenessNote,
    this.concern,
  });

  final String id;

  /// The number a person quotes in a report or an audit: `CA-HCM-2026-00001`.
  final String capaNo;

  /// What the investigation is about — the Concern's own title, which is what
  /// the server files a CAPA under rather than restating the problem (see
  /// `openCapa` in `actions.js`).
  final String title;

  /// The discipline being followed: `8d` for every CAPA this slice opens.
  final String method;

  /// The investigation's own state — is the root cause confirmed, has
  /// effectiveness been verified — never whether its actions are done, which
  /// the [concern] already answers (ADR-0034).
  final String status;

  final String orgUnitId;
  final String? orgUnitCode;
  final String orgUnitName;
  final String siteId;

  /// What the investigation adds on top of the Concern: D2's own field.
  final String? problemStatement;

  /// The team. The lead is a role and the members are a set, which is why they
  /// are shaped differently here as well as in the schema.
  final CapaTeamMember? teamLead;
  final List<CapaTeamMember> teamMembers;

  /// The two 5 Why chains (issue #210), in the order the server returns them:
  /// `occurrence` first, then `escape`, each chain in its own order. One list
  /// rather than two named ones, because a Why already says which chain it is
  /// in — [whysIn] and [rootCauseOf] are the two questions a Screen asks of it.
  final List<CapaWhy> whys;

  /// The fishbone (issue #213): the candidate causes, in the order the server
  /// returns them — the 6M's own order, each category in the order its causes
  /// were recorded. One flat list, like [whys], because a cause already says
  /// which category it is in and what its verdict is; [causesIn] and
  /// [confirmedCauses] are the questions a Screen asks of it.
  final List<CapaCause> causes;

  final DateTime? openedAt;
  final String? dueDate;
  final DateTime? closedAt;

  /// The effectiveness check (issue #211): how many days after the Concern
  /// closes it falls due (30 unless somebody changed it), the date that rule
  /// produced at the last closure, and whether that date has passed with
  /// nothing recorded.
  ///
  /// The date is null while the Concern is open — nothing is due yet — and is
  /// cleared again by a check that did not hold, so an investigation whose fix
  /// is being rewritten does not read as overdue.
  final int effectivenessCheckDelayDays;
  final String? effectivenessCheckDueAt;
  final bool effectivenessCheckOverdue;

  /// When the check was recorded, and by whom, with what note — null until one
  /// has been. All three are written by both verdicts, because a check that did
  /// not hold is evidence too.
  final DateTime? effectivenessVerifiedAt;
  final CapaVerifier? effectivenessVerifiedBy;
  final String? effectivenessNote;

  /// The Concern this investigation is about, with its own measures each
  /// carrying every phase it has been round — the server's own answer, not
  /// something this client assembles from a second read.
  final Action? concern;

  String get methodLabel => capaMethodLabel(method);
  String get statusLabel => capaStatusLabel(status);
  StatusTone get statusTone => capaStatusTone(status);

  /// Whether the investigation is over. Nothing about a closed or cancelled
  /// CAPA may be changed, which is the server's own rule.
  bool get isOpen => !const {'closed', 'cancelled'}.contains(status);

  /// Whether the effectiveness check is due to be recorded: the Concern has
  /// closed, nothing has been verified yet, and the investigation is still
  /// open. The one condition a Screen reads to offer the check rather than the
  /// sentence that says why it cannot (the server is the real gate).
  bool get effectivenessCheckIsDue => isOpen && effectivenessCheckDueAt != null;

  /// The verdict the last recorded check gave, as the record implies it — null
  /// until one has been recorded.
  ///
  /// The API keeps no outcome column for the effectiveness check, and it does
  /// not need one: an investigation that reaches `closed` is one whose check
  /// held (it is the only door to that status), and one back in `actions` had a
  /// check that did not, which is ADR-0033's own re-run recorded as the state
  /// the work is in. Reading it from the status is therefore the same fact said
  /// once rather than twice, and the two can never drift apart.
  String? get effectivenessOutcome {
    if (effectivenessVerifiedAt == null) return null;
    return status == 'closed' ? 'effective' : 'not_effective';
  }

  /// Everybody on the investigation, lead first — what a Screen renders when it
  /// wants one line rather than a section.
  List<CapaTeamMember> get team => [?teamLead, ...teamMembers];

  /// One chain's Whys, in their own order (issue #210). The server's list is
  /// already ordered by chain; this is the filter a Screen renders one chain
  /// with, kept here so the Screen is not the second place that knows what a
  /// chain's order is.
  List<CapaWhy> whysIn(String chain) =>
      [for (final why in whys) if (why.chain == chain) why];

  /// Where a chain stopped, or null while it is still being reasoned — which is
  /// a real state, and the one #211 refuses to close a CAPA on.
  CapaWhy? rootCauseOf(String chain) {
    for (final why in whys) {
      if (why.chain == chain && why.isRoot) return why;
    }
    return null;
  }

  /// Whether both chains have concluded: a confirmed root cause for why the
  /// problem happened *and* for why it was not detected — the first half of
  /// CONTEXT.md's own sentence about when a CAPA closes, and the one the client
  /// can answer from the record it already holds. The server refuses the
  /// effective verdict on the same rule; this is what lets a dialog say so
  /// before the request rather than after it.
  bool get bothChainsAnswered =>
      capaChainOrder.every((chain) => rootCauseOf(chain) != null);

  /// One 6M category's own causes, in the order the team wrote them (issue
  /// #213) — what a fishbone's bone is drawn with. The server's list is already
  /// ordered by category; this is the filter a Screen renders one bone with,
  /// kept here so the Screen is not the second place that knows the order is.
  List<CapaCause> causesIn(String category) =>
      [for (final cause in causes) if (cause.category == category) cause];

  /// The causes the evidence backed (issue #213) — the ones a chain may be
  /// started from, whatever else is on the fishbone.
  List<CapaCause> get confirmedCauses =>
      [for (final cause in causes) if (cause.isConfirmed) cause];

  /// Whether a chain has been started yet: its first Why is written, so which
  /// cause it began from has been decided (issue #213). A closed question,
  /// which is why the Screen reads it rather than offering the choice again.
  bool chainHasStarted(String chain) => whysIn(chain).isNotEmpty;

  /// The chains that have not started yet — the choice a "start a chain from
  /// this cause" form offers, which is empty exactly when every chain has been
  /// begun and the act is no longer available.
  List<String> get chainsNotStarted => [
        for (final chain in capaChainOrder)
          if (!chainHasStarted(chain)) chain,
      ];
}

/// One read of the CAPA list (issue #211) — the rows and whether the server had
/// more than it was willing to send, the shape `ActionRegister` keeps. Rendered,
/// never swallowed: a capped list must not read as the whole Platform.
@immutable
class CapaRegister {
  const CapaRegister({required this.capas, required this.truncated});

  final List<Capa> capas;
  final bool truncated;
}
