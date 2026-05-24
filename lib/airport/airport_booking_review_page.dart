import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
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
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _vatNumberController = TextEditingController();

  bool _isSubmitting = false;
  bool _isSubmitted = false;
  bool _isReturningToCustomerPage = false;
  String? _submitError;
  String? _submittedBookingId;

  @override
  void initState() {
    super.initState();
    _vatNumberController.addListener(_onVatNumberChanged);
    unawaited(_prefillFromCustomerProfile());
  }

  void _onVatNumberChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _prefillFromCustomerProfile() async {
    try {
      final profile = await CustomerProfileStore.instance.load();
      if (!mounted || profile == null) return;

      void setIfBlank(TextEditingController controller, String value) {
        if (controller.text.trim().isNotEmpty) return;
        final incoming = value.trim();
        if (incoming.isEmpty) return;
        controller.text = incoming;
      }

      setIfBlank(_nameController, profile.name);
      setIfBlank(_phoneController, profile.phone);
      setIfBlank(_emailController, profile.email);
      setIfBlank(_companyNameController, profile.companyName);
      setIfBlank(_vatNumberController, profile.vatNumber);
    } catch (_) {
      // Best-effort prefill only; never block airport booking flow.
    }
  }

  String get _lang {
    final raw = widget.languageCode.trim().toLowerCase();
    if (raw.startsWith('en')) return 'en';
    if (raw.startsWith('fr')) return 'fr';
    if (raw.startsWith('es')) return 'es';
    return 'nl';
  }

  @override
  void dispose() {
    _vatNumberController.removeListener(_onVatNumberChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _companyNameController.dispose();
    _vatNumberController.dispose();
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

  bool _isFixedAirportFareQuote(Map<String, dynamic> quote) {
    bool asBool(dynamic value) {
      if (value is bool) {
        return value;
      }
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    String asText(dynamic value) {
      return value?.toString().trim().toLowerCase() ?? '';
    }

    if (asBool(quote['fixed_fare_applied'])) {
      return true;
    }
    if (asText(quote['pricing_source']) == 'airport_fixed_fare') {
      return true;
    }
    final breakdownRaw = quote['breakdown'];
    if (breakdownRaw is Map) {
      final breakdown = Map<String, dynamic>.from(breakdownRaw);
      if (asText(breakdown['kind']) == 'airport_fixed_fare') {
        return true;
      }
    }
    return false;
  }

  String? _fixedFareRuleIdFromQuote(Map<String, dynamic> quote) {
    String? nonEmpty(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final topLevel = nonEmpty(quote['fixed_fare_rule_id']);
    if (topLevel != null) {
      return topLevel;
    }
    final breakdownRaw = quote['breakdown'];
    if (breakdownRaw is Map) {
      return nonEmpty(breakdownRaw['fixed_fare_rule_id']);
    }
    return null;
  }

  Map<String, dynamic> _buildBookPayload({
    required String name,
    required String phone,
    required String email,
    String companyName = '',
    String vatNumber = '',
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
        if (companyName.isNotEmpty) ...{
          'company_name': companyName,
          'companyName': companyName,
        },
        if (vatNumber.isNotEmpty) ...{
          'vat_number': vatNumber,
          'vatNumber': vatNumber,
        },
      },
      'customer_name': name,
      'customer_phone': phone,
      'customer_email': email,
      if (companyName.isNotEmpty) ...{
        'customer_company_name': companyName,
        'customerCompanyName': companyName,
        'billing_company_name': companyName,
        'company_name': companyName,
        'companyName': companyName,
      },
      if (vatNumber.isNotEmpty) ...{
        'customer_vat_number': vatNumber,
        'customerVatNumber': vatNumber,
        'billing_vat_number': vatNumber,
        'vat_number': vatNumber,
        'vatNumber': vatNumber,
      },
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
    final companyName = _companyNameController.text.trim();
    final vatNumber = _vatNumberController.text.trim();
    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        !_isValidEmail(email)) {
      setState(() {
        _submitError = _t(
          nl: 'Vul naam, telefoon en e-mail in.',
          en: 'Enter name, phone and email.',
          fr: "Saisissez le nom, le téléphone et l'e-mail.",
          es: 'Introduce nombre, teléfono y e-mail.',
        );
      });
      return;
    }

    final payload = _buildBookPayload(
      name: name,
      phone: phone,
      email: email,
      companyName: companyName,
      vatNumber: vatNumber,
    );
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
            nl: 'Boeking kon niet worden aangemaakt.',
            en: 'Booking could not be created.',
            fr: "La réservation n'a pas pu être créée.",
            es: 'No se pudo crear la reserva.',
          );
        });
        return;
      }
      final bookingId = _readBookingId(body);
      try {
        final localFallback = StoredCustomerBooking.fromBookSuccess(
          response: body,
          requestPayload: payload,
          customerName: name,
          customerPhone: phone,
          customerEmail: email,
        );
        final authoritativeResponse = bookingId.isEmpty
            ? null
            : await _fetchAuthoritativeBooking(bookingId, payload);
        final storedBooking = authoritativeResponse != null
            ? StoredCustomerBooking.fromAuthoritativeResponse(
                bookingId: bookingId,
                response: authoritativeResponse,
                fallback: localFallback,
              )
            : localFallback;
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
          nl: 'Er ging iets mis bij het aanvragen.',
          en: 'Something went wrong while submitting.',
          fr: "Une erreur est survenue lors de l'envoi.",
          es: 'Se produjo un error al enviar la solicitud.',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _soft.withOpacity(0.9),
              fontSize: 12.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.4,
              fontWeight: FontWeight.w700,
              height: 1.25,
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
    final priceEx =
        quote['total_price_ex_vat'] ??
        quote['price_ex_vat'] ??
        quote['total_ex_vat'];
    final priceVat =
        quote['total_price_vat'] ?? quote['price_vat'] ?? quote['vat'];
    final priceExNum = _toNum(priceEx);
    final priceVatNum = _toNum(priceVat);
    final canShowVatBreakdown = priceExNum != null && priceVatNum != null;
    final distance = _toNum(quote['distance_km']);
    final duration = _toNum(quote['duration_min']);
    final hasFixedFare = _isFixedAirportFareQuote(quote);
    final fixedFareRuleId = _fixedFareRuleIdFromQuote(quote);
    final directionRaw = _fallback(payload['airport_direction'], empty: '');
    final directionLabel = directionRaw == 'from_airport'
        ? _t(
            nl: 'Van de luchthaven',
            en: 'From the airport',
            fr: "Depuis l'aéroport",
            es: 'Desde el aeropuerto',
          )
        : _t(
            nl: 'Naar de luchthaven',
            en: 'To the airport',
            fr: "Vers l'aéroport",
            es: 'Al aeropuerto',
          );
    final flightNumber = _fallback(payload['flight_number'], empty: '');
    final nameBoard = _fallback(payload['name_board'], empty: '');
    final note = _fallback(payload['note'], empty: '');
    final selectedCompanyLabel = _firstNonEmptyText([
      payload['public_partner_name'],
      payload['publicPartnerName'],
      payload['selected_company_name'],
      payload['selectedCompanyName'],
      payload['company_name'],
      payload['companyName'],
      payload['company_code'],
      payload['companyCode'],
      payload['partner_id'],
      payload['partnerId'],
      payload['company_id'],
      payload['companyId'],
    ]);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _gold,
        title: Text(
          _t(
            nl: 'Luchthavenrit controle',
            en: 'Airport ride review',
            fr: 'Vérification du transfert aéroport',
            es: 'Revisión del traslado al aeropuerto',
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
                    en: 'Ride overview',
                    fr: 'Aperçu du trajet',
                    es: 'Resumen del viaje',
                  ),
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 13.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _gold.withOpacity(0.48)),
                  ),
                  child: Text(
                    _t(
                      nl: 'Enkele luchthavenrit',
                      en: 'Single airport ride',
                      fr: 'Trajet aéroport simple',
                      es: 'Traslado de aeropuerto sencillo',
                    ),
                    style: TextStyle(
                      color: _gold.withOpacity(0.97),
                      fontSize: 10.9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                if (selectedCompanyLabel.isNotEmpty)
                  _summaryRow(
                    _t(
                      nl: 'Boeking bij',
                      en: 'Booking with',
                      fr: 'Réservation chez',
                      es: 'Reserva con',
                    ),
                    selectedCompanyLabel,
                  ),
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
                    fr: 'Direction',
                    es: 'Dirección',
                  ),
                  directionLabel,
                ),
                _summaryRow(
                  _t(nl: 'Van', en: 'From', fr: 'De', es: 'Desde'),
                  _fallback(payload['from']),
                ),
                _summaryRow(
                  _t(nl: 'Naar', en: 'To', fr: 'Vers', es: 'Hasta'),
                  _fallback(payload['to']),
                ),
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
                  _t(
                    nl: 'Bagage',
                    en: 'Luggage',
                    fr: 'Bagages',
                    es: 'Equipaje',
                  ),
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
                if (canShowVatBreakdown) ...[
                  _summaryRow(
                    _t(
                      nl: 'Prijs excl. btw',
                      en: 'Price excl. VAT',
                      fr: 'Prix hors TVA',
                      es: 'Precio sin IVA',
                    ),
                    _fmtMoney(priceExNum),
                  ),
                  _summaryRow(
                    _t(nl: 'Btw', en: 'VAT', fr: 'TVA', es: 'IVA'),
                    _fmtMoney(priceVatNum),
                  ),
                ],
                _summaryRow(
                  _t(
                    nl: 'Prijs incl. btw',
                    en: 'Price incl. VAT',
                    fr: 'Prix TTC',
                    es: 'Precio con IVA',
                  ),
                  _fmtMoney(priceIncl),
                ),
                if (hasFixedFare) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: _gold.withOpacity(0.48)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            color: _gold.withOpacity(0.96),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _t(
                                nl: 'Vast tarief volgens bedrijfsregel',
                                en: 'Fixed fare by company rule',
                                fr: 'Tarif fixe selon la règle d’entreprise',
                                es: 'Tarifa fija según regla de empresa',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 11.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      _t(
                        nl: 'Deze prijs geldt voor deze enkele luchthavenrit en komt uit de ingestelde luchthavenregels van het bedrijf.',
                        en: 'This price applies to this single airport ride and comes from the company’s configured airport rules.',
                        fr: "Ce prix s'applique à ce trajet aéroport simple et provient des règles aéroport configurées par l'entreprise.",
                        es: 'Este precio se aplica a este traslado de aeropuerto sencillo y proviene de las reglas de aeropuerto configuradas por la empresa.',
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: _soft.withOpacity(0.9),
                        fontSize: 10.8,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (fixedFareRuleId != null)
                    _summaryRow(
                      _t(
                        nl: 'Tariefregel',
                        en: 'Fare rule',
                        fr: 'Règle tarifaire',
                        es: 'Regla de tarifa',
                      ),
                      fixedFareRuleId,
                    ),
                ],
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
                    _t(
                      nl: 'Meet & greet',
                      en: 'Meet & greet',
                      fr: 'Accueil personnalisé',
                      es: 'Recepción personalizada',
                    ),
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
                const SizedBox(height: 12),
                Text(
                  _t(
                    nl: 'Facturatie optioneel',
                    en: 'Billing optional',
                    fr: 'Facturation optionnelle',
                    es: 'Facturación opcional',
                  ),
                  style: TextStyle(
                    color: _soft.withOpacity(0.95),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _inputField(
                  controller: _companyNameController,
                  label: _t(
                    nl: 'Bedrijfsnaam',
                    en: 'Company name',
                    fr: "Nom de l'entreprise",
                    es: 'Nombre de la empresa',
                  ),
                  icon: Icons.business_outlined,
                ),
                const SizedBox(height: 8),
                _inputField(
                  controller: _vatNumberController,
                  label: _t(
                    nl: 'BTW-nummer',
                    en: 'VAT number',
                    fr: 'Numéro de TVA',
                    es: 'Número de IVA',
                  ),
                  icon: Icons.receipt_long_outlined,
                  suffixIcon: _vatNumberController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: _t(
                            nl: 'Wissen',
                            en: 'Clear',
                            fr: 'Effacer',
                            es: 'Borrar',
                          ),
                          onPressed: () {
                            _vatNumberController.clear();
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _gold,
                            size: 18,
                          ),
                        ),
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
                      fr: 'Envoi...',
                      es: 'Enviando...',
                    )
                  : _t(
                      nl: 'Luchthavenrit aanvragen',
                      en: 'Request airport ride',
                      fr: 'Demander le transfert aéroport',
                      es: 'Solicitar traslado al aeropuerto',
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
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _soft, fontSize: 12.2),
        prefixIcon: Icon(icon, color: _gold, size: 18),
        suffixIcon: suffixIcon,
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
