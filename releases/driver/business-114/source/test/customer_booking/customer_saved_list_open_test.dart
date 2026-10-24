import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_saved_list_open.dart';

void main() {
  test('a late response from a previous customer is rejected', () {
    final guard = CustomerSavedListOpenGuard();
    final first = guard.begin('customer_a');
    expect(guard.accepts(first, 'customer_a'), isTrue);

    final second = guard.begin('customer_b');
    expect(guard.accepts(first, 'customer_a'), isFalse);
    expect(guard.accepts(second, 'customer_b'), isTrue);
    expect(guard.accepts(second, 'customer_a'), isFalse);
  });

  test('a second network open joins the in-flight refresh', () async {
    final guard = CustomerSavedListOpenGuard();
    guard.begin('customer_a');
    var starts = 0;
    late final Future<void> first;
    first = guard.runExclusiveNetwork(() async {
      starts += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    final second = guard.runExclusiveNetwork(() async {
      starts += 1;
    });
    await Future.wait(<Future<void>>[first, second]);
    expect(starts, 1);
    expect(guard.hasInFlightNetwork, isFalse);
  });

  test('signed-out and empty session keys are the same identity', () {
    final guard = CustomerSavedListOpenGuard();
    final first = guard.begin('');
    expect(guard.accepts(first, null), isTrue);
    expect(guard.accepts(first, '  '), isTrue);
  });
}
