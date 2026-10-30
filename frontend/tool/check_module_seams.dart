// Fails when a client Module imports another Module's internals (ADR-0012).
//
//     dart run tool/check_module_seams.dart      # from frontend/
//
// The client's Modules are the directories below. A file inside one of them
// may import: its own Module's files, `platform/`, `widgets/`, `auth/`, any
// file directly under `lib/` (theme, status_tone, people_api, ...), and
// ANOTHER Module only through that Module's entry point,
// `lib/<module>/<module>.dart`. Files directly under `lib/` and `platform/`
// are the wiring layer (like backend `src/index.js`) and may import anything.
import 'dart:io';

const modules = {'people', 'maintenance', 'quality', 'safety', 'actions', 'production', 'kpi'};

final directive =
    RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

void main() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('run from frontend/ (lib/ not found)');
    exit(2);
  }
  final violations = <String>[];
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final segments = entity.uri.pathSegments;
    final rel = segments.sublist(segments.indexOf('lib') + 1);
    if (rel.length < 2 || !modules.contains(rel.first)) continue;
    final own = rel.first;
    final src = entity.readAsStringSync();
    for (final m in directive.allMatches(src)) {
      final uri = m.group(1)!;
      String? target;
      if (uri.startsWith('package:lean_platform/')) {
        target = uri.substring('package:lean_platform/'.length);
      } else if (!uri.contains(':')) {
        target = Uri(pathSegments: [...rel.sublist(0, rel.length - 1), ''])
            .resolve(uri)
            .path;
      }
      if (target == null) continue;
      final parts = target.split('/');
      if (parts.length < 2 || !modules.contains(parts.first)) continue;
      final other = parts.first;
      if (other == own) continue;
      if (parts.length == 2 && parts[1] == '$other.dart') continue;
      violations.add('${entity.path}: imports $uri '
          '(use lib/$other/$other.dart)');
    }
  }
  if (violations.isEmpty) {
    stdout.writeln('module seams ok');
    return;
  }
  violations.sort();
  stderr.writeln('Module seam violations (ADR-0012):');
  violations.forEach(stderr.writeln);
  stderr.writeln('${violations.length} violation(s)');
  exit(1);
}
