import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, MethodDeclaration> methods(String s) => {
  for (final c in parseString(
    content: s,
  ).unit.declarations.whereType<ClassDeclaration>())
    for (final m in c.members.whereType<MethodDeclaration>()) m.name.lexeme: m,
};

class _Transport extends RecursiveAstVisitor<void> {
  final calls = <String>[];
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target?.toSource() == 'client' ||
        ['_client', '_loadSession'].contains(node.methodName.name)) {
      calls.add(node.toSource());
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  final before = File(
    'test/driver/fixtures/driver_ride_alert_before_host.txt',
  ).readAsStringSync();
  final raw = File('lib/driver/driver_ride_offer_host.dart').readAsStringSync();
  final restored = raw.replaceAll(
    '_alerts.stop(owner: this);',
    'unawaited(DriverRideAlert.stop());',
  );
  final old = methods(before), current = methods(restored);
  test(
    'Decision transport and authenticated actor guards survive lifecycle decision memory',
    () {
      final before = _Transport(), after = _Transport();
      old['_decide']!.accept(before);
      current['_decide']!.accept(after);
      expect(after.calls, before.calls);
      final body = current['_decide']!.body.toSource();
      for (final guard in [
        '!_visible', '_busy', 'offer == null', 'token == null',
        'action != _pendingAction', 'epoch != _viewEpoch',
        '!_sameOwner(owner, session)', '!_sameOwner(session, _sessions.value)',
        'session?.driverSessionToken != token', 'session?.assignedVehicleId != offer.vehicleId',
        "throw StateError('offer_expired')",
      ]) {
        expect(body, contains(guard), reason: guard);
      }
    },
  );
  test(
    'Offer polling, receipt, readiness and withdrawal use identical server calls and arguments',
    () {
      for (final name in ['_poll', '_suspendDelivery']) {
        final a = _Transport(), b = _Transport();
        old[name]!.accept(a);
        current[name]!.accept(b);
        expect(b.calls, a.calls, reason: name);
      }
    },
  );
  test(
    'Existing polling cadence stays single; alert sound no longer repeats every five ticks',
    () {
      expect(RegExp(r'Timer\.periodic').allMatches(raw), hasLength(1));
      expect(raw, isNot(contains('_ticks % 5')));
      expect(raw, isNot(contains('DriverRideAlert.play()')));
    },
  );
}
