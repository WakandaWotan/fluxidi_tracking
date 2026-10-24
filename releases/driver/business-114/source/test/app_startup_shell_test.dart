import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/widgets/app_startup_shell.dart';

void main() {
  testWidgets('identity appears while restoration waits and no session screen mounts early', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(AppStartupShell(initialize: () => ready.future,
      builder: (_) => const MaterialApp(home: Text('protected dashboard'))));
    expect(find.text('FLUXIDI'), findsOneWidget);
    expect(find.text('protected dashboard'), findsNothing);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete(); await tester.pumpAndSettle();
    expect(find.text('protected dashboard'), findsOneWidget);
  });
  testWidgets('restoration error stays closed and offers retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(AppStartupShell(initialize: () async {
      if (++attempts == 1) throw StateError('storage unavailable');
    }, builder: (_) => const MaterialApp(home: Text('ready'))));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsNothing);
    await tester.tap(find.text('Opnieuw proberen')); await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
  });
}
