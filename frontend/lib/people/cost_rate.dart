/// One cost rate, as `GET /api/people/cost-rates` sends it (issue #252,
/// `cost-rates.js`'s own `toCostRate`), plus the two known sets a rate is
/// chosen from and the scope list it is attached to.
///
/// CONTEXT.md has no entry of its own for this: a cost rate is the money the
/// Platform costs a thing at — an hour of labour, an hour a machine is down,
/// the premium on an overtime hour — scoped to a Site, an Org Unit, an Asset or
/// a cost centre, and versioned, so a rate revised in October does not rewrite
/// September's cost of poor quality. One catalogue shared by every Site
/// (ADR-0005), maintained by an administrator.
///
/// The rate that actually applies somewhere is not the nearest row in this
/// list: `resolve_cost_rate` falls back from the Asset to the nearest ancestor
/// Org Unit to the Site, in the database, and
/// `GET /api/people/cost-rates/resolution` is what answers it. Nothing on the
/// client re-spells that rule.
library;

import 'package:flutter/foundation.dart';

/// The four scope types the schema accepts, verbatim from `cost_rates`' own
/// CHECK — one place for them, the same reason `employmentTypes` is a single
/// list rather than a copy inside every dialog that offers one.
const List<String> costRateScopeTypes = ['site', 'org_unit', 'asset', 'cost_center'];

/// The five rate types the schema accepts, verbatim from the same CHECK.
const List<String> costRateTypes = [
  'labor_per_hour',
  'overtime_premium_multiplier',
  'machine_downtime_per_hour',
  'overhead_per_hour',
  'rework_labor_per_hour',
];

/// What a scope type is called on screen. The words are the plant's, not the
/// column's — `cost_center` is a cost centre to a person reading the page.
String costRateScopeTypeLabel(String scopeType) => switch (scopeType) {
      'site' => 'Site',
      'org_unit' => 'Org Unit',
      'asset' => 'Asset',
      'cost_center' => 'Cost centre',
      _ => scopeType,
    };

/// What a rate type is called on screen, and what it means. The American
/// spelling in the value (`labor_`) is the schema's and is never shown.
String costRateTypeLabel(String rateType) => switch (rateType) {
      'labor_per_hour' => 'Labour, per hour',
      'overtime_premium_multiplier' => 'Overtime premium, a multiplier',
      'machine_downtime_per_hour' => 'Machine downtime, per hour',
      'overhead_per_hour' => 'Overhead, per hour',
      'rework_labor_per_hour' => 'Rework labour, per hour',
      _ => rateType,
    };

/// Whether a rate type's amount is money or a bare multiplier. The baseline
/// shares one `amount` column for both on purpose (its own comment says so:
/// 1.5 for time-and-a-half), so the currency is meaningless on the one that is
/// dimensionless and this is what stops the page printing "USD 1.5" beside it.
bool costRateIsMultiplier(String rateType) => rateType == 'overtime_premium_multiplier';

/// One thing a rate can be scoped to, as `GET /api/people/cost-rates/scopes`
/// sends it: a Site, an Org Unit, an Asset or a cost centre, each carrying its
/// own scope type. The form picks one of these, so `scopeType` and `scopeId`
/// fall out of the pick rather than being assembled from two controls that can
/// disagree (ADR-0023 — a value with a known set is chosen, never typed).
@immutable
class CostRateScope {
  const CostRateScope({
    required this.scopeType,
    required this.id,
    required this.code,
    required this.name,
    required this.siteName,
  });

  factory CostRateScope.fromJson(Map<String, dynamic> json) => CostRateScope(
        scopeType: json['scopeType'] as String,
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        siteName: json['siteName'] as String?,
      );

  final String scopeType;
  final String id;
  final String code;
  final String name;
  final String? siteName;

  /// What a suggestion row and the chosen value both read as: the name first,
  /// because that is what a person recognises, then the code they quote, then
  /// the Site so two lines called "Line 1" at two plants are not the same row.
  String get label {
    final site = siteName;
    final head = '$name · $code';
    return site == null || scopeType == 'site' ? head : '$head · $site';
  }
}

@immutable
class CostRate {
  const CostRate({
    required this.id,
    required this.scopeType,
    required this.scopeId,
    required this.scopeName,
    required this.rateType,
    required this.amount,
    required this.currency,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.note,
  });

  factory CostRate.fromJson(Map<String, dynamic> json) => CostRate(
        id: json['id'].toString(),
        scopeType: json['scopeType'] as String,
        scopeId: json['scopeId'].toString(),
        scopeName: json['scopeName'] as String?,
        rateType: json['rateType'] as String,
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String,
        effectiveFrom: json['effectiveFrom'] as String,
        effectiveTo: json['effectiveTo'] as String?,
        note: json['note'] as String?,
      );

  final String id;
  final String scopeType;
  final String scopeId;

  /// The scoped record's own name, or null when that record has since been
  /// deleted — the rate is still history worth reading.
  final String? scopeName;

  final String rateType;
  final double amount;
  final String currency;

  /// The day this rate starts applying, as `YYYY-MM-DD`.
  final String effectiveFrom;

  /// The day it stops, exclusive — null means it is still current. A rate is
  /// never deleted: it is closed, and a successor opened.
  final String? effectiveTo;

  final String? note;

  bool get isCurrent => effectiveTo == null;

  /// The scope as a row reads it: the record's own name where it is still
  /// there, and the kind of thing it is.
  String get scopeLabel =>
      '${scopeName ?? 'Scope $scopeId'} · ${costRateScopeTypeLabel(scopeType)}';

  /// The amount as a row reads it — money carries its currency, the overtime
  /// multiplier does not, because it is dimensionless.
  String get amountLabel =>
      costRateIsMultiplier(rateType) ? '× $amount' : '$amount $currency';

  /// The period as a row reads it. An open period says so rather than showing
  /// a blank second date, which reads as missing data.
  String get periodLabel =>
      effectiveTo == null ? 'From $effectiveFrom' : '$effectiveFrom to $effectiveTo';
}
