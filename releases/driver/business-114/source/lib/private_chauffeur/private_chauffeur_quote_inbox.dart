// Company inbox for Privéchauffeur. Reuses the limousine quote endpoints
// with service=private_chauffeur so a company without a limousine offer can
// answer the request. This is not a second quote platform.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

const String kPrivateChauffeurServiceCode = 'private_chauffeur';

bool isPrivateChauffeurServiceToken(String raw) {
  final token = raw.trim().toLowerCase();
  return token == 'private_chauffeur' ||
      token == 'prive_chauffeur' ||
      token == 'privechauffeur';
}

class PrivateChauffeurInboxItem {
  const PrivateChauffeurInboxItem({
    required this.id,
    required this.from,
    required this.to,
    required this.state,
    this.durationMinutes,
    this.customerNote = '',
    this.revision = 1,
  });

  final String id;
  final String from;
  final String to;
  final String state;
  final int? durationMinutes;
  final String customerNote;
  final int revision;
}

class PrivateChauffeurInboxPage {
  const PrivateChauffeurInboxPage({this.items = const <PrivateChauffeurInboxItem>[]});

  final List<PrivateChauffeurInboxItem> items;
}

Uri privateChauffeurInboxUri({
  required String bookingBaseUrl,
  String? tenantId,
  String? companyId,
}) {
  return adminTenantCompanyScopedUri(
    Uri.parse(
      '${bookingBaseUrl.trim()}/admin/limousine/quote-requests',
    ).replace(
      queryParameters: const <String, String>{
        'service': kPrivateChauffeurServiceCode,
        'page_size': '20',
      },
    ),
    tenantId: tenantId,
    companyId: companyId,
  );
}

Map<String, dynamic> privateChauffeurCompanyQuoteBody({
  required String quoteRequestId,
  required int expectedRevision,
  required int totalInclVatCents,
  Map<String, String> scope = const <String, String>{},
}) {
  return <String, dynamic>{
    ...scope,
    'service': kPrivateChauffeurServiceCode,
    'service_type': kPrivateChauffeurServiceCode,
    'quote_request_id': quoteRequestId.trim(),
    'action': 'quote',
    'expected_revision': expectedRevision,
    'total_incl_vat_cents': totalInclVatCents,
    'currency': 'EUR',
    'terms': <String, dynamic>{
      'terms_revision': 1,
      'cancellation_deadline_hours': 24,
      'cancellation_penalty_percent': 50,
      'waiting_time_included_minutes': 15,
      'waiting_time_overage_cents_per_minute': 100,
      'no_show_penalty_percent': 100,
      'overtime_cents_per_hour': 9000,
      'mobilisation_disclosure': <String, String>{
        'nl': 'Aanrijden inbegrepen',
      },
    },
  };
}

int? _intOf(Object? raw) {
  if (raw is num && raw.isFinite) return raw.round();
  return int.tryParse((raw ?? '').toString().trim());
}

