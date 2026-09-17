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
    this.problemStatement,
    this.orgUnitCode,
    this.teamLead,
    this.openedAt,
    this.dueDate,
    this.closedAt,
    this.effectivenessCheckDueAt,
    this.effectivenessVerifiedAt,
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

  final DateTime? openedAt;
  final String? dueDate;
  final DateTime? closedAt;

  /// When the effectiveness check falls due, and how it was answered — null
  /// until #211 records one. Carried here so the Screen can say "not yet" about
  /// a fact it will soon have.
  final String? effectivenessCheckDueAt;
  final DateTime? effectivenessVerifiedAt;
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
}
