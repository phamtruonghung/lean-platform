/// The employment types an Employee can be given (issue #87), mirroring the
/// backend's own list verbatim (`EMPLOYMENT_TYPES`, directory.js) — one place
/// for it, the same reason `role_choice.dart`'s `admissionRoles` is a single
/// list rather than a copy inside every dialog that offers a role.
library;

const List<String> employmentTypes = [
  'permanent',
  'temporary',
  'agency',
  'contractor',
  'apprentice',
];

/// The label for [employmentType] — a plain capitalised form, since none of
/// these five words need more explaining than that.
String employmentTypeLabel(String employmentType) => employmentType.isEmpty
    ? employmentType
    : '${employmentType[0].toUpperCase()}${employmentType.substring(1)}';