Map<String, dynamic>? _mapOf(Object? raw) {
  if (raw is! Map) return null;
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

List<PrivateChauffeurInboxItem> privateChauffeurInboxItemsFromJson(
  Map<String, dynamic> body,
) {
  final raw = body['items'];
  if (raw is! List) return const <PrivateChauffeurInboxItem>[];
  final items = <PrivateChauffeurInboxItem>[];
  for (final row in raw) {
    final map = _mapOf(row);
    if (map == null) continue;
    final service = (map['service_type'] ?? map['service'] ?? '').toString();
    if (!isPrivateChauffeurServiceToken(service)) continue;
    final fulfilment = _mapOf(map['fulfilment']) ?? map;
    final id = (map['quote_request_id'] ?? map['id'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    items.add(
      PrivateChauffeurInboxItem(
        id: id,
        from: (fulfilment['from'] ?? '').toString(),
        to: (fulfilment['to'] ?? '').toString(),
        state: (map['state'] ?? '').toString(),
        durationMinutes: _intOf(
          fulfilment['requested_duration_minutes'] ??
              map['requested_duration_minutes'],
        ),
        customerNote: (fulfilment['customer_note'] ?? map['customer_note'] ?? '')
            .toString(),
        revision: _intOf(map['revision']) ?? 1,
      ),
    );
  }
  return items;
}

abstract class PrivateChauffeurInboxGateway {
  Future<PrivateChauffeurInboxPage> list({String? tenantId, String? companyId});

  Future<void> sendQuote({
    required String quoteRequestId,
    required int expectedRevision,
    required int totalInclVatCents,
    String? tenantId,
    String? companyId,
  });
}

class MemoryPrivateChauffeurInboxGateway implements PrivateChauffeurInboxGateway {
  MemoryPrivateChauffeurInboxGateway({this.items = const <PrivateChauffeurInboxItem>[]});

  List<PrivateChauffeurInboxItem> items;
  int listCalls = 0;
  int quoteCalls = 0;
  Map<String, dynamic>? lastQuoteBody;
  Uri? lastListUri;

  @override
  Future<PrivateChauffeurInboxPage> list({
    String? tenantId,
    String? companyId,
  }) async {
    listCalls += 1;
    final scoped = (tenantId ?? '').trim().isNotEmpty &&
        (companyId ?? '').trim().isNotEmpty;
    lastListUri = scoped
        ? privateChauffeurInboxUri(
            bookingBaseUrl: 'https://booking.test',
            tenantId: tenantId,
            companyId: companyId,
          )
        : Uri.parse(
            'https://booking.test/admin/limousine/quote-requests',
          ).replace(
            queryParameters: const <String, String>{
              'service': kPrivateChauffeurServiceCode,
              'page_size': '20',
            },
          );
    return PrivateChauffeurInboxPage(items: items);
  }

  @override
  Future<void> sendQuote({
    required String quoteRequestId,
    required int expectedRevision,
    required int totalInclVatCents,
    String? tenantId,
    String? companyId,
  }) async {
    quoteCalls += 1;
    final scoped = (tenantId ?? '').trim().isNotEmpty &&
        (companyId ?? '').trim().isNotEmpty;
    lastQuoteBody = privateChauffeurCompanyQuoteBody(
      quoteRequestId: quoteRequestId,
      expectedRevision: expectedRevision,
      totalInclVatCents: totalInclVatCents,
      scope: scoped
          ? adminTenantCompanyScope(tenantId: tenantId, companyId: companyId)
          : const <String, String>{},
    );
  }
}

class HttpPrivateChauffeurInboxGateway implements PrivateChauffeurInboxGateway {
  HttpPrivateChauffeurInboxGateway({http.Client? client, String? bookingBaseUrl})
    : _client = client,
      _bookingBaseUrl = bookingBaseUrl;

  final http.Client? _client;
  final String? _bookingBaseUrl;

  String get _base => (_bookingBaseUrl ?? appConfig.bookingBaseUrl).trim();

  @override
  Future<PrivateChauffeurInboxPage> list({
    String? tenantId,
    String? companyId,
  }) async {
    final uri = privateChauffeurInboxUri(
      bookingBaseUrl: _base,
      tenantId: tenantId,
      companyId: companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders(json: false);
    final client = _client;
    final res = client == null
        ? await http.get(uri, headers: auth.headers).timeout(const Duration(seconds: 12))
        : await client.get(uri, headers: auth.headers).timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded is! Map) {
      throw StateError('private_chauffeur_inbox_load_failed');
    }
    if (decoded['ok'] == false) throw StateError('private_chauffeur_inbox_load_failed');
    return PrivateChauffeurInboxPage(
      items: privateChauffeurInboxItemsFromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }

  @override
  Future<void> sendQuote({
    required String quoteRequestId,
    required int expectedRevision,
    required int totalInclVatCents,
    String? tenantId,
    String? companyId,
  }) async {
    final body = privateChauffeurCompanyQuoteBody(
      quoteRequestId: quoteRequestId,
      expectedRevision: expectedRevision,
      totalInclVatCents: totalInclVatCents,
      scope: adminTenantCompanyScope(tenantId: tenantId, companyId: companyId),
    );
    final uri = adminTenantCompanyScopedUri(
      Uri.parse('$_base/admin/limousine/quote-requests/respond'),
      tenantId: tenantId,
      companyId: companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders();
    final encoded = jsonEncode(body);
    final client = _client;
    final response = client == null
        ? await http.post(uri, headers: auth.headers, body: encoded).timeout(const Duration(seconds: 15))
        : await client.post(uri, headers: auth.headers, body: encoded).timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded is! Map || decoded['ok'] != true) {
      throw StateError('private_chauffeur_quote_not_confirmed');
    }
  }
}

class PrivateChauffeurQuoteInboxPanel extends StatefulWidget {
  const PrivateChauffeurQuoteInboxPanel({super.key, this.gateway});

  final PrivateChauffeurInboxGateway? gateway;

  @override
  State<PrivateChauffeurQuoteInboxPanel> createState() =>
      _PrivateChauffeurQuoteInboxPanelState();
}

class _PrivateChauffeurQuoteInboxPanelState
    extends State<PrivateChauffeurQuoteInboxPanel> {
  late final PrivateChauffeurInboxGateway _gateway;
  List<PrivateChauffeurInboxItem> _items = const <PrivateChauffeurInboxItem>[];
  final TextEditingController _cents = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? HttpPrivateChauffeurInboxGateway();
  }

  @override
  void dispose() {
    _cents.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final page = await _gateway.list();
      if (!mounted) return;
      setState(() => _items = page.items);
    } catch (_) {
      if (mounted) setState(() => _error = 'Aanvragen konden niet worden geladen. Probeer opnieuw.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quote(PrivateChauffeurInboxItem item) async {
    if (_busy) return;
    final cents = int.tryParse(_cents.text.trim());
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Vul eerst een geldig offertebedrag in.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    var confirmed = false;
    try {
      await _gateway.sendQuote(quoteRequestId: item.id, expectedRevision: item.revision, totalInclVatCents: cents);
      confirmed = true;
    } catch (_) {
      if (mounted) setState(() => _error = 'De offerte is niet bevestigd. Controleer de aanvragen voordat je opnieuw verzendt.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && confirmed) { _cents.clear(); await _load(); }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) Text(_error!, key: const Key('private_chauffeur_inbox_error')),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: const Key('private_chauffeur_inbox_load'),
            onPressed: _busy ? null : _load,
            child: const Text('Aanvragen bekijken'),
          ),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('private_chauffeur_inbox_cents'),
            controller: _cents,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Offertebedrag in cent',
            ),
          ),
        ],
        for (final item in _items) ...[
          const SizedBox(height: 8),
          Text(
            '${item.from} → ${item.to}',
            key: Key('private_chauffeur_inbox_route_${item.id}'),
          ),
          Text(
            'Privéchauffeur · ${item.durationMinutes ?? '-'} min',
            key: Key('private_chauffeur_inbox_service_${item.id}'),
          ),
          if (item.customerNote.isNotEmpty) Text(item.customerNote),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: Key('private_chauffeur_inbox_quote_${item.id}'),
              onPressed: _busy ? null : () => _quote(item),
              child: const Text('Offerte sturen'),
            ),
          ),
        ],
      ],
    );
  }
}
