import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';

CompanyAgendaRide _ride(String id, {String customer = 'Ada'}) {
  return CompanyAgendaRide(
    bookingId: id,
    customerId: 'cus_1',
    customerName: customer,
    fromAddress: 'Gent',
    toAddress: 'Brussel',
    pickupIso: '2026-09-11T08:00:00.000Z',
    status: 'PENDING',
    assignedDriverId: '',
    assignedVehicleId: '',
    durationUnknown: true,
  );
}

CompanyCustomer _customer() {
  return parseCompanyCustomer(<String, dynamic>{
    'customer_id': 'cus_1',
    'display_name': 'Ada Lovelace',
    'status': 'active',
    'revision': 1,
    'email': 'ada@example.test',
  });
}

void main() {
  test('period cache is reused until a write or company switch', () async {
    var lists = 0;
    String companyId = 'demo_company_p0';
    final seen = <String>[];
    final repo = CompanyAgendaRepository(
      scopeResolver: () => <String, String>{
        'tenant_id': companyId,
        'company_id': companyId,
      },
      listTransport: (period) async {
        lists += 1;
        seen.add('$companyId|${period.view.name}');
        return <CompanyAgendaRide>[_ride('agb_$companyId')];
      },
      createTransport: ({required draft, required idempotencyKey}) async {
        return _ride('agb_new');
      },
    );
    final week = companyAgendaPeriodFor(
      view: CompanyAgendaView.week,
      anchorLocal: DateTime(2026, 9, 11),
    );
    final first = await repo.listPeriod(week);
    final second = await repo.listPeriod(week);
    expect(lists, 1);
    expect(first.single.bookingId, 'agb_demo_company_p0');
    expect(second.single.bookingId, 'agb_demo_company_p0');

    await repo.createRide(
      draft: CompanyRidePlanDraft(
        customer: _customer(),
        pickupLocal: DateTime(2026, 9, 11, 10),
        fromAddress: 'Gent',
        toAddress: 'Brussel',
      ),
      idempotencyKey: 'k1',
    );
    await repo.listPeriod(week);
    expect(lists, 2);

    companyId = 'demo_company_p1';
    final other = await repo.listPeriod(week);
    expect(lists, 3);
    expect(other.single.bookingId, 'agb_demo_company_p1');
    expect(seen, <String>[
      'demo_company_p0|week',
      'demo_company_p0|week',
      'demo_company_p1|week',
    ]);
  });
}
