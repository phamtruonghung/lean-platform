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
