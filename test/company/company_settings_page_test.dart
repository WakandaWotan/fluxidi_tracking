import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_about_labels.dart';
import 'package:fluxidi_tracking/company/company_settings_page.dart';
import 'package:fluxidi_tracking/company/fluxidi_about_this_app.dart';

void main() {
  testWidgets('settings saves name back into the profile source', (
    tester,
  ) async {
    companyOpsContextGeneration = 1;
    companyOpsLocalSessionNotifier.value = const CompanyOpsLocalSession(
      companyId: 'demo_company_p0',
      sessionToken: 'tok',
    );
    var storedName = 'Fluxidi Demo Cars';
    tester.view.physicalSize = const Size(720, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.enterText(
      find.byKey(kCompanySettingsNameKey),
      'Fluxidi Demo Fleet',
    );
    await tester.ensureVisible(find.byKey(kCompanySettingsSaveKey));
    await tester.tap(find.byKey(kCompanySettingsSaveKey));
    await tester.pumpAndSettle();
    expect(storedName, 'Fluxidi Demo Fleet');
    expect(companyOpsIdentityNotifier.value.companyName, 'Fluxidi Demo Fleet');
    await tester.drag(find.byKey(kCompanySettingsListKey), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.byKey(kFluxidiAboutThisAppKey), findsOneWidget);
    expect(
      find.text(kFluxidiAboutThisAppTitle.of(AppLanguage.nl)),
      findsOneWidget,
    );
  });
}
