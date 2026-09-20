import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importRe = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');

Set<String> reachableLibDartFromMain(Directory packageRoot) {
  final libRoot = Directory('${packageRoot.path}${Platform.pathSeparator}lib');
  final seen = <String>{'lib/main.dart'};
  final queue = <String>['lib/main.dart'];

  String normalize(String path) {
    final parts = <String>[];
    for (final seg in path.replaceAll('\\', '/').split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return parts.join('/');
  }

  while (queue.isNotEmpty) {
    final file = queue.removeAt(0);
    final abs = File('${packageRoot.path}${Platform.pathSeparator}$file');
    if (!abs.existsSync()) continue;
    for (final line in abs.readAsLinesSync()) {
      final match = _importRe.firstMatch(line);
      if (match == null) continue;
      final ref = match.group(1)!;
      if (ref.startsWith('dart:')) continue;
      String? target;
      if (ref.startsWith('package:fluxidi_tracking/')) {
        target = 'lib/${ref.substring('package:fluxidi_tracking/'.length)}';
      } else if (!ref.startsWith('package:')) {
        final dir = file.contains('/')
            ? file.substring(0, file.lastIndexOf('/'))
            : '';
        target = normalize(dir.isEmpty ? ref : '$dir/$ref');
      }
      if (target == null || !target.startsWith('lib/') || !target.endsWith('.dart')) {
        continue;
      }
      if (seen.add(target)) queue.add(target);
    }
  }

  // Touch libRoot so a missing lib/ fails loudly.
  if (!libRoot.existsSync()) {
    throw StateError('missing lib/ at ${packageRoot.path}');
  }
  return seen;
}

void main() {
  test('customer airport quote files are reachable from main.dart', () {
    final root = Directory.current;
    final reachable = reachableLibDartFromMain(root);
    const required = <String>[
      'lib/customer_booking/customer_booking_flow.dart',
      'lib/customer_booking/customer_booking_addresses.dart',
      'lib/customer_booking/customer_booking_quote_wire.dart',
      'lib/customer_booking/customer_booking_submit.dart',
      'lib/customer_booking/customer_booking_labels.dart',
      'lib/company/company_plan_quote.dart',
    ];
    for (final path in required) {
      expect(reachable.contains(path), isTrue, reason: '$path is not imported from main.dart');
    }
    expect(
      reachable.contains('lib/airport/airport_page.dart'),
      isFalse,
      reason:
          'lib/airport/airport_page.dart is still dead code; do not ship airport fixes there',
    );
  });
}
