// COMPANY-CUSTOMER-OPS-P0

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_customer_ground.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_list.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_money.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_breakdown.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_suggestion.dart';
import 'package:fluxidi_tracking/company/company_rate_card_hint.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_ride_options_form.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_roundtrip_fields.dart';
import 'package:fluxidi_tracking/company/company_trip_route_fields.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

const Key kCompanyCustomerQuotePageKey = Key('company_customer_quote_page');
const Key kCompanyCustomerQuoteSaveKey = Key('company_customer_quote_save');
const Key kCompanyCustomerQuoteRetryKey = Key('company_customer_quote_retry');
const double kCompanyQuoteStickyActionsClearance = 160;
const Key kCompanyCustomerQuoteReviewKey = Key('company_customer_quote_review');
const Key kCompanyCustomerQuoteSendKey = Key('company_customer_quote_send');
const Key kCompanyCustomerQuotePriceKey = Key('company_customer_quote_price');
const Key kCompanyCustomerQuoteCurrencyKey =
    Key('company_customer_quote_currency');
const Key kCompanyCustomerQuoteIncludedKey =
    Key('company_customer_quote_included');
const Key kCompanyCustomerQuoteEmailKey = Key('company_customer_quote_email');
const Key kCompanyCustomerQuotePhoneKey = Key('company_customer_quote_phone');
const Key kCompanyCustomerQuoteGuestLinkKey =
    Key('company_customer_quote_guest_link');
const Key kCompanyCustomerQuoteViewBookingKey =
    Key('company_customer_quote_view_booking');
const Key kCompanyCustomerQuotePickupFieldKey =
    Key('company_customer_quote_pickup');
const Key kCompanyCustomerQuoteDropoffFieldKey =
    Key('company_customer_quote_dropoff');
const Key kCompanyCustomerQuoteVatFieldKey =
    Key('company_customer_quote_vat_field');
const Key kCompanyCustomerQuoteVatBreakdownKey =
    Key('company_customer_quote_vat_breakdown');
const Key kCompanyCustomerQuoteReviewPickupKey =
    Key('company_customer_quote_review_pickup');
const Key kCompanyCustomerQuoteReviewDropoffKey =
    Key('company_customer_quote_review_dropoff');
const Key kCompanyCustomerQuoteAddressWarningKey =
    Key('company_customer_quote_address_warning');
const Key kCompanyCustomerQuoteDescriptionKey =
    Key('company_customer_quote_description');
const Key kCompanyCustomerQuoteDraftSavedKey =
    Key('company_customer_quote_draft_saved');
const Key kCompanyCustomerQuoteOpenKey = Key('company_customer_quote_open');
const Key kCompanyCustomerQuoteSendChannelKey =
    Key('company_customer_quote_send_channel');
const Key kCompanyCustomerQuoteSendRecipientKey =
    Key('company_customer_quote_send_recipient');

class CompanyCustomerQuotePage extends StatefulWidget {
  const CompanyCustomerQuotePage({
    super.key,
    required this.repository,
    required this.customer,
    this.existing,
    this.language,
    this.issuerName,
    this.onOpenBooking,
    this.placeLookup,
    this.initialStartAt,
  });

  final CompanyCustomersRepository repository;
  final CompanyCustomer customer;
  final CompanyCustomerQuote? existing;
  final AppLanguage? language;
  final String? issuerName;
  final void Function(String bookingId)? onOpenBooking;
  final LimousinePlaceLookup? placeLookup;
  final DateTime? initialStartAt;

  @override
  State<CompanyCustomerQuotePage> createState() =>
      _CompanyCustomerQuotePageState();
}

