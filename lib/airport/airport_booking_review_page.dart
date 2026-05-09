import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:http/http.dart' as http;

class AirportBookingReviewPage extends StatefulWidget {
  const AirportBookingReviewPage({
    super.key,
    required this.bookingBaseUrl,
    required this.quote,
    required this.payload,
    required this.languageCode,
    this.currencySymbol = '€',
  });

  final String bookingBaseUrl;
  final Map<String, dynamic> quote;
  final Map<String, dynamic> payload;
  final String languageCode;
  final String currencySymbol;

  @override
  State<AirportBookingReviewPage> createState() =>
      _AirportBookingReviewPageState();
}

class _AirportBookingReviewPageState extends State<AirportBookingReviewPage> {
  static const Color _bg = Color(0xFF07080C);
  static const Color _panel = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _soft = Color(0xFFB4B4B4);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  bool _isSubmitting = false;
  bool _isSubmitted = false;
  bool _isReturningToCustomerPage = false;
  String? _submitError;
  String? _submittedBookingId;

  String get _lang {
    final raw = widget.languageCode.trim().toLowerCase();
    if (raw.startsWith('en')) return 'en';
    if (raw.startsWith('fr')) return 'fr';
    if (raw.startsWith('es')) return 'es';
    return 'nl';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case 'en':
        return en;
      case 'fr':
        return fr;
      case 'es':
        return es;
      default:
        return nl;
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  double? _toNum(dynamic value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : null;
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  String _fmtMoney(dynamic value) {
    final amount = _toNum(value);
    if (amount == null) return '—';
    return '${widget.currencySymbol} ${amount.toStringAsFixed(2)}';
  }

  Map<String, dynamic> _buildBookPayload({
    required String name,
    required String phone,
    required String email,
  }) {
    final base = Map<String, dynamic>.from(widget.payload);
    final tenantId = (base['tenant_id'] ?? base['tenantId'] ?? '').toString();
    final companyId = (base['company_id'] ?? base['companyId'] ?? '')
        .toString();
    final airportTransfer = <String, dynamic>{
      'airport_direction': base['airport_direction'],
      'airport_id': base['airport_id'],
      'airport_iata': base['airport_iata'],
      'airport_name': base['airport_name'],
      'airport_country': base['airport_country'],
      'flight_number': base['flight_number'],
      'meet_and_greet': base['meet_and_greet'] == true,
      'name_board': base['name_board'],
    };

    return <String, dynamic>{
      ...base,
      if (tenantId.isNotEmpty) ...{'tenant_id': tenantId, 'tenantId': tenantId},
      if (companyId.isNotEmpty) ...{
        'company_id': companyId,
        'companyId': companyId,
      },
      'booking_source': 'airport_module',
      'booking_type': 'airport_transfer',
      'entry_channel': 'flutter_airport',
      'customer': <String, dynamic>{
        'name': name,
        'phone': phone,
        'email': email,
      },
      'customer_name': name,
      'customer_phone': phone,
      'customer_email': email,
      'quote': widget.quote,
      'airport_transfer': airportTransfer,
    };
  }

  String _firstNonEmptyText(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _readBookingId(Map<String, dynamic> body) {
    final booking = body['booking'];
    final bookingMap = booking is Map
        ? Map<String, dynamic>.from(booking)
        : const <String, dynamic>{};
    return _firstNonEmptyText([
      body['booking_id'],
      body['bookingId'],
      body['id'],
      bookingMap['booking_id'],
      bookingMap['bookingId'],
      bookingMap['id'],
    ]);
  }

  Future<Map<String, dynamic>?> _fetchAuthoritativeBooking(
    String bookingId,
    Map<String, dynamic> requestPayload,
  ) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;
    final tenantId = _firstNonEmptyText([
      requestPayload['tenant_id'],
      requestPayload['tenantId'],
    ]);
    final companyId = _firstNonEmptyText([
      requestPayload['company_id'],
      requestPayload['companyId'],
    ]);
    final customerRaw = requestPayload['customer'];
    final customerMap = customerRaw is Map
        ? Map<String, dynamic>.from(customerRaw)
        : const <String, dynamic>{};
    final customerEmail = _firstNonEmptyText([
      requestPayload['customer_email'],
      requestPayload['email'],
      customerMap['email'],
    ]);
    final customerPhone = _firstNonEmptyText([
      requestPayload['customer_phone'],
      requestPayload['phone'],
      customerMap['phone'],
    ]);
    final uri =
        Uri.parse(
          '${widget.bookingBaseUrl}/bookings/${Uri.encodeComponent(id)}',
        ).replace(
          queryParameters: <String, String>{
            if (tenantId.isNotEmpty) ...{
              'tenant_id': tenantId,
              'tenantId': tenantId,
            },
            if (companyId.isNotEmpty) ...{
              'company_id': companyId,
              'companyId': companyId,
            },
            if (customerEmail.isNotEmpty) 'customer_email': customerEmail,
            if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
          },
        );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        debugPrint(
          '[AIRPORT_BOOKING][AUTHORITATIVE_FETCH][STATUS] code=${response.statusCode}',
        );
        return null;
      }
      final dynamic decoded = response.body.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (err) {
      debugPrint('[AIRPORT_BOOKING][AUTHORITATIVE_FETCH][ERROR] $err');
      return null;
    }
  }

  Future<void> _submitBooking() async {
    if (_isSubmitting || _isSubmitted) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        !_isValidEmail(email)) {
      setState(() {
        _submitError = _t(
          nl: 'Vul naam, telefoon en geldig e-mailadres in.',
          en: 'Please enter name, phone and a valid email address.',
          fr: 'Veuillez saisir le nom, le téléphone et une adresse e-mail valide.',
          es: 'Introduce nombre, teléfono y un correo electrónico válido.',
        );
      });
      return;
    }

    final payload = _buildBookPayload(name: name, phone: phone, email: email);
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('${widget.bookingBaseUrl}/book'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      final dynamic decoded = response.body.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(response.body);
      final body = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final ok =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          (body['ok'] == null || body['ok'] == true);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _submitError = _t(
            nl: 'Luchthavenrit kon niet worden aangevraagd. Probeer opnieuw.',
            en: 'Airport ride request failed. Please try again.',
            fr: 'La demande de trajet aéroport a échoué. Réessayez.',
            es: 'No se pudo solicitar el traslado al aeropuerto. Inténtalo de nuevo.',
          );
        });
        return;
      }
      final bookingId = _readBookingId(body);
      try {
        final authoritativeResponse = bookingId.isEmpty
            ? null
            : await _fetchAuthoritativeBooking(bookingId, payload);
        final storedBooking = authoritativeResponse != null
            ? StoredCustomerBooking.fromAuthoritativeResponse(
                bookingId: bookingId,
                response: authoritativeResponse,
              )
            : StoredCustomerBooking.fromBookSuccess(
                response: body,
                requestPayload: payload,
                customerName: name,
                customerPhone: phone,
                customerEmail: email,
              );
        await CustomerBookingsStore.instance.upsert(storedBooking);
      } catch (err) {
        debugPrint('[AIRPORT_BOOKING][LOCAL_PERSIST][ERROR] $err');
      }
      if (!mounted) return;
      setState(() {
        _isSubmitted = true;
        _submittedBookingId = bookingId.isEmpty ? null : bookingId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Luchthavenrit aangevraagd.',
              en: 'Airport ride requested.',
              fr: 'Trajet aéroport demandé.',
              es: 'Traslado al aeropuerto solicitado.',
            ),
          ),
        ),
      );
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        _returnToCustomerPage();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = _t(
          nl: 'Luchthavenrit kon niet worden aangevraagd. Controleer de verbinding.',
          en: 'Airport ride request failed. Check your connection.',
          fr: 'La demande de trajet aéroport a échoué. Vérifiez la connexion.',
          es: 'No se pudo solicitar el traslado al aeropuerto. Verifica la conexión.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _soft.withOpacity(0.9),
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fallback(dynamic value, {String empty = '—'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? empty : text;
  }

  void _returnToCustomerPage() {
    if (_isReturningToCustomerPage) return;
    _isReturningToCustomerPage = true;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final quote = widget.quote;
    final priceIncl = quote['total_price_incl_vat'] ?? quote['price_incl_vat'];
    final distance = _toNum(quote['distance_km']);
    final duration = _toNum(quote['duration_min']);
    final directionRaw = _fallback(payload['airport_direction'], empty: '');
    final directionLabel = directionRaw == 'from_airport'
        ? _t(
            nl: 'Van de luchthaven',
            en: 'From airport',
            fr: 'Depuis l’aéroport',
            es: 'Desde el aeropuerto',
          )
        : _t(
            nl: 'Naar de luchthaven',
            en: 'To airport',
            fr: 'Vers l’aéroport',
            es: 'Hacia el aeropuerto',
          );
    final flightNumber = _fallback(payload['flight_number'], empty: '');
    final nameBoard = _fallback(payload['name_board'], empty: '');
    final note = _fallback(payload['note'], empty: '');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _gold,
        title: Text(
          _t(
            nl: 'Luchthavenrit controleren',
            en: 'Review airport ride',
            fr: 'Vérifier le trajet aéroport',
            es: 'Revisar traslado aeropuerto',
          ),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withOpacity(0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Ritoverzicht',
                    en: 'Ride summary',
                    fr: 'Résumé de course',
                    es: 'Resumen del trayecto',
                  ),
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 13.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                _summaryRow(
                  _t(
                    nl: 'Luchthaven',
                    en: 'Airport',
                    fr: 'Aéroport',
                    es: 'Aeropuerto',
                  ),
                  '${_fallback(payload['airport_name'])} (${_fallback(payload['airport_iata'])})',
                ),
                _summaryRow(
                  _t(
                    nl: 'Richting',
                    en: 'Direction',
                    fr: 'Sens',
                    es: 'Dirección',
                  ),
                  directionLabel,
                ),
                _summaryRow('From', _fallback(payload['from'])),
                _summaryRow('To', _fallback(payload['to'])),
                _summaryRow(
                  _t(
                    nl: 'Datum en tijd',
                    en: 'Date and time',
                    fr: 'Date et heure',
                    es: 'Fecha y hora',
                  ),
                  '${_fallback(payload['date'])} ${_fallback(payload['time'])}',
                ),
                _summaryRow(
                  _t(
                    nl: 'Passagiers',
                    en: 'Passengers',
                    fr: 'Passagers',
                    es: 'Pasajeros',
                  ),
                  _fallback(payload['pax']),
                ),
                _summaryRow(
                  _t(nl: 'Bagage', en: 'Bags', fr: 'Bagages', es: 'Equipaje'),
                  _fallback(payload['bags']),
                ),
                _summaryRow(
                  _t(
                    nl: 'Afstand',
                    en: 'Distance',
                    fr: 'Distance',
                    es: 'Distancia',
                  ),
                  distance != null ? '${distance.toStringAsFixed(1)} km' : '—',
                ),
                _summaryRow(
                  _t(nl: 'Duur', en: 'Duration', fr: 'Durée', es: 'Duración'),
                  duration != null ? '${duration.toStringAsFixed(0)} min' : '—',
                ),
                _summaryRow(
                  _t(
                    nl: 'Prijs incl. btw',
                    en: 'Price incl. VAT',
                    fr: 'Prix TTC',
                    es: 'Precio con IVA',
                  ),
                  _fmtMoney(priceIncl),
                ),
                if (flightNumber.isNotEmpty)
                  _summaryRow(
                    _t(
                      nl: 'Vluchtnummer',
                      en: 'Flight number',
                      fr: 'Numéro de vol',
                      es: 'Número de vuelo',
                    ),
                    flightNumber,
                  ),
                if (payload['meet_and_greet'] == true)
                  _summaryRow(
                    'Meet & greet',
                    _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Sí'),
                  ),
                if (nameBoard.isNotEmpty)
                  _summaryRow(
                    _t(
                      nl: 'Naam bordje',
                      en: 'Name board',
                      fr: 'Nom sur panneau',
                      es: 'Nombre en cartel',
                    ),
                    nameBoard,
                  ),
                if (note.isNotEmpty)
                  _summaryRow(
                    _t(nl: 'Opmerking', en: 'Note', fr: 'Note', es: 'Nota'),
                    note,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withOpacity(0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Uw contactgegevens',
                    en: 'Your contact details',
                    fr: 'Vos coordonnées',
                    es: 'Tus datos de contacto',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                _inputField(
                  controller: _nameController,
                  label: _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 8),
                _inputField(
                  controller: _phoneController,
                  label: _t(
                    nl: 'Telefoon',
                    en: 'Phone',
                    fr: 'Téléphone',
                    es: 'Teléfono',
                  ),
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                _inputField(
                  controller: _emailController,
                  label: _t(
                    nl: 'E-mail',
                    en: 'Email',
                    fr: 'E-mail',
                    es: 'Correo electrónico',
                  ),
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _submitError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_isSubmitted) ...[
                  const SizedBox(height: 8),
                  Text(
                    _submittedBookingId == null
                        ? _t(
                            nl: 'Luchthavenrit aangevraagd.',
                            en: 'Airport ride requested.',
                            fr: 'Trajet aéroport demandé.',
                            es: 'Traslado al aeropuerto solicitado.',
                          )
                        : '${_t(nl: "Aangevraagd", en: "Requested", fr: "Demandé", es: "Solicitado")}: $_submittedBookingId',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 12.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t(
                      nl: 'Uw aanvraag werd ontvangen.',
                      en: 'Your request was received.',
                      fr: 'Votre demande a été reçue.',
                      es: 'Tu solicitud fue recibida.',
                    ),
                    style: TextStyle(
                      color: _soft.withOpacity(0.95),
                      fontSize: 11.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isSubmitting || _isSubmitted ? null : _submitBooking,
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(
              _isSubmitting
                  ? _t(
                      nl: 'Aanvragen...',
                      en: 'Requesting...',
                      fr: 'Demande...',
                      es: 'Solicitando...',
                    )
                  : _t(
                      nl: 'Luchthavenrit aanvragen',
                      en: 'Request airport ride',
                      fr: 'Demander un trajet aéroport',
                      es: 'Solicitar traslado aeropuerto',
                    ),
            ),
          ),
          if (_isSubmitted) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _returnToCustomerPage,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withOpacity(0.65)),
              ),
              child: Text(
                _t(
                  nl: 'Terug naar klantenpagina',
                  en: 'Back to customer page',
                  fr: 'Retour à la page client',
                  es: 'Volver a la página del cliente',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _soft, fontSize: 12.2),
        prefixIcon: Icon(icon, color: _gold, size: 18),
        filled: true,
        fillColor: const Color(0xFF181818),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withOpacity(0.32)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.2),
        ),
      ),
    );
  }
}
