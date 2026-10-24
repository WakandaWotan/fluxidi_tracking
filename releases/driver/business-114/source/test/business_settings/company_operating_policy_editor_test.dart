import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_operating_policy.dart';
import 'package:fluxidi_tracking/company/company_operating_policy_editor.dart';
void main(){
  testWidgets('availability can switch back without losing dispatch preferences',(tester)async{
    var value=const CompanyOperatingPolicy(deviceBinding:'vehicle',availabilitySource:'manual_duty',scheduledDispatch:'manager_first');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>SingleChildScrollView(child:
      CompanyOperatingPolicyEditor(value:value,onChanged:(next)=>setState(()=>value=next)))))));
    expect(find.textContaining('Uurroosters blijven bewaard'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('operating_availability_source')));await tester.pumpAndSettle();
    await tester.tap(find.text('Volgens uurrooster (bestaande werking)').last);await tester.pumpAndSettle();
    expect(value.availabilitySource,'existing');
    expect(value.deviceBinding,'vehicle');
    expect(value.scheduledDispatch,'manager_first');
    expect(find.textContaining('Uurroosters blijven bewaard'),findsNothing);
  });
  testWidgets('response timeout and fallback are editable without assumed company defaults',(tester)async{
    var value=const CompanyOperatingPolicy(immediateDispatch:'driver_offer');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>SingleChildScrollView(child:
      CompanyOperatingPolicyEditor(value:value,onChanged:(next)=>setState(()=>value=next)))))));
    expect(find.byKey(const ValueKey('operating_offer_seconds')),findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('operating_offer_seconds')),'60');await tester.pump();
    expect(value.offerResponseSeconds,60);
    expect(value.unansweredOffer,isNull);
    await tester.tap(find.byKey(const ValueKey('operating_unanswered_offer')));await tester.pumpAndSettle();
    await tester.tap(find.text('Naar centrale').last);await tester.pumpAndSettle();
    expect(value.unansweredOffer,'central');expect(value.validationError,isNull);
  });
  testWidgets('manager threshold edits amount without a primary car selection', (tester) async {
    var value=const CompanyOperatingPolicy(immediateDispatch:'manager_above_threshold',
      primaryReviewAboveCents:2500,offerResponseSeconds:30,unansweredOffer:'central');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>SingleChildScrollView(child:
      CompanyOperatingPolicyEditor(value:value,onChanged:(next)=>setState(()=>value=next)))))));
    expect(find.byKey(const ValueKey('operating_primary_vehicle_id')),findsNothing);
    await tester.enterText(find.byKey(const ValueKey('operating_primary_price')),'25.00');
    await tester.pump();
    expect(value.immediateDispatch,'manager_above_threshold');
    expect(value.primaryReviewAboveCents,2500);
    expect(value.primaryVehicleId,isNull);
    expect(value.validationError,isNull);
    expect(tester.takeException(),isNull);
  });

}
