import 'dart:convert';

import 'package:fluxidi_tracking/business/regional_demand_consistency.dart';
import 'package:http/http.dart' as http;

/// Same public endpoints the website and the existing app use.
const String kRegionInterestPath = '/region-interest';
const String kRegionInterestRadarPath = '/region-interest/radar';
const String kRegionInterestSource = 'regio_radar';

typedef RegionInterestHttpGet = Future<http.Response> Function(Uri uri);
typedef RegionInterestHttpPost =
    Future<http.Response> Function(
      Uri uri, {
      Map<String, String>? headers,
      Object? body,
    });

/// Snapshot from `GET /region-interest/radar`.
///
/// Counts come only from the server. A missing or failed response is not
/// turned into a decorative `0+`.
/// One server-supplied approximate regional cell. Never a house address.
class RegionRadarApproximateCell {
  const RegionRadarApproximateCell({
    required this.lat,
    required this.lon,
    this.displayCount = '',
    this.postcode = '',
  });

  final double lat;
  final double lon;
  final String displayCount;
  final String postcode;
}

class RegionRadarSnapshot {
  const RegionRadarSnapshot({
    required this.country,
    required this.postcode,
    this.count,
    this.displayCount = '',
    this.status = '',
    this.approximateCells = const <RegionRadarApproximateCell>[],
  });

  final String country;
  final String postcode;
  final int? count;
  final String displayCount;
  final String status;

  /// Bounded regional cells from a future radar expansion. Empty today.
  final List<RegionRadarApproximateCell> approximateCells;

  bool get hasInterest => (count ?? 0) > 0 && displayCount.trim().isNotEmpty;

  /// True when the server sent a count label. Never invent `3+`.
  bool get hasServerCount => displayCount.trim().isNotEmpty;
}

/// Reads optional `cells` from a radar body. Unknown or personal keys are ignored.
List<RegionRadarApproximateCell> parseRegionRadarApproximateCells(
  Map<String, dynamic> body,
) {
  final raw = body['cells'];
  if (raw is! List) return const <RegionRadarApproximateCell>[];
  final cells = <RegionRadarApproximateCell>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final lat = _readFinite(map['lat']);
    final lon = _readFinite(map['lon'] ?? map['lng']);
    if (lat == null || lon == null) continue;
    cells.add(
      RegionRadarApproximateCell(
        lat: lat,
        lon: lon,
        displayCount: (map['display_count'] ?? '').toString().trim(),
        postcode: (map['postcode'] ?? '').toString().trim(),
      ),
    );
  }
  return List<RegionRadarApproximateCell>.unmodifiable(cells);
}

