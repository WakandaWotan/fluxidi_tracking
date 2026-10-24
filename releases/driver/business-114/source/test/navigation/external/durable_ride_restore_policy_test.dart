import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/durable_ride_restore_policy.dart';

void main() {
  String? decide({
    bool record = true,
    bool actor = true,
    String status = 'IN_PROGRESS',
    bool street = true,
    String trip = 'trip-1',
    bool finalizing = false,
    String leg = '',
    String serverLeg = '',
  }) => durableRideRestoreBlockReason(
    serverRecordFound: record,
    actorAllowed: actor,
    serverStatus: status,
    isStreet: street,
    trackingTripId: trip,
    finalizePending: finalizing,
    expectedLegId: leg,
    actualLegId: serverLeg,
  );
  test(
    'crashed local street snapshot with no server binding cannot activate',
    () {
      expect(
        decide(record: false, actor: false, trip: ''),
        'server_binding_missing',
      );
    },
  );
  test('missing tracking identity cannot activate a street meter', () {
    expect(decide(trip: ''), 'tracking_identity_missing');
  });
  test('different driver or vehicle cannot take over a persisted ride', () {
    expect(decide(actor: false), 'assignment_mismatch');
  });
  test('correct booking but different operational leg cannot activate', () {
    expect(decide(leg: 'return', serverLeg: 'outbound'), 'leg_mismatch');
  });
  test('terminal and unstarted server rides cannot restart the meter', () {
    for (final status in [
      'COMPLETED',
      'CANCELLED',
      'FAILED',
      'PENDING',
      'ASSIGNED',
      '',
    ]) {
      expect(decide(status: status), 'server_not_active', reason: status);
    }
  });
  test('pending stop finalization cannot resume an active ride', () {
    expect(decide(finalizing: true), 'finalization_pending');
  });
  test('verified live direct ride restores with exact assignment and trip', () {
    expect(decide(), isNull);
    expect(decide(status: ' in_progress '), isNull);
  });
  test('verified planned return uses the exact stored leg', () {
    expect(decide(street: false, leg: 'return', serverLeg: 'return'), isNull);
  });
}
