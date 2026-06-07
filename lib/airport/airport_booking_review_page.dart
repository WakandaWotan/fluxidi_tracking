import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';
import 'package:fluxidi_tracking/payment/payment_method_resolver.dart';
import 'package:fluxidi_tracking/payment/payment_qr_panel.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _themePalette.isDark;
  Color get _bg => _themePalette.background;
  Color get _panel => _themePalette.surfaceAlt;
  Color get _card => _themePalette.surface;
  Color get _gold => _themePalette.gold;
  Color get _soft => _themePalette.textMuted;
  Color get _textPrimary => _themePalette.textPrimary;
  Color get _textMuted => _themePalette.textMuted;
  Color get _border => _themePalette.border;
  Color get _shadow => _themePalette.shadow;
  Color get _accentForeground =>
      _isDarkTheme ? const Color(0xFF050505) : const Color(0xFF1F1706);

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
  String? _submittedMessage;
  String _selectedPaymentMethodId = PaymentMethodIds.inVehicleCard;

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

  AppLanguage get _appLanguage => switch (_lang) {
    'en' => AppLanguage.en,
    'fr' => AppLanguage.fr,
    'es' => AppLanguage.es,
    _ => AppLanguage.nl,
  };

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

  BookingPaymentSelection get _bookingPaymentSelection =>
      BookingPaymentSelection.fromMethodId(_selectedPaymentMethodId);

  String _paymentCountryCodeForResolver() {
    final base = widget.payload;
    for (final key in [
      'airport_country_code',
      'airportCountryCode',
      'country_code',
      'countryCode',
    ]) {
      final normalized = normalizeCountryCode(base[key]?.toString() ?? '');
      if (normalized.isNotEmpty &&
          PaymentCountryCodes.supported.contains(normalized)) {
        return normalized;
      }
    }
    final name = (base['airport_country'] ?? base['airportCountry'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    const nameToCode = {
      'belgië': PaymentCountryCodes.belgium,
      'belgie': PaymentCountryCodes.belgium,
      'belgium': PaymentCountryCodes.belgium,
      'nederland': PaymentCountryCodes.netherlands,
      'netherlands': PaymentCountryCodes.netherlands,
      'frankrijk': PaymentCountryCodes.france,
      'france': PaymentCountryCodes.france,
      'españa': PaymentCountryCodes.spain,
      'espana': PaymentCountryCodes.spain,
      'spain': PaymentCountryCodes.spain,
      'united kingdom': PaymentCountryCodes.greatBritain,
      'uk': PaymentCountryCodes.greatBritain,
      'great britain': PaymentCountryCodes.greatBritain,
    };
    return nameToCode[name] ?? PaymentCountryCodes.belgium;
  }

  List<String> get _visiblePaymentMethodIds {
    const manualInCar = PaymentMethodIds.inVehicleCard;
    final onlineIds = PaymentMethodResolver.resolveIds(
      countryCode: _paymentCountryCodeForResolver(),
    );
    final seen = <String>{manualInCar};
    final out = <String>[manualInCar];
    for (final id in onlineIds) {
      if (id == manualInCar || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }

  String _paymentMethodLabel(String methodId) {
    switch (normalizePaymentMethodId(methodId)) {
      case PaymentMethodIds.inVehicleCard:
        return _t(
          nl: 'Betalen in de auto',
          en: 'Pay in the car',
          fr: 'Payer dans la voiture',
          es: 'Pagar en el coche',
        );
      case PaymentMethodIds.bancontact:
        return 'Bancontact';
      case PaymentMethodIds.bancontactQr:
        return 'Payconiq / Bancontact Pay QR';
      case PaymentMethodIds.ideal:
        return 'iDEAL';
      case PaymentMethodIds.cardPayment:
        return _t(
          nl: 'Kaartbetaling',
          en: 'Card payment',
          fr: 'Paiement par carte',
          es: 'Pago con tarjeta',
        );
      case PaymentMethodIds.applePay:
        return 'Apple Pay';
      case PaymentMethodIds.googlePay:
        return 'Google Pay';
      case PaymentMethodIds.paypal:
        return 'PayPal';
      case PaymentMethodIds.bizum:
        return 'Bizum';
      case PaymentMethodIds.cartesBancaires:
        return 'Carte Bancaire / CB';
      case PaymentMethodIds.payconiqWero:
        return 'Payconiq / Wero';
      case PaymentMethodIds.tikkie:
        return 'Tikkie';
      default:
        return methodId;
    }
  }

  String _paymentMethodDescription(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    if (id == PaymentMethodIds.inVehicleCard ||
        PaymentMethodCatalog.providerFor(id) == PaymentProvider.manual) {
      return _t(
        nl: 'De rit wordt bevestigd en je betaalt later in de wagen.',
        en: 'Ride is confirmed and you pay later in the vehicle.',
        fr: 'Le trajet est confirmé et vous payez plus tard dans le véhicule.',
        es: 'El trayecto se confirma y pagas después en el vehículo.',
      );
    }
    if (PaymentMethodCatalog.isTikkieMethod(id)) {
      return _t(
        nl: 'Betaalverzoek volgt na het bevestigen.',
        en: 'A payment request follows after confirming.',
        fr: 'Une demande de paiement suit après confirmation.',
        es: 'Una solicitud de pago sigue tras confirmar.',
      );
    }
    if (id == PaymentMethodIds.bancontactQr) {
      return _t(
        nl: 'Scan met Bancontact Pay, Payconiq by Bancontact of je bank-app.',
        en: 'Scan with Bancontact Pay, Payconiq by Bancontact, or your Belgian banking app.',
        fr: 'Scannez avec Bancontact Pay, Payconiq by Bancontact ou votre application bancaire belge.',
        es: 'Escanea con Bancontact Pay, Payconiq by Bancontact o tu app bancaria belga.',
      );
    }
    return _t(
      nl: 'Je wordt direct doorgestuurd naar de veilige betaalpagina.',
      en: 'You will be redirected to secure checkout immediately.',
      fr: 'Vous serez redirigé immédiatement vers le paiement sécurisé.',
      es: 'Se te redirigirá de inmediato al pago seguro.',
    );
  }

  IconData _paymentMethodIcon(String methodId) {
    final id = normalizePaymentMethodId(methodId);
    if (id == PaymentMethodIds.inVehicleCard) {
      return Icons.local_taxi_rounded;
    }
    if (PaymentMethodCatalog.isTikkieMethod(id)) {
      return Icons.send_rounded;
    }
    if (id == PaymentMethodIds.bancontactQr) {
      return Icons.qr_code_2_rounded;
    }
    return Icons.language_rounded;
  }

  String? _qrSrcFromBookResponse(Map<String, dynamic> body) {
    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final bookingMap = body['booking'] is Map
        ? Map<String, dynamic>.from(body['booking'] as Map)
        : const <String, dynamic>{};
    final candidates = <Map<String, dynamic>?>[
      asMap(body['qr_code']),
      asMap(body['qrCode']),
      asMap(
        body['payment'] is Map ? (body['payment'] as Map)['qr_code'] : null,
      ),
      asMap(body['payment'] is Map ? (body['payment'] as Map)['qrCode'] : null),
      asMap(bookingMap['qr_code']),
      asMap(bookingMap['qrCode']),
    ];
    for (final qr in candidates) {
      final src = qr?['src']?.toString().trim() ?? '';
      if (src.isNotEmpty) return src;
    }
    return null;
  }

  Future<void> _showPaymentQrDialog({
    required String qrSrc,
    required String checkoutUrl,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _panel,
          content: PaymentQrPanel(
            language: _appLanguage,
            qrSrc: qrSrc,
            checkoutUrl: checkoutUrl.trim().isEmpty ? null : checkoutUrl.trim(),
            onOpenCheckout: checkoutUrl.trim().isEmpty
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    _openCheckoutUrl(checkoutUrl);
                  },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openCheckoutUrl(String checkoutUrl) async {
    final uri = Uri.tryParse(checkoutUrl.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    if (asBool(quote['fixed_fare_applied_main']) ||
        asBool(quote['fixed_fare_applied_return'])) {
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

    final paymentSelection = _bookingPaymentSelection;

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
      ...paymentSelection.toPayloadFields(),
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
      body['public_booking_id'],
      body['publicBookingId'],
      body['id'],
      bookingMap['booking_id'],
      bookingMap['bookingId'],
      bookingMap['public_booking_id'],
      bookingMap['publicBookingId'],
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
      _submittedMessage = null;
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
      final bookingMap = body['booking'] is Map
          ? Map<String, dynamic>.from(body['booking'] as Map)
          : const <String, dynamic>{};
      bool boolish(dynamic value) {
        if (value is bool) return value;
        final raw = (value ?? '').toString().trim().toLowerCase();
        return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
      }

      bool isOnlinePaymentMode(String value) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'mollie' ||
            normalized == 'online' ||
            normalized == 'online_payment' ||
            normalized == 'online-payments' ||
            normalized == 'online_payments';
      }

      bool isSafeCheckoutUrl(String value) {
        final raw = value.trim();
        if (raw.isEmpty) return false;
        final uri = Uri.tryParse(raw);
        if (uri == null) return false;
        final scheme = uri.scheme.toLowerCase();
        return (scheme == 'https' || scheme == 'http') && uri.host.isNotEmpty;
      }

      String safeBookingPreview(String value) {
        final text = value.trim();
        if (text.isEmpty) return '-';
        if (text.length <= 6) return text;
        return '${text.substring(0, 3)}…${text.substring(text.length - 2)}';
      }

      final responseRequiresPayment =
          boolish(body['requiresPayment']) ||
          boolish(body['payment_required']) ||
          boolish(body['requires_payment']) ||
          boolish(bookingMap['requiresPayment']) ||
          boolish(bookingMap['payment_required']) ||
          boolish(bookingMap['requires_payment']);
      final responsePaymentMode = _firstNonEmptyText([
        body['payment_mode'],
        body['paymentMode'],
        bookingMap['payment_mode'],
        bookingMap['paymentMode'],
      ]).toLowerCase();
      final responsePaymentProvider = _firstNonEmptyText([
        body['payment_provider'],
        body['paymentProvider'],
        bookingMap['payment_provider'],
        bookingMap['paymentProvider'],
      ]).toLowerCase();
      final requestPaymentMode = _firstNonEmptyText([
        payload['payment_mode'],
        payload['paymentMode'],
        payload['payment_method'],
        payload['paymentMethod'],
      ]).toLowerCase();
      final requestPaymentProvider = _firstNonEmptyText([
        payload['payment_provider'],
        payload['paymentProvider'],
      ]).toLowerCase();
      final checkoutUrl = _firstNonEmptyText([
        body['checkout_url'],
        body['checkoutUrl'],
        body['payment_url'],
        body['paymentUrl'],
        bookingMap['checkout_url'],
        bookingMap['checkoutUrl'],
        bookingMap['payment_url'],
        bookingMap['paymentUrl'],
      ]);
      final hasSafeCheckoutUrl = isSafeCheckoutUrl(checkoutUrl);
      final explicitOnlineRequested =
          isOnlinePaymentMode(requestPaymentMode) ||
          requestPaymentProvider == 'mollie';
      final backendRequiresOnlineCheckout =
          responseRequiresPayment ||
          isOnlinePaymentMode(responsePaymentMode) ||
          responsePaymentProvider == 'mollie';
      final responseBusinessDetected =
          boolish(body['business_detected']) ||
          boolish(body['businessDetected']) ||
          boolish(bookingMap['business_detected']) ||
          boolish(bookingMap['businessDetected']);
      final responseInvoiceRequested =
          boolish(body['invoice_requested']) ||
          boolish(body['invoiceRequested']) ||
          boolish(bookingMap['invoice_requested']) ||
          boolish(bookingMap['invoiceRequested']);
      final requestBusinessIntent =
          boolish(payload['business_detected']) ||
          boolish(payload['businessDetected']) ||
          boolish(payload['invoice_requested']) ||
          boolish(payload['invoiceRequested']) ||
          companyName.trim().isNotEmpty ||
          vatNumber.trim().isNotEmpty;
      final businessInvoiceIntent =
          responseBusinessDetected ||
          responseInvoiceRequested ||
          requestBusinessIntent;
      if (explicitOnlineRequested &&
          backendRequiresOnlineCheckout &&
          !hasSafeCheckoutUrl) {
        debugPrint(
          '[AIRPORT_BOOKING][CHECKOUT_MISSING_BLOCKED] booking=${safeBookingPreview(bookingId)} paymentMode=$responsePaymentMode provider=$responsePaymentProvider requiresPayment=$responseRequiresPayment',
        );
        setState(() {
          _submitError = _t(
            nl: 'Online betaling kon niet worden gestart. Probeer opnieuw.',
            en: 'Online payment could not be started. Please try again.',
            fr: "Le paiement en ligne n'a pas pu être démarré. Réessayez.",
            es: 'No se pudo iniciar el pago online. Inténtalo de nuevo.',
          );
        });
        return;
      }
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
      final manualBusinessFlow =
          !explicitOnlineRequested &&
          !hasSafeCheckoutUrl &&
          businessInvoiceIntent;
      final manualPrivateFlow =
          !explicitOnlineRequested &&
          !hasSafeCheckoutUrl &&
          !businessInvoiceIntent;
      final successMessage = manualBusinessFlow
          ? _t(
              nl: 'Boeking aangemaakt. Betaling in de wagen. Factuur volgt na betaling.',
              en: 'Booking created. Payment in the vehicle. Invoice follows after payment.',
              fr: 'Reservation creee. Paiement dans le vehicule. Facture envoyee apres paiement.',
              es: 'Reserva creada. Pago en el vehiculo. La factura se enviara despues del pago.',
            )
          : manualPrivateFlow
          ? _t(
              nl: 'Boeking aangemaakt. Betaling in de wagen.',
              en: 'Booking created. Payment in the vehicle.',
              fr: 'Reservation creee. Paiement dans le vehicule.',
              es: 'Reserva creada. Pago en el vehiculo.',
            )
          : _t(
              nl: 'Luchthavenrit aangemaakt. Rond de online betaling af.',
              en: 'Airport ride created. Complete the online payment.',
              fr: 'Transfert aéroport créé. Finalisez le paiement en ligne.',
              es: 'Traslado al aeropuerto creado. Completa el pago en línea.',
            );
      setState(() {
        _isSubmitted = true;
        _submittedBookingId = bookingId.isEmpty ? null : bookingId;
        _submittedMessage = successMessage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _panel,
          content: Text(successMessage, style: TextStyle(color: _textPrimary)),
        ),
      );
      final qrSrc = _qrSrcFromBookResponse(body);
      final prefersQrCheckout =
          normalizePaymentMethodId(_selectedPaymentMethodId) ==
          PaymentMethodIds.bancontactQr;
      if (explicitOnlineRequested &&
          prefersQrCheckout &&
          (qrSrc ?? '').isNotEmpty) {
        await _showPaymentQrDialog(qrSrc: qrSrc!, checkoutUrl: checkoutUrl);
      } else if (explicitOnlineRequested && hasSafeCheckoutUrl) {
        await _openCheckoutUrl(checkoutUrl);
      }
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

  Widget _paymentMethodChoiceOptionTile(String methodId) {
    final selected = _selectedPaymentMethodId == methodId;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isSubmitting || _isSubmitted
          ? null
          : () {
              setState(() {
                _selectedPaymentMethodId = methodId;
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? _gold.withOpacity(_isDarkTheme ? 0.16 : 0.12)
              : _panel.withOpacity(_isDarkTheme ? 0.72 : 1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _gold
                : _border.withOpacity(_isDarkTheme ? 0.8 : 0.95),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _paymentMethodIcon(methodId),
              color: selected ? _gold : _textMuted,
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _paymentMethodLabel(methodId),
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 12.8,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _paymentMethodDescription(methodId),
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 11.1,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _gold : _textMuted.withOpacity(0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
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
            style: TextStyle(
              color: _textPrimary,
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
    final returnMapRaw = quote['return'];
    final returnMap = returnMapRaw is Map
        ? Map<String, dynamic>.from(returnMapRaw)
        : const <String, dynamic>{};
    final isRoundtrip =
        payload['return_enabled'] == true ||
        payload['returnEnabled'] == true ||
        quote['return_enabled'] == true ||
        quote['returnEnabled'] == true ||
        quote['price_incl_vat_return'] != null ||
        returnMap.isNotEmpty;
    final priceIncl =
        quote['total_price_incl_vat'] ??
        quote['price_incl_vat_total'] ??
        quote['price_incl_vat'];
    final priceInclMain =
        quote['price_incl_vat_main'] ?? quote['price_incl_vat'];
    final priceInclReturn =
        quote['price_incl_vat_return'] ?? returnMap['price_incl_vat'];
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
    bool quoteBool(dynamic value) {
      if (value is bool) return value;
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    final fixedFareRuleIdMain = _fallback(
      quote['fixed_fare_rule_id_main'],
      empty: '',
    );
    final fixedFareRuleIdReturn = _fallback(
      quote['fixed_fare_rule_id_return'],
      empty: '',
    );
    final fixedFareMain =
        quoteBool(quote['fixed_fare_applied_main']) ||
        quoteBool(quote['fixed_fare_applied']);
    final fixedFareReturn = quoteBool(quote['fixed_fare_applied_return']);
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
    final returnFrom = _fallback(payload['return_from'], empty: '');
    final returnTo = _fallback(payload['return_to'], empty: '');
    final returnDate = _fallback(payload['return_date'], empty: '');
    final returnTime = _fallback(payload['return_time'], empty: '');
    final returnDistance = _toNum(
      quote['return_distance_km'] ?? returnMap['distance_km'],
    );
    final returnDuration = _toNum(
      quote['return_duration_min'] ?? returnMap['duration_min'],
    );
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

    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, _) {
        final palette = paletteForCustomerTheme(themeVariant);
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.textPrimary,
            elevation: 0,
            title: Text(
              _t(
                nl: 'Luchthavenrit controle',
                en: 'Airport ride review',
                fr: 'Vérification du transfert aéroport',
                es: 'Revisión del traslado al aeropuerto',
              ),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isDarkTheme
                    ? <Color>[
                        palette.background,
                        _panel.withOpacity(0.55),
                        palette.background,
                      ]
                    : <Color>[
                        palette.background,
                        _panel.withOpacity(0.45),
                        palette.background,
                      ],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _border.withOpacity(_isDarkTheme ? 0.82 : 0.95),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _shadow.withOpacity(_isDarkTheme ? 0.35 : 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
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
                        style: TextStyle(
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
                          color: _gold.withOpacity(_isDarkTheme ? 0.14 : 0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _gold.withOpacity(
                              _isDarkTheme ? 0.48 : 0.38,
                            ),
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: isRoundtrip
                                ? 'Heen-en-terug luchthavenrit'
                                : 'Enkele luchthavenrit',
                            en: isRoundtrip
                                ? 'Roundtrip airport ride'
                                : 'Single airport ride',
                            fr: isRoundtrip
                                ? 'Trajet aéroport aller-retour'
                                : 'Trajet aéroport simple',
                            es: isRoundtrip
                                ? 'Traslado de aeropuerto ida y vuelta'
                                : 'Traslado de aeropuerto sencillo',
                          ),
                          style: TextStyle(
                            color: _isDarkTheme
                                ? _gold.withOpacity(0.97)
                                : _themePalette.bronze,
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
                        _t(
                          nl: isRoundtrip ? 'Heenrit van' : 'Van',
                          en: isRoundtrip ? 'Outbound from' : 'From',
                          fr: isRoundtrip ? "Aller depuis" : 'De',
                          es: isRoundtrip ? 'Ida desde' : 'Desde',
                        ),
                        _fallback(payload['from']),
                      ),
                      _summaryRow(
                        _t(
                          nl: isRoundtrip ? 'Heenrit naar' : 'Naar',
                          en: isRoundtrip ? 'Outbound to' : 'To',
                          fr: isRoundtrip ? "Aller vers" : 'Vers',
                          es: isRoundtrip ? 'Ida hacia' : 'Hasta',
                        ),
                        _fallback(payload['to']),
                      ),
                      _summaryRow(
                        _t(
                          nl: isRoundtrip
                              ? 'Heenrit datum en tijd'
                              : 'Datum en tijd',
                          en: isRoundtrip
                              ? 'Outbound date and time'
                              : 'Date and time',
                          fr: isRoundtrip
                              ? "Date et heure de l'aller"
                              : 'Date et heure',
                          es: isRoundtrip
                              ? 'Fecha y hora de ida'
                              : 'Fecha y hora',
                        ),
                        '${_fallback(payload['date'])} ${_fallback(payload['time'])}',
                      ),
                      if (isRoundtrip) ...[
                        _summaryRow(
                          _t(
                            nl: 'Terugrit van',
                            en: 'Return from',
                            fr: 'Retour depuis',
                            es: 'Regreso desde',
                          ),
                          returnFrom,
                        ),
                        _summaryRow(
                          _t(
                            nl: 'Terugrit naar',
                            en: 'Return to',
                            fr: 'Retour vers',
                            es: 'Regreso hacia',
                          ),
                          returnTo,
                        ),
                        _summaryRow(
                          _t(
                            nl: 'Terugrit datum en tijd',
                            en: 'Return date and time',
                            fr: 'Date et heure du retour',
                            es: 'Fecha y hora de regreso',
                          ),
                          '${returnDate.isEmpty ? '—' : returnDate} ${returnTime.isEmpty ? '' : returnTime}'
                              .trim(),
                        ),
                      ],
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
                        distance != null
                            ? '${distance.toStringAsFixed(1)} km'
                            : '—',
                      ),
                      _summaryRow(
                        _t(
                          nl: 'Duur',
                          en: 'Duration',
                          fr: 'Durée',
                          es: 'Duración',
                        ),
                        duration != null
                            ? '${duration.toStringAsFixed(0)} min'
                            : '—',
                      ),
                      if (isRoundtrip) ...[
                        _summaryRow(
                          _t(
                            nl: 'Terugrit afstand',
                            en: 'Return distance',
                            fr: 'Distance retour',
                            es: 'Distancia de regreso',
                          ),
                          returnDistance != null
                              ? '${returnDistance.toStringAsFixed(1)} km'
                              : '—',
                        ),
                        _summaryRow(
                          _t(
                            nl: 'Terugrit duur',
                            en: 'Return duration',
                            fr: 'Durée retour',
                            es: 'Duración de regreso',
                          ),
                          returnDuration != null
                              ? '${returnDuration.toStringAsFixed(0)} min'
                              : '—',
                        ),
                      ],
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
                          nl: isRoundtrip
                              ? 'Heenrit prijs incl. btw'
                              : 'Prijs incl. btw',
                          en: isRoundtrip
                              ? 'Outbound price incl. VAT'
                              : 'Price incl. VAT',
                          fr: isRoundtrip ? "Prix aller TVAC" : 'Prix TTC',
                          es: isRoundtrip
                              ? 'Precio ida con IVA'
                              : 'Precio con IVA',
                        ),
                        _fmtMoney(priceInclMain),
                      ),
                      if (isRoundtrip)
                        _summaryRow(
                          _t(
                            nl: 'Terugrit prijs incl. btw',
                            en: 'Return price incl. VAT',
                            fr: 'Prix retour TVAC',
                            es: 'Precio regreso con IVA',
                          ),
                          _fmtMoney(priceInclReturn),
                        ),
                      if (isRoundtrip)
                        _summaryRow(
                          _t(
                            nl: 'Totaal heen-en-terug incl. btw',
                            en: 'Roundtrip total incl. VAT',
                            fr: 'Total aller-retour TVAC',
                            es: 'Total ida y vuelta con IVA',
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
                              color: _gold.withOpacity(
                                _isDarkTheme ? 0.14 : 0.11,
                              ),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: _gold.withOpacity(
                                  _isDarkTheme ? 0.48 : 0.38,
                                ),
                              ),
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
                                      nl: isRoundtrip
                                          ? 'Vast tarief per rit volgens bedrijfsregel'
                                          : 'Vast tarief volgens bedrijfsregel',
                                      en: isRoundtrip
                                          ? 'Fixed fare per leg by company rule'
                                          : 'Fixed fare by company rule',
                                      fr: isRoundtrip
                                          ? "Tarif fixe par trajet selon la règle d’entreprise"
                                          : 'Tarif fixe selon la règle d’entreprise',
                                      es: isRoundtrip
                                          ? 'Tarifa fija por trayecto según regla de empresa'
                                          : 'Tarifa fija según regla de empresa',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _isDarkTheme
                                          ? _gold
                                          : _themePalette.bronze,
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
                              nl: isRoundtrip
                                  ? (fixedFareMain && fixedFareReturn
                                        ? 'Heen- en terugrit volgen beide de ingestelde luchthavenregels van het bedrijf.'
                                        : 'Vaste tariefregels zijn toegepast waar beschikbaar; overige delen volgen routeberekening.')
                                  : 'Deze prijs geldt voor deze enkele luchthavenrit en komt uit de ingestelde luchthavenregels van het bedrijf.',
                              en: isRoundtrip
                                  ? (fixedFareMain && fixedFareReturn
                                        ? 'Both outbound and return legs follow the company’s configured airport rules.'
                                        : 'Fixed-fare rules are applied where available; remaining parts use route pricing.')
                                  : 'This price applies to this single airport ride and comes from the company’s configured airport rules.',
                              fr: isRoundtrip
                                  ? (fixedFareMain && fixedFareReturn
                                        ? "L’aller et le retour suivent les règles aéroport configurées par l’entreprise."
                                        : "Les règles de tarif fixe sont appliquées quand possible; le reste suit le calcul d’itinéraire.")
                                  : "Ce prix s'applique à ce trajet aéroport simple et provient des règles aéroport configurées par l'entreprise.",
                              es: isRoundtrip
                                  ? (fixedFareMain && fixedFareReturn
                                        ? 'Tanto ida como regreso siguen las reglas de aeropuerto configuradas por la empresa.'
                                        : 'Las reglas de tarifa fija se aplican donde estén disponibles; el resto usa cálculo por ruta.')
                                  : 'Este precio se aplica a este traslado de aeropuerto sencillo y proviene de las reglas de aeropuerto configuradas por la empresa.',
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              color: _textMuted,
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
                        if (isRoundtrip &&
                            fixedFareRuleIdMain.isNotEmpty &&
                            fixedFareRuleIdReturn.isNotEmpty &&
                            fixedFareRuleIdMain != fixedFareRuleIdReturn) ...[
                          _summaryRow(
                            _t(
                              nl: 'Tariefregel heenrit',
                              en: 'Fare rule outbound',
                              fr: "Règle tarifaire aller",
                              es: 'Regla tarifa ida',
                            ),
                            fixedFareRuleIdMain,
                          ),
                          _summaryRow(
                            _t(
                              nl: 'Tariefregel terugrit',
                              en: 'Fare rule return',
                              fr: 'Règle tarifaire retour',
                              es: 'Regla tarifa regreso',
                            ),
                            fixedFareRuleIdReturn,
                          ),
                        ],
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
                          _t(
                            nl: 'Opmerking',
                            en: 'Note',
                            fr: 'Note',
                            es: 'Nota',
                          ),
                          note,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _border.withOpacity(_isDarkTheme ? 0.82 : 0.95),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _shadow.withOpacity(_isDarkTheme ? 0.35 : 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          nl: 'Betaalmethode',
                          en: 'Payment method',
                          fr: 'Mode de paiement',
                          es: 'Método de pago',
                        ),
                        style: TextStyle(
                          color: _gold,
                          fontSize: 13.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _t(
                          nl: 'Kies hoe je wilt betalen voor deze rit.',
                          en: 'Choose how you want to pay for this ride.',
                          fr: 'Choisissez comment payer ce trajet.',
                          es: 'Elige cómo quieres pagar este viaje.',
                        ),
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: 11.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (
                        var i = 0;
                        i < _visiblePaymentMethodIds.length;
                        i++
                      ) ...[
                        if (i > 0) const SizedBox(height: 7),
                        _paymentMethodChoiceOptionTile(
                          _visiblePaymentMethodIds[i],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _border.withOpacity(_isDarkTheme ? 0.82 : 0.95),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _shadow.withOpacity(_isDarkTheme ? 0.35 : 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
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
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 13.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _inputField(
                        controller: _nameController,
                        label: _t(
                          nl: 'Naam',
                          en: 'Name',
                          fr: 'Nom',
                          es: 'Nombre',
                        ),
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
                          color: _textMuted,
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
                                icon: Icon(
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
                          style: TextStyle(
                            color: _themePalette.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_isSubmitted) ...[
                        const SizedBox(height: 8),
                        Text(
                          _submittedMessage ??
                              (_submittedBookingId == null
                                  ? _t(
                                      nl: 'Luchthavenrit aangevraagd.',
                                      en: 'Airport ride requested.',
                                      fr: 'Trajet aéroport demandé.',
                                      es: 'Traslado al aeropuerto solicitado.',
                                    )
                                  : '${_t(nl: "Aangevraagd", en: "Requested", fr: "Demandé", es: "Solicitado")}: $_submittedBookingId'),
                          style: TextStyle(
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
                          style: TextStyle(color: _textMuted, fontSize: 11.8),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _isSubmitting || _isSubmitted
                      ? null
                      : _submitBooking,
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _accentForeground,
                    disabledBackgroundColor: _gold.withOpacity(0.45),
                    disabledForegroundColor: _accentForeground.withOpacity(
                      0.75,
                    ),
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
                      foregroundColor: _textPrimary,
                      side: BorderSide(
                        color: _border.withOpacity(_isDarkTheme ? 0.9 : 1),
                      ),
                      backgroundColor: _card,
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
          ),
        );
      },
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
      cursorColor: _gold,
      style: TextStyle(color: _textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textMuted, fontSize: 12.2),
        prefixIcon: Icon(icon, color: _gold, size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.8 : 1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold, width: 1.2),
        ),
      ),
    );
  }
}