double? _readFinite(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

/// Website-style line under the map: `Regio BE 9688: 3+ (taxibedrijven gezocht).`
///
/// [displayCount] must be the server value. An empty count omits that part
/// instead of substituting a decorative number.
String regionRadarSummaryLine({
  required String country,
  required String postcode,
  String displayCount = '',
  required String regionWord,
  required String partnersWanted,
}) {
  final head =
      '${regionWord.trim()} ${country.trim().toUpperCase()} ${postcode.trim()}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  final count = displayCount.trim();
  if (count.isEmpty) return head;
  return '$head: $count ($partnersWanted).';
}

class RegionInterestDraft {
  const RegionInterestDraft({
    required this.country,
    required this.postcode,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone = '',
    this.locale = 'nl',
  });

  final String country;
  final String postcode;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String locale;

  String get fullName =>
      <String>[firstName.trim(), lastName.trim()]
          .where((part) => part.isNotEmpty)
          .join(' ');
}

class RegionInterestSubmitResult {
  const RegionInterestSubmitResult({
    required this.ok,
    this.snapshot,
    this.errorCode = '',
    this.alreadyRegistered = false,
  });

  final bool ok;
  final RegionRadarSnapshot? snapshot;
  final String errorCode;
  final bool alreadyRegistered;
}

/// Validation that matches the booking worker and the website form.
String? regionInterestFieldError({
  required RegionInterestDraft draft,
  required String Function({
    required String nl,
    required String en,
    required String fr,
    required String es,
    required String de,
  })
  translate,
}) {
  final country = parseDemandRadarCountryCode(draft.country);
  final postcode = normalizeDemandRadarPostcode(draft.postcode);
  if (country.isEmpty || postcode.isEmpty) {
    return translate(
      nl: 'Vul een postcode in voor Regio Radar.',
      en: 'Enter a postcode for Region Radar.',
      fr: 'Saisissez un code postal pour le Radar régional.',
      es: 'Introduce un código postal para el Radar regional.',
      de: 'Geben Sie eine Postleitzahl für Region Radar ein.',
    );
  }
  if (draft.firstName.trim().isEmpty ||
      draft.lastName.trim().isEmpty ||
      !isRegionInterestEmail(draft.email)) {
    return translate(
      nl: 'Voornaam, achternaam, e-mail en postcode zijn verplicht.',
      en: 'First name, last name, email and postcode are required.',
      fr: 'Le prénom, le nom, l’e-mail et le code postal sont obligatoires.',
      es: 'Nombre, apellidos, correo y código postal son obligatorios.',
      de: 'Vorname, Nachname, E-Mail und Postleitzahl sind Pflicht.',
    );
  }
  return null;
}

bool isRegionInterestEmail(String raw) {
  final email = raw.trim();
  return email.contains('@') && email.contains('.') && email.length >= 5;
}

/// HTTP client for the shared region-interest API.
class RegionInterestClient {
  RegionInterestClient({
    required this.baseUrl,
    this.httpGet,
    this.httpPost,
  });

  final String baseUrl;
  final RegionInterestHttpGet? httpGet;
  final RegionInterestHttpPost? httpPost;

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root$path').replace(queryParameters: query);
  }

  Future<RegionRadarSnapshot> fetchRadar({
    required String country,
    required String postcode,
  }) async {
    final normalizedCountry = parseDemandRadarCountryCode(country);
    final normalizedPostcode = normalizeDemandRadarPostcode(postcode);
    if (normalizedCountry.isEmpty || normalizedPostcode.isEmpty) {
      throw const RegionInterestException('missing_region_interest_query');
    }
    final uri = _uri(kRegionInterestRadarPath, <String, String>{
      'country': normalizedCountry,
      'postcode': normalizedPostcode,
    });
    final res = await (httpGet ?? http.get)(
      uri,
    ).timeout(const Duration(seconds: 12));
    final body = _decodeMap(res.bodyBytes);
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        body == null ||
        body['ok'] != true) {
      throw RegionInterestException(
        (body?['error'] ?? 'radar_failed').toString(),
      );
    }
    return _snapshotFrom(body, normalizedCountry, normalizedPostcode);
  }

  Future<RegionInterestSubmitResult> submit(RegionInterestDraft draft) async {
    final normalizedCountry = parseDemandRadarCountryCode(draft.country);
    final normalizedPostcode = normalizeDemandRadarPostcode(draft.postcode);
    final name = draft.fullName;
    final email = draft.email.trim().toLowerCase();
    if (normalizedCountry.isEmpty ||
        normalizedPostcode.isEmpty ||
        name.isEmpty ||
        !isRegionInterestEmail(email)) {
      return const RegionInterestSubmitResult(
        ok: false,
        errorCode: 'invalid_region_interest_payload',
      );
    }
    final uri = _uri(kRegionInterestPath);
    final res = await (httpPost ?? _defaultPost)(
      uri,
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'country': normalizedCountry,
        'postcode': normalizedPostcode,
        'name': name,
        'email': email,
        'phone': draft.phone.trim(),
        'locale': draft.locale.trim().isEmpty
            ? 'nl'
            : draft.locale.trim().toLowerCase(),
        'source': kRegionInterestSource,
      }),
    ).timeout(const Duration(seconds: 12));
    final body = _decodeMap(res.bodyBytes);
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        body == null ||
        body['ok'] != true) {
      return RegionInterestSubmitResult(
        ok: false,
        errorCode: (body?['error'] ?? 'submit_failed').toString(),
      );
    }
    return RegionInterestSubmitResult(
      ok: true,
      snapshot: _snapshotFrom(body, normalizedCountry, normalizedPostcode),
      alreadyRegistered: body['existed'] == true,
    );
  }

  Future<http.Response> _defaultPost(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return http.post(uri, headers: headers, body: body);
  }

  Map<String, dynamic>? _decodeMap(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  RegionRadarSnapshot _snapshotFrom(
    Map<String, dynamic> body,
    String country,
    String postcode,
  ) {
    final count = _toInt(body['count']);
    final display = (body['display_count'] ?? '').toString().trim();
    return RegionRadarSnapshot(
      country: (body['country'] ?? country).toString(),
      postcode: (body['postcode'] ?? postcode).toString(),
      count: count,
      displayCount: display,
      status: (body['status'] ?? '').toString(),
      approximateCells: parseRegionRadarApproximateCells(body),
    );
  }

  int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }
}

class RegionInterestException implements Exception {
  const RegionInterestException(this.code);
  final String code;

  @override
  String toString() => 'RegionInterestException($code)';
}
