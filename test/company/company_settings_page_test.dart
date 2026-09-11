import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_settings_page.dart';

void main() {
  testWidgets('settings saves name back into the profile source', (tester) async {
    companyOpsContextGeneration = 1;
    companyOpsLocalSessionNotifier.value = const CompanyOpsLocalSession(
      companyId: 'demo_company_p0',
      sessionToken: 'tok',
    );
    var storedName = 'Fluxidi Demo Cars';
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(720, 900)),
        child: MaterialApp(
          home: CompanySettingsPage(
            language: AppLanguage.nl,
            profileLoader: () async => <String, dynamic>{
              'companyName': storedName,
              'phone': '+3227110000',
              'email': 'ops@demo.local',
              'country': 'BE',
            },
            profileSaver: (profile) async {
              storedName = profile['companyName']?.toString() ?? '';
              return profile;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanySettingsPageKey), findsOneWidget);
    await tester.enterText(find.byKey(kCompanySettingsNameKey), 'Fluxidi Demo Fleet');
    await tester.tap(find.byKey(kCompanySettingsSaveKey));
    await tester.pumpAndSettle();
    expect(storedName, 'Fluxidi Demo Fleet');
    expect(companyOpsIdentityNotifier.value.companyName, 'Fluxidi Demo Fleet');
  });
}