class _CompanyCustomerQuotePageState extends State<CompanyCustomerQuotePage> {
  late final LimousinePlaceLookup _placeLookup;
  late final bool _ownsPlaceLookup;
  late final LimousineAddressFieldController _pickup;
  late final LimousineAddressFieldController _dropoff;
  late final LimousineAddressFieldController _returnFrom;
  late final LimousineAddressFieldController _returnTo;
  late final TextEditingController _passengers;
  late final TextEditingController _description;
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _price;
  late final TextEditingController _currency;
  late final TextEditingController _returnDuration;
  DateTime? _startAt;
  DateTime? _validUntil;
  DateTime? _returnAt;
  CompanyRoundtripChoice _roundtripChoice = CompanyRoundtripChoice.single;
  CompanyRideOptions _rideOptions = const CompanyRideOptions();
  Map<String, dynamic>? _fixedPriceSnapshot;
  String _vatTreatment = 'incl';
  CompanyCustomerQuote? _quote;
  bool _review = false;
  bool _busy = false;
  bool _draftSaved = false;
  String? _error;
  late final String _createIdempotencyKey;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  String _initialQuotePriceText(CompanyCustomerQuote? existing) {
    final cents = existing?.enteredAmountCents;
    if (cents == null) return '';
    return (cents / 100).toStringAsFixed(2);
  }

