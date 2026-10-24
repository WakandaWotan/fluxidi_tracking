// BILLIT-CONSUMER-PROD-CREATE-1 — manual "Registreren in Billit" visibility.
//
// Consumer-sale invoices reach Billit through the same canonical create engine
// as business invoices, so the UI must no longer hide the manual recovery
// action for them. These are source-wiring assertions (the documents section is
// a private stateful widget deep inside main_parts), matching the convention
// already used by consumer_billit_document_ui_wiring_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

/// Returns the body of a method, from its signature up to the matching close.
///
/// The parameter list is skipped first: a named-parameter block (`{ ... }`)
/// would otherwise be mistaken for the method body.
String _extractBlock(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'missing $signature');

  final parenOpen = source.indexOf('(', start);
  expect(parenOpen, isNot(-1), reason: 'no parameter list for $signature');
  var parenDepth = 0;
  var parenClose = -1;
  for (var i = parenOpen; i < source.length; i++) {
    if (source[i] == '(') parenDepth++;
    if (source[i] == ')') {
      parenDepth--;
      if (parenDepth == 0) {
        parenClose = i;
        break;
      }
    }
  }
  expect(parenClose, isNot(-1), reason: 'unbalanced parens for $signature');

  final open = source.indexOf('{', parenClose);
  expect(open, isNot(-1), reason: 'no body for $signature');
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('unbalanced braces for $signature');
}

void main() {
  late String docs;
  late String block;
  late String predicate;

  setUpAll(() {
    docs = _read('lib/main_parts/company_booking_documents_section.dart');
    block = _extractBlock(docs, 'Widget _buildBillitNotLinkedYetBlock(');
    predicate = _extractBlock(docs, 'bool _shouldShowBillitNotLinkedYet(');
  });

  test('consumer sales are no longer excluded from the register action', () {
    // The registerDoc binding decides whether the button subtree is built.
    final match = RegExp(
      r'registerDoc\s*=\s*([\s\S]*?);',
    ).firstMatch(block);
    expect(match, isNotNull, reason: 'registerDoc binding not found');
    final binding = match!.group(1)!;

    // The old gate was: (!isConsumer && doc != null && ...).
    expect(
      binding.contains('!isConsumer'),
      isFalse,
      reason: 'consumer sales must not be excluded from manual register',
    );
    // Still requires a real document id.
    expect(binding, contains('doc != null'));
    expect(binding, contains('doc.documentId.trim().isNotEmpty'));
  });

  test('the register button is wired to the canonical register handler', () {
    expect(block, contains('registerDoc != null'));
    expect(block, contains('_registerBillitOrder(registerDoc)'));
    expect(block, contains('Registreren in Billit'));
    expect(block, contains('Bezig met registreren…'));
    // In-flight state disables the button for that one document only.
    expect(block, contains('_registeringBillitDocIds.contains'));
    expect(
      RegExp(r'registering\s*\?\s*null\s*:').hasMatch(block),
      isTrue,
      reason:
          'In-flight register must disable the button via onPressed: null. '
          'The ternary may be wrapped across lines.',
    );
  });

  test('the block (and therefore the button) hides once Billit is linked', () {
    // Only issued invoices with no Billit order id render the block at all, so
    // a linked consumer sale falls through to the linked-status block instead.
    expect(predicate, contains("doc.documentType.trim().toLowerCase() != 'invoice'"));
    expect(predicate, contains("state != 'issued'"));
    expect(predicate, contains('export.orderId.trim().isNotEmpty'));
  });

  test('business invoice wording and consumer wording both remain', () {
    expect(block, contains('Koppel handmatig in Billit (auto-aanmaak staat uit)'));
    expect(block, contains('Nog niet geregistreerd in Billit'));
    // Peppol stays not-applicable for private sales.
    expect(block, contains('Peppol is niet van toepassing op particuliere verkoop.'));
  });

  test('manual register never sends Peppol and surfaces a reconnect hint', () {
    final handler = _extractBlock(docs, 'Future<void> _registerBillitOrder(');
    expect(handler, contains('/billit/register'));
    expect(handler, contains('confirm_billit_register'));
    // The register call must not touch any send/Peppol endpoint.
    expect(handler.contains('peppol/send'), isFalse);
    expect(handler.contains('commands/send'), isFalse);
    // Disconnected Billit tells the user to reconnect rather than failing blind.
    expect(handler, contains('billit_party_id_missing'));
    expect(handler, contains('billit_oauth_not_configured'));
    expect(handler, contains('Billit is niet verbonden.'));
  });
}
