/// One Defect code, as `GET /api/quality/defect-codes` sends it
/// (defect-codes.js's own `toDefectCode`).
///
/// CONTEXT.md's **Defect code**: the kind of thing found wrong on a
/// Non-conformance, chosen from one list shared by every Site and maintained
/// by an administrator, so the same failure carries the same code wherever it
/// happens — and each code carries the severity a Non-conformance recorded
/// against it starts at. Codes form a tree, which is why [parentId] is here
/// rather than in a nested payload: the API sends the tree flat, each row
/// naming its own parent, and [defectCodeTree] below is where the client turns
/// that into the shape a person reads.
library;

import 'package:flutter/foundation.dart';

@immutable
class DefectCode {
  const DefectCode({
    required this.id,
    required this.parentId,
    required this.code,
    required this.name,
    required this.category,
    required this.defaultSeverity,
    required this.isActive,
  });

  factory DefectCode.fromJson(Map<String, dynamic> json) => DefectCode(
        id: json['id'].toString(),
        parentId: json['parentId']?.toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        category: json['category'] as String? ?? DefectCategory.product,
        defaultSeverity: json['defaultSeverity'] as String? ?? DefectSeverity.minor,
        isActive: json['isActive'] == true,
      );

  final String id;

  /// The code this one sits beneath, or null at the top of the tree.
  final String? parentId;

  final String code;
  final String name;
  final String category;
  final String defaultSeverity;
  final bool isActive;
}

/// The categories a Defect code falls under — the baseline's own
/// `defect_codes_defect_category_check`, repeated here so the form offers the
/// set rather than letting a caller invent one (ADR-0023: a value with a known
/// set is chosen, never typed). A category is a grouping of codes, not a code
/// (CONTEXT.md's own distinction), which is why this is a property of a code
/// and not a record of its own.
abstract final class DefectCategory {
  static const String product = 'product';
  static const String process = 'process';
  static const String material = 'material';
  static const String documentation = 'documentation';
  static const String packaging = 'packaging';

  static const List<String> values = [product, process, material, documentation, packaging];

  /// The category as a person reads it — 'Product', 'Documentation'.
  static String label(String category) =>
      category.isEmpty ? category : category[0].toUpperCase() + category.substring(1);
}

/// The severities a Defect code can start a Non-conformance at — the
/// baseline's own `defect_codes_default_severity_check`, and the same three
/// the Non-conformance's own severity column accepts.
abstract final class DefectSeverity {
  static const String minor = 'minor';
  static const String major = 'major';
  static const String critical = 'critical';

  static const List<String> values = [minor, major, critical];

  static String label(String severity) =>
      severity.isEmpty ? severity : severity[0].toUpperCase() + severity.substring(1);
}

/// One row of the tree as a Screen reads it: the code, and how deep it sits.
///
/// `defect_codes` is a self-referencing table with no path column — the
/// baseline gives it none — so the shape is re-derived here from each row's
/// [DefectCode.parentId] rather than sent. A code is placed immediately after
/// its own parent, and [depth] is the number of parents above it.
@immutable
class DefectCodeRow {
  const DefectCodeRow({required this.code, required this.depth, required this.parentName});

  final DefectCode code;
  final int depth;

  /// The parent's own name, for a row that says where it sits — the tree is
  /// read on a card rather than in a tree view, so indentation alone would not
  /// name a parent whose row is off screen.
  final String? parentName;
}

/// The ids of [id] and every code beneath it — the set a Defect code cannot be
/// moved under.
///
/// The API refuses that link (400, defect-codes.js's own cycle refusal) and is
/// the authority on it; this exists so the form's own parent choice never
/// offers a descendant in the first place, rather than offering one and
/// reporting a refusal the caller could not have known about. A cycle cannot
/// exist (the API refuses one), and this guards anyway: a code is visited once.
Set<String> defectCodeDescendantsOf(List<DefectCode> codes, String id) {
  final children = <String, List<String>>{};
  for (final code in codes) {
    if (code.parentId == null) continue;
    children.putIfAbsent(code.parentId!, () => <String>[]).add(code.id);
  }

  final found = <String>{};
  void visit(String current) {
    if (!found.add(current)) return;
    for (final child in children[current] ?? const <String>[]) {
      visit(child);
    }
  }

  visit(id);
  return found;
}

/// Flattens [codes] into the order a tree is read: each code directly after
/// its own parent, with the depth it sits at.
///
/// Total by construction. A code whose parent is not in [codes] (a deactivated
/// parent, which the catalogue deliberately allows, or a parent the caller did
/// not ask for) is treated as a root rather than dropped — the same refusal to
/// discard a row ADR-0008's entry points make in the Org Unit tree. A cycle
/// cannot exist (the API refuses one) but is still guarded: a code already
/// placed is never placed twice, and any row left over is appended at the top
/// level rather than silently disappearing.
List<DefectCodeRow> defectCodeTree(List<DefectCode> codes) {
  final byId = {for (final code in codes) code.id: code};
  final children = <String?, List<DefectCode>>{};
  for (final code in codes) {
    // A parent that is not in this list is no parent as far as the shape goes.
    final parentId = byId.containsKey(code.parentId) ? code.parentId : null;
    children.putIfAbsent(parentId, () => <DefectCode>[]).add(code);
  }
  for (final list in children.values) {
    list.sort((a, b) => a.code.compareTo(b.code));
  }

  final rows = <DefectCodeRow>[];
  final placed = <String>{};

  void place(DefectCode code, int depth, String? parentName) {
    if (!placed.add(code.id)) return;
    rows.add(DefectCodeRow(code: code, depth: depth, parentName: parentName));
    for (final child in children[code.id] ?? const <DefectCode>[]) {
      place(child, depth + 1, code.name);
    }
  }

  for (final root in children[null] ?? const <DefectCode>[]) {
    place(root, 0, null);
  }
  for (final code in codes) {
    place(code, 0, null);
  }
  return rows;
}