  String get _issuer {
    final explicit = widget.issuerName?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return widget.customer.companyId;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _quote = existing;
    _createIdempotencyKey = existing == null
        ? 'quote-new-${widget.customer.customerId}-'
              '${DateTime.now().microsecondsSinceEpoch}'
        : 'quote-${existing.quoteId}';
    _ownsPlaceLookup = widget.placeLookup == null;
    _placeLookup = widget.placeLookup ?? LimousinePlaceLookup(country: '');
    _pickup = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'quote_pickup',
      language: _lang.name,
    );
    _dropoff = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'quote_dropoff',
      language: _lang.name,
    );
    _returnFrom = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'quote_return_from',
      language: _lang.name,
    );
    _returnTo = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'quote_return_to',
      language: _lang.name,
    );
    if (existing != null) {
      _pickup.acceptCopy(
        companyAddressValueFromStored(
          text: existing.pickup,
          lat: existing.pickupLat,
          lon: existing.pickupLon,
          placeId: existing.pickupPlaceId,
        ),
      );
      _dropoff.acceptCopy(
        companyAddressValueFromStored(
          text: existing.dropoff,
          lat: existing.dropoffLat,
          lon: existing.dropoffLon,
          placeId: existing.dropoffPlaceId,
        ),
      );
    }
    _startAt = companyFormDateTimeFromIso(existing?.startAt ?? '') ??
        widget.initialStartAt;
    _passengers = TextEditingController(
      text: '${existing?.passengers ?? 1}',
    );
    _description = TextEditingController(text: existing?.description ?? '');
    _name = TextEditingController(
      text: existing?.passengerName.isNotEmpty == true
          ? existing!.passengerName
          : widget.customer.displayName,
    );
    _email = TextEditingController(
      text: existing?.passengerEmail.isNotEmpty == true
          ? existing!.passengerEmail
          : widget.customer.email,
    );
    _phone = TextEditingController(
      text: existing?.passengerPhone.isNotEmpty == true
          ? existing!.passengerPhone
          : companyCustomerInternationalPhone(widget.customer),
    );
    if (existing == null) {
      companyApplyCustomerGroundAddress(
        customer: widget.customer,
        options: _rideOptions,
        pickup: _pickup,
        dropoff: _dropoff,
      );
    }
    _price = TextEditingController(text: _initialQuotePriceText(existing));
    final existingCurrency = existing?.currency.trim() ?? '';
    final settingsCurrency =
        businessSettingsNotifier.value.defaultCurrency.trim();
    _currency = TextEditingController(
      text: existingCurrency.isNotEmpty
          ? existingCurrency.toUpperCase()
          : (settingsCurrency.isEmpty ? 'EUR' : settingsCurrency.toUpperCase()),
    );
    _validUntil = companyFormDateTimeFromIso(existing?.validUntil ?? '');
    _rideOptions = existing?.rideOptions ?? const CompanyRideOptions();
    _fixedPriceSnapshot = existing?.fixedPriceSnapshot;
    _roundtripChoice = existing?.roundtripChoice ?? CompanyRoundtripChoice.single;
    _returnAt = companyFormDateTimeFromIso(existing?.returnPickupIso ?? '');
    _returnDuration = TextEditingController(
      text: existing?.returnDurationMin == null
          ? ''
          : '${existing!.returnDurationMin}',
    );
    if (existing != null && existing.returnFrom.isNotEmpty) {
      _returnFrom.acceptCopy(
        companyAddressValueFromStored(
          text: existing.returnFrom,
          lat: existing.returnPickupLat,
          lon: existing.returnPickupLon,
          placeId: existing.returnPickupPlaceId,
        ),
      );
    }
    if (existing != null && existing.returnTo.isNotEmpty) {
      _returnTo.acceptCopy(
        companyAddressValueFromStored(
          text: existing.returnTo,
          lat: existing.returnDropoffLat,
          lon: existing.returnDropoffLon,
          placeId: existing.returnDropoffPlaceId,
        ),
      );
    }
    _vatTreatment = existing?.vatTreatment.trim().isNotEmpty == true
        ? existing!.vatTreatment
        : 'incl';
    _pickup.addListener(_onAddressChanged);
    _dropoff.addListener(_onAddressChanged);
  }

  void _onAddressChanged() {
    if (!mounted) return;
    setState(() => _fixedPriceSnapshot = null);
  }

  void _onRouteIdentityChanged() {
    if (!mounted) return;
    setState(() => _fixedPriceSnapshot = null);
  }

  @override
  void dispose() {
    _pickup.removeListener(_onAddressChanged);
    _dropoff.removeListener(_onAddressChanged);
    _pickup.dispose();
    _dropoff.dispose();
    _returnFrom.dispose();
    _returnTo.dispose();
    _returnDuration.dispose();
    if (_ownsPlaceLookup) _placeLookup.dispose();
    _passengers.dispose();
    _description.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _price.dispose();
    _currency.dispose();
    super.dispose();
  }

  CompanyQuoteVatBreakdown _vatBreakdown() {
    return computeCompanyQuoteVatBreakdown(
      enteredCents: parseEuroToCents(_price.text),
      treatment: _vatTreatment,
      vatRateRaw: businessSettingsNotifier.value.pricingVatRate,
    );
  }

  String get _currencyCode {
    final text = _currency.text.trim();
    return text.isEmpty ? 'EUR' : text.toUpperCase();
  }

  bool get _addressesComplete =>
      companyAddressIsComplete(_pickup.value) &&
      companyAddressIsComplete(_dropoff.value);

  CompanyCustomerQuoteWrite _write() {
    final pickup = _pickup.value;
    final dropoff = _dropoff.value;
    final pickupSelected =
        pickup.acceptance == LimousineAddressAcceptance.selected;
    final dropoffSelected =
        dropoff.acceptance == LimousineAddressAcceptance.selected;
    final vat = _vatBreakdown();
    return CompanyCustomerQuoteWrite(
      pickup: pickup.displayText,
      dropoff: dropoff.displayText,
      startAt: _startAt == null ? '' : companyFormIsoFromLocal(_startAt!),
      passengers: int.tryParse(_passengers.text.trim()) ?? 1,
      description: _description.text,
      passengerName: _name.text,
      passengerEmail: _email.text,
      passengerPhone: _phone.text,
      enteredAmountCents: parseEuroToCents(_price.text),
      currency: _currency.text,
      vatTreatment: _vatTreatment,
      vatRate: vat.rateMissing ? null : vat.vatRatePercent,
      validUntil: _validUntil == null ? '' : companyFormIsoFromLocal(_validUntil!),
      issuerName: _issuer,
      pickupLat: pickupSelected ? pickup.lat : null,
      pickupLon: pickupSelected ? pickup.lon : null,
      pickupPlaceId: pickupSelected ? (pickup.placeId ?? '') : '',
      dropoffLat: dropoffSelected ? dropoff.lat : null,
      dropoffLon: dropoffSelected ? dropoff.lon : null,
      dropoffPlaceId: dropoffSelected ? (dropoff.placeId ?? '') : '',
      rideOptions: _rideOptions,
      roundtripChoice: _roundtripChoice,
      returnPickupIso: _returnAt == null
          ? ''
          : companyFormIsoFromLocal(_returnAt!),
      returnFrom: _returnFrom.value.displayText,
      returnTo: _returnTo.value.displayText,
      returnDurationMin: int.tryParse(_returnDuration.text.trim()),
      returnPickupLat:
          _returnFrom.value.acceptance == LimousineAddressAcceptance.selected
          ? _returnFrom.value.lat
          : null,
      returnPickupLon:
          _returnFrom.value.acceptance == LimousineAddressAcceptance.selected
          ? _returnFrom.value.lon
          : null,
      returnPickupPlaceId:
          _returnFrom.value.acceptance == LimousineAddressAcceptance.selected
          ? (_returnFrom.value.placeId ?? '')
          : '',
      returnDropoffLat:
          _returnTo.value.acceptance == LimousineAddressAcceptance.selected
          ? _returnTo.value.lat
          : null,
      returnDropoffLon:
          _returnTo.value.acceptance == LimousineAddressAcceptance.selected
          ? _returnTo.value.lon
          : null,
      returnDropoffPlaceId:
          _returnTo.value.acceptance == LimousineAddressAcceptance.selected
          ? (_returnTo.value.placeId ?? '')
          : '',
      fixedPriceSnapshot: _fixedPriceSnapshot,
    );
  }

  Future<void> _saveDraft() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final write = _write();
      final current = _quote;
      final saved = current == null
          ? await widget.repository.createQuote(
              widget.customer.customerId,
              write,
              idempotencyKey: _createIdempotencyKey,
            )
          : await widget.repository.updateQuote(
              current.quoteId,
              write,
              revision: current.revision,
            );
      if (!mounted) return;
      setState(() {
        _quote = saved;
        _busy = false;
        _draftSaved = saved.isDraft;
      });
    } on CompanyCustomerException catch (error) {
      await _finishSaveFailure(error);
    } catch (_) {
      await _finishSaveFailure(
        const CompanyCustomerException('transport_failed', offline: true),
      );
    }
  }

  Future<void> _finishSaveFailure(CompanyCustomerException error) async {
    if (!mounted) return;
    if (_quote == null) {
      try {
        final recovered = await _recoverCreatedDraft();
        if (recovered != null && mounted) {
          setState(() {
            _quote = recovered;
            _busy = false;
            _draftSaved = recovered.isDraft;
            _error = null;
          });
          return;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error.offline
          ? kCompanyCustomersOffline.of(_lang)
          : kCompanyCustomersSaveFailed.of(_lang);
    });
  }

  Future<CompanyCustomerQuote?> _recoverCreatedDraft() async {
    final items = await widget.repository.listQuotes(widget.customer.customerId);
    final pickup = _pickup.value.displayText.trim();
    final dropoff = _dropoff.value.displayText.trim();
    final iata = _rideOptions.airportIata.trim().toUpperCase();
    final flight = _rideOptions.flightNumber.trim().toUpperCase();
    for (final quote in items) {
      if (!quote.isDraft) continue;
      if (quote.pickup.trim() != pickup || quote.dropoff.trim() != dropoff) {
        continue;
      }
      final options = quote.rideOptions;
      if (iata.isNotEmpty &&
          options.airportIata.trim().toUpperCase() != iata) {
        continue;
      }
      if (flight.isNotEmpty &&
          options.flightNumber.trim().toUpperCase() != flight) {
        continue;
      }
      return quote;
    }
    return null;
  }

  Future<void> _send() async {
    if (!hasExplicitQuotePrice(_price.text)) {
      setState(() => _error = kCompanyCustomerQuotePriceRequired.of(_lang));
      return;
    }
    if (!isUsableCompanyCustomerEmail(_email.text)) {
      setState(() => _error = kCompanyCustomerQuoteEmailRequired.of(_lang));
      return;
    }
    if (!_addressesComplete) {
      setState(() => _error = kCompanyCustomerQuoteAddressRequired.of(_lang));
      return;
    }
    await _saveDraft();
    final current = _quote;
    if (current == null) return;
    setState(() => _busy = true);
    try {
      final sent = await widget.repository.sendQuote(current.quoteId);
      if (!mounted) return;
      setState(() {
        _quote = sent;
        _busy = false;
        _review = false;
        _draftSaved = sent.isDraft;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _sendErrorText(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = kCompanyCustomersOffline.of(_lang);
      });
    }
  }

  String _sendErrorText(CompanyCustomerException error) {
    switch (error.code) {
      case 'invalid_quote':
        if (!_addressesComplete) {
          return kCompanyCustomerQuoteAddressRequired.of(_lang);
        }
        return hasExplicitQuotePrice(_price.text)
            ? kCompanyCustomerQuoteEmailRequired.of(_lang)
            : kCompanyCustomerQuotePriceRequired.of(_lang);
      case 'mail_not_configured':
        return kCompanyCustomerQuoteMailNotConfigured.of(_lang);
      case 'send_failed':
        return kCompanyCustomerQuoteSendFailed.of(_lang);
      default:
        return kCompanyCustomersSaveFailed.of(_lang);
    }
  }

  Widget _field(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: child,
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _sendChannel() {
    final email = _email.text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key: kCompanyCustomerQuoteSendChannelKey,
            '${kCompanyCustomerQuoteSendChannel.of(_lang)}: ${kCompanyCustomerQuoteSendChannelEmail.of(_lang)}',
            softWrap: true,
          ),
          Text(
            key: kCompanyCustomerQuoteSendRecipientKey,
            '${kCompanyCustomerQuoteSendRecipient.of(_lang)}: ${email.isEmpty ? '—' : email}',
            softWrap: true,
          ),
          Text(
            kCompanyCustomerQuotePhoneNotChannel.of(_lang),
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyCustomerQuotePageKey,
        appBar: AppBar(title: Text(kCompanyCustomerQuoteTitle.of(_lang))),
        body: SafeArea(
          child: CompanyOpsBoundedForm(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      24 + bottom + kCompanyQuoteStickyActionsClearance,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                Text(
                  '${kCompanyCustomerQuoteIssuer.of(_lang)}: $_issuer',
                  softWrap: true,
                ),
                if (_draftSaved && _quote != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: kCompanyCustomerQuoteDraftSavedKey,
                    children: [
                      Expanded(
                        child: Text(
                          kCompanyCustomerQuoteDraftSaved.of(_lang),
                          softWrap: true,
                        ),
                      ),
                      TextButton(
                        key: kCompanyCustomerQuoteOpenKey,
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(_quote),
                        child: Text(kCompanyCustomerQuoteOpen.of(_lang)),
                      ),
                    ],
                  ),
                ],
                if (_quote != null)
                  Text(
                    companyCustomerQuoteStateLabel(_quote!.state).of(_lang),
                  ),
                if (_quote?.isAccepted == true)
                  Text(kCompanyCustomerQuoteAccepted.of(_lang)),
                if (_quote?.isTestSend == true)
                  Text(kCompanyCustomerQuoteSent.of(_lang)),
                if (_quote?.isAdapterAccepted == true)
                  Text(kCompanyCustomerQuoteAdapterAccepted.of(_lang)),
                if ((_quote?.publicUrl ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(kCompanyCustomerQuoteGuestLink.of(_lang)),
                  SelectableText(
                    _quote!.publicUrl,
                    key: kCompanyCustomerQuoteGuestLinkKey,
                  ),
                ],
                if ((_quote?.bookingId ?? '').isNotEmpty) ...[
                  Text(
                    '${kCompanyCustomerQuoteBookingId.of(_lang)}: ${_quote!.bookingId}',
                  ),
                  if (_quote!.isAccepted && !_quote!.bookingListReady)
                    Text(kCompanyCustomerQuoteBookingNotListed.of(_lang)),
                  if (_quote!.isAccepted)
                    Text(kCompanyCustomerQuoteAssignmentPending.of(_lang)),
                  if (widget.onOpenBooking != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: kCompanyCustomerQuoteViewBookingKey,
                        onPressed: _busy
                            ? null
                            : () => widget.onOpenBooking!(_quote!.bookingId),
                        child: Text(kCompanyCustomerQuoteViewBooking.of(_lang)),
                      ),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, maxLines: 6, softWrap: true),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: kCompanyCustomerQuoteRetryKey,
                      onPressed: _busy ? null : _saveDraft,
                      child: Text(kCompanyCustomersRetry.of(_lang)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _field(
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersDisplayName.of(_lang),
                    ),
                  ),
                ),
                _field(
                  TextFormField(
                    key: kCompanyCustomerQuoteEmailKey,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersEmail.of(_lang),
                    ),
                  ),
                ),
                _hint(kCompanyCustomerQuoteEmailRequired.of(_lang)),
                _field(
                  TextFormField(
                    key: kCompanyCustomerQuotePhoneKey,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomerQuotePhone.of(_lang),
                    ),
                  ),
                ),
                _field(
                  CompanyTripRouteFields(
                    language: _lang,
                    pickup: _pickup,
                    dropoff: _dropoff,
                    rideOptions: _rideOptions,
                    onRideOptionsChanged: (next) {
                      setState(() {
                        _rideOptions = next;
                        _fixedPriceSnapshot = null;
                      });
                    },
                    savedAddresses: widget.customer.addresses,
                    pickupInputKey: kCompanyCustomerQuotePickupFieldKey,
                    dropoffInputKey: kCompanyCustomerQuoteDropoffFieldKey,
                    onRouteIdentityChanged: _onRouteIdentityChanged,
                    showReturnAirportFields:
                        _roundtripChoice != CompanyRoundtripChoice.single,
                  ),
                ),
                _field(
                  CompanyDateTimeFields(
                    fieldId: 'quote_start',
                    language: _lang,
                    value: _startAt,
                    onChanged: (next) => setState(() => _startAt = next),
                    dateLabel: kCompanyFormDate.of(_lang),
                  ),
                ),
                _field(
                  CompanyRoundtripFields(
                    language: _lang,
                    choice: _roundtripChoice,
                    onChoiceChanged: (next) {
                      setState(() {
                        _roundtripChoice = next;
                        if (next == CompanyRoundtripChoice.single) {
                          _returnAt = null;
                          return;
                        }
                        _returnAt ??= _startAt?.add(const Duration(hours: 3));
                        if (_returnFrom.value.displayText.trim().isEmpty &&
                            _dropoff.value.displayText.trim().isNotEmpty) {
                          _returnFrom.acceptCopy(_dropoff.value);
                        }
                        if (_returnTo.value.displayText.trim().isEmpty &&
                            _pickup.value.displayText.trim().isNotEmpty) {
                          _returnTo.acceptCopy(_pickup.value);
                        }
                      });
                    },
                    returnPickup: _returnAt,
                    onReturnPickupChanged: (next) =>
                        setState(() => _returnAt = next),
                    returnTo: _returnTo,
                    savedAddresses: widget.customer.addresses,
                  ),
                ),
                _field(
                  TextFormField(
                    controller: _passengers,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomerQuotePassengers.of(_lang),
                    ),
                  ),
                ),
                CompanyRideOptionsForm(
                  language: _lang,
                  value: _rideOptions,
                  showAirportRouteFields: false,
                  showReturnAirportFields: false,
                  onChanged: (next) => setState(() {
                    _rideOptions = next;
                    _fixedPriceSnapshot = null;
                  }),
                ),
                const SizedBox(height: 12),
                CompanyFixedPriceSuggestion(
                  language: _lang,
                  from: _pickup.value.displayText,
                  to: _dropoff.value.displayText,
                  fromCity: _pickup.value.displayText,
                  toCity: _dropoff.value.displayText,
                  airportIata: _rideOptions.airportIata,
                  airportDirection: _rideOptions.airportDirection,
                  passengers: int.tryParse(_passengers.text.trim()) ?? 1,
                  tier: _rideOptions.tier,
                  pickupLat: _pickup.value.lat,
                  pickupLon: _pickup.value.lon,
                  dropoffLat: _dropoff.value.lat,
                  dropoffLon: _dropoff.value.lon,
                  hasManualAmount: hasExplicitQuotePrice(_price.text),
                  onApply: (snapshot) {
                    final total = snapshot['total_incl_vat'];
                    setState(() {
                      _fixedPriceSnapshot = snapshot;
                      if (total != null) {
                        _price.text = total.toString();
                      }
                    });
                  },
                ),
                if (_fixedPriceSnapshot != null) ...[
                  const SizedBox(height: 8),
                  CompanyFixedPriceBreakdown(
                    language: _lang,
                    snapshot: _fixedPriceSnapshot!,
                  ),
                ],
                const SizedBox(height: 8),
                _field(
                  TextFormField(
                    key: kCompanyCustomerQuoteDescriptionKey,
                    controller: _description,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomerQuoteDescription.of(_lang),
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                _hint(kCompanyCustomerQuotePublicDescriptionHint.of(_lang)),
                Text(
                  kCompanyCustomerQuotePrice.of(_lang),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _field(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          key: kCompanyCustomerQuotePriceKey,
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: kCompanyCustomerQuotePrice.of(_lang),
                          ),
                          onChanged: (_) {
                            final applied =
                                _fixedPriceSnapshot?['total_incl_vat']
                                    ?.toString();
                            setState(() {
                              if (applied != null &&
                                  _price.text.trim() != applied) {
                                _fixedPriceSnapshot = null;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: kCompanyCustomerQuoteCurrencyKey,
                          controller: _currency,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: kCompanyCustomerQuoteCurrency.of(_lang),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
                _hint(kCompanyCustomerQuotePriceRequired.of(_lang)),
                if (_roundtripChoice != CompanyRoundtripChoice.single)
                  _hint(kCompanyRoundtripPriceCovers.of(_lang)),
                _field(
                  DropdownButtonFormField<String>(
                    key: kCompanyCustomerQuoteVatFieldKey,
                    isExpanded: true,
                    initialValue: _vatTreatment,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomerQuoteVat.of(_lang),
                    ),
                    items: [
                      for (final code in const ['incl', 'excl', 'none', 'zero'])
                        DropdownMenuItem(
                          value: code,
                          child: Text(
                            companyCustomerQuoteVatOption(code).of(_lang),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _vatTreatment = value);
                      }
                    },
                  ),
                ),
                Padding(
                  key: kCompanyCustomerQuoteVatBreakdownKey,
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in companyQuoteVatBreakdownLines(
                        breakdown: _vatBreakdown(),
                        language: _lang,
                        currency: _currencyCode,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(line, softWrap: true),
                        ),
                    ],
                  ),
                ),
                Padding(
                  key: kCompanyCustomerQuoteIncludedKey,
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kCompanyCustomerQuoteIncluded.of(_lang),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _rideOptions.isEmpty
                            ? kCompanyCustomerQuoteIncludedNone.of(_lang)
                            : formatCompanyRideOptionsSummary(
                                _rideOptions,
                                language: _lang,
                              ),
                        softWrap: true,
                      ),
                      if (_description.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          kCompanyCustomerQuotePriceConditions.of(_lang),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(_description.text.trim(), softWrap: true),
                      ],
                    ],
                  ),
                ),
                _field(
                  CompanyDateTimeFields(
                    fieldId: 'quote_valid_until',
                    language: _lang,
                    value: _validUntil,
                    onChanged: (next) => setState(() => _validUntil = next),
                    dateLabel: kCompanyCustomerQuoteValidUntil.of(_lang),
                  ),
                ),
                CompanyInternalRatesPanel(
                  language: _lang,
                  options: _rideOptions,
                ),
                if (_review) ...[
                  const SizedBox(height: 8),
                  Text(kCompanyCustomerQuoteReview.of(_lang)),
                  Text(
                    key: kCompanyCustomerQuoteReviewPickupKey,
                    companyAddressReviewLine(_pickup.value, _lang),
                    softWrap: true,
                  ),
                  Text(
                    key: kCompanyCustomerQuoteReviewDropoffKey,
                    companyAddressReviewLine(_dropoff.value, _lang),
                    softWrap: true,
                  ),
                  if (!_addressesComplete)
                    Text(
                      key: kCompanyCustomerQuoteAddressWarningKey,
                      kCompanyCustomerQuoteAddressRequired.of(_lang),
                      softWrap: true,
                    ),
                  if (_startAt != null)
                    Text(formatCompanyFormDateTime(_startAt!, _lang)),
                  if (_roundtripChoice != CompanyRoundtripChoice.single) ...[
                    Text(
                      companyRoundtripChoiceLabel(_roundtripChoice).of(_lang),
                      softWrap: true,
                    ),
                    Text(
                      '${kCompanyRoundtripOutbound.of(_lang)}: ${_pickup.value.displayText} → ${_dropoff.value.displayText}',
                      softWrap: true,
                    ),
                    Text(
                      '${kCompanyRoundtripReturn.of(_lang)}: ${_returnFrom.value.displayText} → ${_returnTo.value.displayText}',
                      softWrap: true,
                    ),
                    if (_returnAt != null)
                      Text(formatCompanyFormDateTime(_returnAt!, _lang)),
                    Text(
                      kCompanyRoundtripPriceCovers.of(_lang),
                      softWrap: true,
                    ),
                  ],
                  Text(companyCustomerQuoteVatOption(_vatTreatment).of(_lang)),
                  for (final line in companyQuoteVatBreakdownLines(
                    breakdown: _vatBreakdown(),
                    language: _lang,
                    currency: _currencyCode,
                  ))
                    Text(line, softWrap: true),
                  Text(_issuer, softWrap: true),
                  if (!_rideOptions.isEmpty) ...[
                    Text(kCompanyCustomerQuoteIncluded.of(_lang)),
                    Text(
                      formatCompanyRideOptionsSummary(
                        _rideOptions,
                        language: _lang,
                      ),
                      softWrap: true,
                    ),
                  ],
                  if (_description.text.trim().isNotEmpty) ...[
                    Text(kCompanyCustomerQuotePriceConditions.of(_lang)),
                    Text(_description.text.trim(), softWrap: true),
                  ],
                  const SizedBox(height: 8),
                  _sendChannel(),
                ],
              ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_review) _sendChannel(),
                      Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: kCompanyCustomerQuoteSaveKey,
                        onPressed: _busy ? null : _saveDraft,
                        child: Text(kCompanyCustomerQuoteSaveDraft.of(_lang)),
                      ),
                      OutlinedButton(
                        key: kCompanyCustomerQuoteReviewKey,
                        onPressed: _busy
                            ? null
                            : () => setState(() => _review = true),
                        child: Text(kCompanyCustomerQuoteReview.of(_lang)),
                      ),
                      FilledButton.tonal(
                        key: kCompanyCustomerQuoteSendKey,
                        onPressed: _busy ? null : _send,
                        child: Text(kCompanyCustomerQuoteSend.of(_lang)),
                      ),
                    ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
