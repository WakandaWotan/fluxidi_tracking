// COMPANY-CUSTOMER-OPS-P0 — public booking URL + QR, no native share sheet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

const Key kCompanyBookingLinkPageKey = Key('company_booking_link_page');
const Key kCompanyBookingLinkUrlKey = Key('company_booking_link_url');

const String kCompanyOpsPublicBookingBaseUrl = String.fromEnvironment(
  'PUBLIC_BOOKING_BASE_URL',
  defaultValue: 'https://fluxidi.com',
);

class CompanyBookingLinkPage extends StatefulWidget {
  const CompanyBookingLinkPage({
    super.key,
    this.language,
    this.profileLoader,
  });

  final AppLanguage? language;
  final Future<Map<String, dynamic>> Function()? profileLoader;

  @override
  State<CompanyBookingLinkPage> createState() => _CompanyBookingLinkPageState();
}

class _CompanyBookingLinkPageState extends State<CompanyBookingLinkPage> {
  bool _loading = true;
  String? _error;
  String _code = '';
  String _url = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await (widget.profileLoader ??
          fetchCompanyOpsBusinessProfile)();
      final code = _publicCode(profile);
      if (!mounted) return;
      setState(() {
        _code = code;
        _url = code.isEmpty ? '' : _bookingUrl(code);
        _loading = false;
        if (code.isEmpty) {
          _error = 'Er is nog geen publieke bedrijfscode in het profiel.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Boekingslink laden mislukt.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyBookingLinkPageKey,
        appBar: AppBar(title: const Text('Deel boekingslink')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Text(_error!),
                  if (_url.isNotEmpty) ...[
                    SelectableText(
                      _url,
                      key: kCompanyBookingLinkUrlKey,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: QrImageView(
                        data: _url,
                        size: 180,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _url)),
                      child: const Text('Link kopiëren'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Dit is dezelfde publieke boekings-URL als in de app. '
                    'Native delen (share-sheet / QR-kaart als bestand) blijft op telefoon. '
                    'Deze pagina bewijst niet de consumentenboeking op fluxidi.com.',
                  ),
                  if (_code.isNotEmpty) Text('Code: $_code'),
                ],
              ),
      ),
    );
  }
}

String _publicCode(Map<String, dynamic> profile) {
  for (final key in const <String>[
    'public_company_code',
    'publicCompanyCode',
    'company_code',
    'companyCode',
    'public_display_code',
    'publicDisplayCode',
  ]) {
    final value = profile[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _bookingUrl(String companyCode) {
  final base = kCompanyOpsPublicBookingBaseUrl.trim().isEmpty
      ? 'https://fluxidi.com'
      : kCompanyOpsPublicBookingBaseUrl.trim();
  try {
    final uri = Uri.parse(base);
    final path = uri.path.trim().isEmpty || uri.path == '/'
        ? '/book'
        : (uri.path.endsWith('/book') ? uri.path : '${uri.path}/book');
    final query = Map<String, String>.from(uri.queryParameters);
    query['company_code'] = companyCode;
    return uri.replace(path: path, queryParameters: query).toString();
  } catch (_) {
    return '$base/book?company_code=${Uri.encodeQueryComponent(companyCode)}';
  }
}
