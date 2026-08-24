import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import '../company/company_fleet_operational.dart';
import 'limousine_address_field.dart';
import 'limousine_address_lookup.dart';
import 'limousine_business_setup.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_external_quote.dart';
import 'limousine_external_quote_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_p2d4c1c_journey.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_api.dart';
import 'limousine_quote_inbox_labels.dart';
import 'limousine_quote_presentation.dart';
import 'limousine_quote_requests_nav.dart';
import 'limousine_quote_respond_form.dart';

class LimousineExternalQuoteCreatePage extends StatefulWidget {
  const LimousineExternalQuoteCreatePage({
    super.key,
    required this.gateway,
    this.offers = const <Map<String, dynamic>>[],
    this.vehicles = const <VehicleProfile>[],
    this.share,
    this.copy,
    this.quoteDraft,
    this.placeLookup,
  });

  final LimousineExternalQuoteGateway gateway;
  final List<Map<String, dynamic>> offers;
  final List<VehicleProfile> vehicles;
  final Future<void> Function(String url)? share;
  final Future<void> Function(String url)? copy;
  final LimousineCompanyQuoteDraft? quoteDraft;
  final LimousinePlaceLookup? placeLookup;

  @override
  State<LimousineExternalQuoteCreatePage> createState() =>
      _LimousineExternalQuoteCreatePageState();
}

class _LimousineExternalQuoteCreatePageState
    extends State<LimousineExternalQuoteCreatePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _company = TextEditingController();
  final _pax = TextEditingController(text: '2');
  final _bags = TextEditingController(text: '0');
  final _occasion = TextEditingController();
  String _locale = 'nl';
  bool _roundtrip = false;
  DateTime _when = DateTime.now().add(const Duration(days: 3));
  DateTime? _returnWhen;
  String _offerId = '';
  String _vehicleId = '';
  String _serviceClassId = '';
  final Set<String> _extraIds = <String>{};
  bool _submitting = false;
  String? _error;
  LimousineCompanyQuoteDraft? _previewDraft;
  LimousineExternalQuoteCreateResult? _created;
  List<Map<String, dynamic>> _offers = const <Map<String, dynamic>>[];
  late final LimousinePlaceLookup _placeLookup;
  late final bool _ownsLookup;
  late final LimousineAddressFieldController _pickup;
  late final LimousineAddressFieldController _destination;
  final List<LimousineAddressFieldController> _stopFields =
      <LimousineAddressFieldController>[];
  int _stopSeq = 0;

  AppLanguage get _lang => appLanguageNotifier.value;
  String _t(LocalizedText text) => text.of(_lang);
  List<Map<String, dynamic>> get _quoteOffers =>
      _offers.where(limousineQuoteOnRequestIsEnabled).toList(growable: false);
  List<VehicleProfile> get _limousineVehicles =>
      limousineSetupLimousineVehicles(
        widget.vehicles.isNotEmpty
            ? widget.vehicles
            : companyOperationalVehicles(),
      );

  Map<String, dynamic>? get _selectedOffer {
    for (final offer in _quoteOffers) {
      if ((offer['offer_id'] ?? '').toString() == _offerId) return offer;
    }
    return null;
  }

  List<Map<String, String>> get _offerExtras {
    final raw = _selectedOffer?['paid_extras'];
    if (raw is! List) return const <Map<String, String>>[];
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = (item['extra_id'] ?? item['item_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final label = (item['label'] ?? item['name'] ?? id).toString().trim();
      out.add(<String, String>{'id': id, 'label': label.isEmpty ? id : label});
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _ownsLookup = widget.placeLookup == null;
    _placeLookup = widget.placeLookup ?? LimousinePlaceLookup();
    _pickup = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'own_pickup',
      language: _lang.name,
    );
    _destination = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'own_destination',
      language: _lang.name,
    );
    _pickup.addListener(_onAddressChanged);
    _destination.addListener(_onAddressChanged);
    _offers = widget.offers.isNotEmpty
        ? widget.offers
        : limousineQuoteRequestsConfirmedOffers.value;
    if (_offers.isEmpty) {
      _loadOffers();
    } else {
      _selectDefaults();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _mobile.dispose();
    _company.dispose();
    _pickup
      ..removeListener(_onAddressChanged)
      ..dispose();
    _destination
      ..removeListener(_onAddressChanged)
      ..dispose();
    for (final stop in _stopFields) {
      stop
        ..removeListener(_onAddressChanged)
        ..dispose();
    }
    if (_ownsLookup) {
      _placeLookup.dispose();
    }
    _pax.dispose();
    _bags.dispose();
    _occasion.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    try {
      final data = await fetchAdminLimousinePricing();
      if (!mounted) return;
      setState(() {
        _offers = limousineOffersFromPricingPayload(data);
        _selectDefaults();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectDefaults());
    }
  }

  void _selectDefaults() {
    final quoteOffers = _offers
        .where(limousineQuoteOnRequestIsEnabled)
        .toList();
    if (quoteOffers.isNotEmpty) {
      _applyOffer((quoteOffers.first['offer_id'] ?? '').toString());
    }
    final limos = _limousineVehicles;
    if (_vehicleId.isEmpty && limos.isNotEmpty) {
      _vehicleId = limos.first.id;
      if (limos.first.serviceClassId.isNotEmpty) {
        _serviceClassId = limos.first.serviceClassId;
      }
    }
  }

  void _applyOffer(String offerId) {
    _offerId = offerId;
    final offer = _selectedOffer;
    if (offer == null) return;
    final vehicleId = (offer['vehicle_id'] ?? '').toString();
    if (vehicleId.isNotEmpty) _vehicleId = vehicleId;
    final serviceClass = (offer['service_class_id'] ?? '').toString();
    if (serviceClass.isNotEmpty) _serviceClassId = serviceClass;
  }

  LimousineExternalContactSummary _contact() {
    return LimousineExternalContactSummary(
      displayName: _name.text.trim(),
      mail: _email.text.trim(),
      mobile: _mobile.text.trim(),
      locale: normalizeLimousineQuoteLocale(_locale),
      companyLabel: _company.text.trim(),
    );
  }

  LimousineExternalJourneyDraft _journey() {
    return LimousineExternalJourneyDraft(
      offerId: _offerId,
      vehicleId: _vehicleId,
      serviceClassId: _serviceClassId,
      from: _pickup.value.routeText,
      to: _destination.value.routeText,
      stops: _stopFields
          .map((stop) => stop.value.routeText)
          .where((stop) => stop.isNotEmpty)
          .toList(growable: false),
      scheduledPickupIso: _when.toUtc().toIso8601String(),
      roundtrip: _roundtrip,
      returnPickupIso: _roundtrip
          ? (_returnWhen ?? _when.add(const Duration(hours: 4)))
                .toUtc()
                .toIso8601String()
          : '',
      pax: int.tryParse(_pax.text.trim()),
      bags: int.tryParse(_bags.text.trim()),
      occasion: _occasion.text.trim(),
      selectedExtraIds: _extraIds.toList(growable: false),
      locale: _locale,
    );
  }

  void _finalizeAddresses() {
    _pickup.language = _lang.name;
    _destination.language = _lang.name;
    if (!_pickup.value.isRouteReady) {
      _pickup.confirmManualFallback();
    }
    if (!_destination.value.isRouteReady) {
      _destination.confirmManualFallback();
    }
    for (final stop in _stopFields) {
      stop.language = _lang.name;
      if (stop.textController.text.trim().isEmpty) continue;
      if (!stop.value.isRouteReady) {
        stop.confirmManualFallback();
      }
    }
  }

  String? _formError() {
    _finalizeAddresses();
    final contact = validateOwnCustomerContactForm(
      name: _name.text,
      email: _email.text,
      mobile: _mobile.text,
    );
    if (!contact.ok) return _t(kLimousineExternalContactRequired);
    final journey = validateOwnCustomerJourneyForm(
      from: _pickup.textController.text,
      to: _destination.textController.text,
      offerId: _offerId,
      vehicleId: _vehicleId,
      pax: int.tryParse(_pax.text.trim()),
      bags: int.tryParse(_bags.text.trim()),
      roundtrip: _roundtrip,
      returnPickupIso: _roundtrip
          ? (_returnWhen ?? _when.add(const Duration(hours: 4)))
                .toUtc()
                .toIso8601String()
          : '',
    );
    if (journey.code == 'pax') return _t(kLimousineExternalPaxRange);
    if (journey.code == 'bags') return _t(kLimousineExternalBagsRange);
    if (!journey.ok) return _t(kLimousineExternalJourneyRequired);
    if (!_pickup.value.isRouteReady || !_destination.value.isRouteReady) {
      return _t(kLimousineExternalJourneyRequired);
    }
    for (final stop in _stopFields) {
      if (stop.textController.text.trim().isEmpty) continue;
      if (!stop.value.isRouteReady) {
        return _t(kLimousineExternalJourneyRequired);
      }
    }
    return null;
  }

  Future<void> _continueToQuote() async {
    final error = _formError();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final provided = widget.quoteDraft;
    if (provided != null) {
      setState(() {
        _error = null;
        _previewDraft = provided;
      });
      return;
    }
    final draft = await Navigator.of(context).push<LimousineCompanyQuoteDraft>(
      MaterialPageRoute(
        builder: (_) => LimousineQuoteEditorPage(
          record: LimousineQuoteRequest.fromJson(<String, dynamic>{
            'quote_request_id': 'limq_external_draft',
            'state': 'requested',
            'revision': 1,
            'locale': _locale,
          }),
        ),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _error = null;
      _previewDraft = draft;
    });
  }

  Future<void> _editPreview() async {
    final current = _previewDraft;
    final draft = await Navigator.of(context).push<LimousineCompanyQuoteDraft>(
      MaterialPageRoute(
        builder: (_) => LimousineQuoteEditorPage(
          record: LimousineQuoteRequest.fromJson(<String, dynamic>{
            'quote_request_id': 'limq_external_draft',
            'state': 'requested',
            'revision': 1,
            'locale': _locale,
            if (current != null && (current.totalInclVatCents ?? 0) > 0)
              'quote': limousineCompanyQuoteDraftEditorSeed(current),
          }),
        ),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _previewDraft = draft);
  }

  Future<void> _submit(LimousineCompanyQuoteDraft draft) async {
    if (_submitting) return;
    final error = _formError();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final quote = draft.toWorkerQuote();
      if (_occasion.text.trim().isNotEmpty || _name.text.trim().isNotEmpty) {
        quote['public_text'] = <String, String>{
          _locale: _occasion.text.trim().isEmpty
              ? draft.importantInformation[_locale] ?? ''
              : _occasion.text.trim(),
        };
      }
      final created = await widget.gateway.createExternal(
        contact: _contact(),
        request: _journey(),
        quote: quote,
      );
      if (!mounted) return;
      setState(() {
        _created = created;
        _previewDraft = null;
      });
    } on LimousineQuoteInboxException catch (error) {
      if (!mounted) return;
      setState(() => _error = limousineQuoteErrorLabel(error, _lang));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = limousineQuoteErrorLabel(
          const LimousineQuoteInboxException(
            kind: LimousineQuoteInboxErrorKind.network,
            code: 'network',
          ),
          _lang,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copyLink() async {
    final created = _created;
    if (created == null) return;
    final result = await widget.gateway.invitation(
      quoteRequestId: created.record.quoteRequestId,
      action: 'copy',
    );
    final url = result.invitationUrl;
    if (widget.copy != null) {
      await widget.copy!(url);
    } else {
      await Clipboard.setData(ClipboardData(text: url));
    }
    if (!mounted) return;
    setState(
      () => _created = LimousineExternalQuoteCreateResult(
        record: result.record,
        invitationUrl: url,
        contact: created.contact,
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t(kLimousineExternalLinkCopied))));
  }

  Future<void> _shareLink() async {
    final created = _created;
    if (created == null) return;
    final result = await widget.gateway.invitation(
      quoteRequestId: created.record.quoteRequestId,
      action: 'share',
    );
    final url = result.invitationUrl;
    if (widget.share != null) {
      await widget.share!(url);
    } else {
      await Share.share(url);
    }
    if (!mounted) return;
    setState(
      () => _created = LimousineExternalQuoteCreateResult(
        record: result.record,
        invitationUrl: url,
        contact: created.contact,
      ),
    );
  }

  Future<void> _pickWhen({required bool returning}) async {
    final current = returning
        ? (_returnWhen ?? _when.add(const Duration(hours: 4)))
        : _when;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    final next = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? current.hour,
      time?.minute ?? current.minute,
    );
    setState(() {
      if (returning) {
        _returnWhen = next;
      } else {
        _when = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        _syncAddressLanguages();
        return ValueListenableBuilder<BusinessThemeVariant>(
          valueListenable: businessThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForBusinessTheme(variant);
            return Scaffold(
              key: kLimousineExternalQuotePageKey,
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.background,
                foregroundColor: palette.textPrimary,
                title: Text(_t(kLimousineExternalQuoteCreateAction)),
              ),
              body: SafeArea(
                key: kLimousineExternalQuoteSafeAreaKey,
                top: false,
                minimum: const EdgeInsets.only(bottom: 12),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _t(kLimousineExternalQuoteCreateSubtitle),
                        style: TextStyle(
                          color: palette.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: palette.danger)),
                      ],
                      if (_created != null)
                        ..._createdChildren(palette)
                      else if (_previewDraft != null)
                        ..._previewChildren(palette, _previewDraft!)
                      else
                        ..._formChildren(palette),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _createdChildren(BusinessThemePalette palette) {
    return [
      const SizedBox(height: 16),
      LimousineExternalContactSummaryCard(contact: _created!.contact),
      const SizedBox(height: 12),
      LimousineExternalDeliveryTimeline(
        delivery: _created!.record.externalDelivery,
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: kLimousineExternalCopyLinkKey,
        onPressed: _copyLink,
        icon: const Icon(Icons.copy),
        label: Text(_t(kLimousineExternalCopyLink)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: kLimousineExternalShareLinkKey,
        onPressed: _shareLink,
        icon: const Icon(Icons.share),
        label: Text(_t(kLimousineExternalShareLink)),
      ),
    ];
  }

  List<Widget> _previewChildren(
    BusinessThemePalette palette,
    LimousineCompanyQuoteDraft draft,
  ) {
    final contact = _contact();
    final journey = _journey();
    final money = previewOwnCustomerQuoteMoney(
      enteredCents: draft.totalInclVatCents ?? 0,
      vatTreatment: draft.vatTreatment,
      vatRate: draft.vatRate ?? 0.06,
    );
    final vehicle = _limousineVehicles.cast<VehicleProfile?>().firstWhere(
      (item) => item?.id == _vehicleId,
      orElse: () => null,
    );
    final delivery = [
      if (contact.mail.isNotEmpty) contact.mail,
      if (contact.mobile.isNotEmpty) contact.mobile,
    ].join(' · ');
    return [
      const SizedBox(height: 16),
      Container(
        key: kLimousineExternalPreviewKey,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(kLimousineExternalPreviewTitle),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            _previewBlock(palette, _t(kLimousineExternalPreviewCustomer), [
              contact.displayName,
              if (contact.companyLabel.isNotEmpty) contact.companyLabel,
              '${_t(kLimousineExternalDeliveryMethod)}: $delivery',
              '${_t(kLimousineExternalContactLocale)}: ${contact.locale}',
            ]),
            _previewBlock(palette, _t(kLimousineExternalPreviewJourney), [
              '${_t(kLimousineQuotePickup)}: ${journey.from}',
              '${_t(kLimousineQuoteDestination)}: ${journey.to}',
              if (journey.stops.isNotEmpty)
                '${_t(kLimousineQuoteStops)}: ${journey.stops.join(', ')}',
              '${_t(kLimousineQuoteWhen)}: ${formatLimousineOwnCustomerDateTime(_when, _lang)}',
              if (journey.roundtrip)
                '${_t(kLimousineExternalReturnToggle)}: ${formatLimousineOwnCustomerDateTime(_returnWhen ?? _when.add(const Duration(hours: 4)), _lang)}',
              '${_t(kLimousineQuotePassengers)}: ${journey.pax}',
              '${_t(kLimousineQuoteLuggage)}: ${journey.bags}',
              if (vehicle != null)
                '${_t(kLimousineQuoteVehicle)}: ${vehicle.vehicleName.isEmpty ? vehicle.id : vehicle.vehicleName}',
            ]),
            _previewBlock(
              palette,
              _t(kLimousineExternalPreviewMoney),
              [
                '${_t(kLimousineQuoteNetAmount)}: ${formatLimousineMoney(money.netCents, draft.currency)}',
                '${_t(kLimousineQuoteVatAmount)} ${ownCustomerVatPercentLabel(money.vatRate)}: ${formatLimousineMoney(money.vatCents, draft.currency)}',
                '${_t(kLimousineQuoteGrossAmount)}: ${formatLimousineMoney(money.grossCents, draft.currency)}',
              ],
              key: kLimousineExternalPreviewMoneyKey,
            ),
            KeyedSubtree(
              key: kLimousineExternalPreviewVatKey,
              child: const SizedBox.shrink(),
            ),
            KeyedSubtree(
              key: kLimousineExternalPreviewTotalKey,
              child: Text(
                formatLimousineMoney(money.grossCents, draft.currency),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _previewBlock(palette, _t(kLimousineExternalPreviewTerms), [
              '${_t(kLimousineQuoteCancelDeadline)}: ${draft.cancellationDeadlineHours ?? 0}h',
              '${_t(kLimousineQuoteCancelPenalty)}: ${draft.cancellationPenaltyPercent ?? 0}%',
              '${_t(kLimousineQuoteNoShow)}: ${draft.noShowPenaltyPercent ?? 0}%',
              '${_t(kLimousineQuoteWaitingIncluded)}: ${draft.waitingTimeIncludedMinutes ?? 0}',
              '${_t(kLimousineQuoteOvertime)}: ${draft.overtimeCentsPerHour ?? 0}',
              '${_t(kLimousineQuoteInboxValidUntil)} ${draft.expiresAt}',
            ]),
            for (final note in limousineQuoteCommercialNotesFromDraft(
              draft,
              language: _lang,
            ))
              _previewBlock(palette, note.label.of(_lang), [
                note.value,
              ], key: _previewNoteKey(note.label)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: kLimousineExternalPreviewSendKey,
        onPressed: _submitting ? null : () => _submit(draft),
        child: Text(_t(kLimousineExternalPreviewSend)),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: kLimousineExternalPreviewEditKey,
        onPressed: _editPreview,
        child: Text(_t(kLimousineExternalPreviewEdit)),
      ),
      TextButton(
        key: kLimousineExternalPreviewDiscardKey,
        onPressed: () => setState(() => _previewDraft = null),
        child: Text(_t(kLimousineExternalPreviewDiscard)),
      ),
    ];
  }

  Key? _previewNoteKey(LocalizedText label) {
    if (label == kLimousineQuoteIncludedServices) {
      return kLimousineExternalPreviewIncludedKey;
    }
    if (label == kLimousineQuoteMobilisation) {
      return kLimousineExternalPreviewMobilisationKey;
    }
    if (label == kLimousineQuoteCustomerObligations) {
      return kLimousineExternalPreviewObligationsKey;
    }
    if (label == kLimousineQuoteImportantInfo) {
      return kLimousineExternalPreviewImportantKey;
    }
    return null;
  }

  Widget _previewBlock(
    BusinessThemePalette palette,
    String title,
    List<String> lines, {
    Key? key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: TextStyle(color: palette.textSecondary)),
            ),
        ],
      ),
    );
  }

  static const double _sectionGap = 22;
  static const double _outlinedGap = 24;
  static const double _plainGap = 16;

  List<Widget> _formChildren(BusinessThemePalette palette) {
    return [
      _sectionTitle(
        palette,
        _t(kLimousineExternalContactSection),
        key: kLimousineExternalContactSectionKey,
      ),
      _field(
        palette,
        _name,
        kLimousineExternalContactName,
        kLimousineExternalContactNameKey,
      ),
      _field(
        palette,
        _email,
        kLimousineExternalContactEmail,
        kLimousineExternalContactEmailKey,
        keyboard: TextInputType.emailAddress,
      ),
      _field(
        palette,
        _mobile,
        kLimousineExternalContactMobile,
        kLimousineExternalContactMobileKey,
        keyboard: TextInputType.phone,
      ),
      _field(
        palette,
        _company,
        kLimousineExternalContactCompany,
        kLimousineExternalContactCompanyKey,
      ),
      _outlinedControl(
        DropdownButtonFormField<String>(
          key: kLimousineExternalContactLocaleKey,
          isExpanded: true,
          value: _locale,
          decoration: _decoration(palette, kLimousineExternalContactLocale),
          items: const [
            DropdownMenuItem(value: 'nl', child: Text('NL')),
            DropdownMenuItem(value: 'en', child: Text('EN')),
            DropdownMenuItem(value: 'fr', child: Text('FR')),
            DropdownMenuItem(value: 'es', child: Text('ES')),
          ],
          onChanged: (value) => setState(
            () => _locale = normalizeLimousineQuoteLocale(value ?? 'nl'),
          ),
        ),
      ),
      _sectionTitle(
        palette,
        _t(kLimousineQuoteJourneyCard),
        key: kLimousineExternalJourneySectionKey,
      ),
      _addressField(
        palette,
        controller: _pickup,
        label: kLimousineQuotePickup,
        inputKey: kLimousineExternalPickupKey,
        showCurrentLocation: true,
      ),
      _addressField(
        palette,
        controller: _destination,
        label: kLimousineQuoteDestination,
        inputKey: kLimousineExternalDestinationKey,
      ),
      KeyedSubtree(
        key: kLimousineExternalStopsKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _stopFields.length; i++) _stopRow(palette, i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: kLimousineExternalAddStopKey,
                onPressed: _stopFields.length >= 8
                    ? null
                    : () => setState(_addStop),
                icon: const Icon(Icons.add),
                label: Text(_t(kLimousineCustomerAddStop)),
              ),
            ),
          ],
        ),
      ),
      _plainControl(
        ListTile(
          key: kLimousineExternalWhenKey,
          contentPadding: EdgeInsets.zero,
          title: Text(
            _t(kLimousineQuoteWhen),
            style: TextStyle(color: palette.textPrimary),
          ),
          subtitle: Text(
            formatLimousineOwnCustomerDateTime(_when, _lang),
            style: TextStyle(color: palette.textSecondary),
          ),
          onTap: () => _pickWhen(returning: false),
        ),
      ),
      _plainControl(
        SwitchListTile(
          key: kLimousineExternalReturnKey,
          contentPadding: EdgeInsets.zero,
          title: Text(
            _t(kLimousineExternalReturnToggle),
            style: TextStyle(color: palette.textPrimary),
          ),
          value: _roundtrip,
          onChanged: (value) => setState(() {
            _roundtrip = value;
            _returnWhen ??= _when.add(const Duration(hours: 4));
          }),
        ),
      ),
      if (_roundtrip)
        _plainControl(
          ListTile(
            key: kLimousineExternalReturnWhenKey,
            contentPadding: EdgeInsets.zero,
            title: Text(
              _t(kLimousineExternalReturnWhen),
              style: TextStyle(color: palette.textPrimary),
            ),
            subtitle: Text(
              formatLimousineOwnCustomerDateTime(
                _returnWhen ?? _when.add(const Duration(hours: 4)),
                _lang,
              ),
              style: TextStyle(color: palette.textSecondary),
            ),
            onTap: () => _pickWhen(returning: true),
          ),
        ),
      _field(
        palette,
        _pax,
        kLimousineQuotePassengers,
        kLimousineExternalPaxKey,
        keyboard: TextInputType.number,
      ),
      _field(
        palette,
        _bags,
        kLimousineQuoteLuggage,
        kLimousineExternalBagsKey,
        keyboard: TextInputType.number,
      ),
      _field(
        palette,
        _occasion,
        kLimousineQuoteImportantInfo,
        kLimousineExternalOccasionKey,
      ),
      if (_quoteOffers.isNotEmpty) _offerSelector(palette),
      if (_offerExtras.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: _plainGap),
          child: Text(
            _t(kLimousineExternalOptionalExtras),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            key: kLimousineExternalExtrasKey,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final extra in _offerExtras)
                FilterChip(
                  label: Text(extra['label']!),
                  selected: _extraIds.contains(extra['id']),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _extraIds.add(extra['id']!);
                    } else {
                      _extraIds.remove(extra['id']);
                    }
                  }),
                ),
            ],
          ),
        ),
      ],
      _sectionTitle(
        palette,
        _t(kLimousineQuoteVehicle),
        key: kLimousineExternalVehicleSectionKey,
      ),
      Column(
        key: kLimousineExternalVehicleKey,
        children: [
          for (final vehicle in _limousineVehicles)
            _vehicleCard(palette, vehicle),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: _sectionGap, bottom: 8),
        child: FilledButton(
          key: kLimousineExternalSubmitKey,
          onPressed: _submitting ? null : _continueToQuote,
          child: Text(_t(kLimousineExternalContinueQuote)),
        ),
      ),
    ];
  }

  Widget _vehicleCard(BusinessThemePalette palette, VehicleProfile vehicle) {
    final selected = vehicle.id == _vehicleId;
    final photo = (vehicle.publicPhotoUrl ?? '').trim();
    final classLabel = vehicle.serviceClassId.isEmpty
        ? ''
        : limousineServiceClassLabel(vehicle.serviceClassId, _lang);
    final selectedFill = Color.alphaBlend(
      palette.accent.withOpacity(palette.isDark ? 0.16 : 0.10),
      palette.surface,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _vehicleId = vehicle.id;
            if (vehicle.serviceClassId.isNotEmpty) {
              _serviceClassId = vehicle.serviceClassId;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            key: limousineExternalVehicleCardKey(vehicle.id),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? selectedFill : palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? palette.accent : palette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                if (photo.startsWith('https://'))
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        photo,
                        width: 64,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.vehicleName.isEmpty
                            ? vehicle.id
                            : vehicle.vehicleName,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (classLabel.isNotEmpty)
                        Text(
                          classLabel,
                          style: TextStyle(color: palette.textSecondary),
                        ),
                      Text(
                        '${_t(kLimousineExternalVehicleCapacity)}: ${vehicle.passengerCapacity}',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    key: kLimousineExternalVehicleSelectedIconKey,
                    color: palette.accent,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _syncAddressLanguages() {
    final code = _lang.name;
    _pickup.language = code;
    _destination.language = code;
    for (final stop in _stopFields) {
      stop.language = code;
    }
  }

  void _onAddressChanged() {
    _syncAddressLanguages();
    if (mounted) setState(() {});
  }

  void _addStop() {
    if (_stopFields.length >= 8) return;
    final field = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: 'own_stop_${_stopSeq++}',
      language: _lang.name,
    );
    field.addListener(_onAddressChanged);
    _stopFields.add(field);
  }

  void _removeStop(int index) {
    if (index < 0 || index >= _stopFields.length) return;
    final field = _stopFields.removeAt(index);
    field
      ..removeListener(_onAddressChanged)
      ..dispose();
  }

  void _moveStop(int index, int delta) {
    final next = index + delta;
    if (index < 0 || next < 0 || index >= _stopFields.length) return;
    if (next >= _stopFields.length) return;
    final field = _stopFields.removeAt(index);
    _stopFields.insert(next, field);
  }

  Widget _offerSelector(BusinessThemePalette palette) {
    final offers = _quoteOffers;
    final labels = limousineOfferCatalogDisplayLabels(offers, _lang);
    if (offers.length == 1) {
      final offerId = (offers.first['offer_id'] ?? '').toString();
      if (_offerId != offerId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _applyOffer(offerId));
        });
      }
      return _outlinedControl(
        Container(
          key: kLimousineExternalOfferKey,
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.accent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(kLimousineQuoteOffer),
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                labels.first,
                key: kLimousineExternalOfferLabelKey,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _outlinedControl(
      DropdownButtonFormField<String>(
        key: kLimousineExternalOfferKey,
        isExpanded: true,
        value:
            offers.any(
              (offer) => (offer['offer_id'] ?? '').toString() == _offerId,
            )
            ? _offerId
            : null,
        decoration: _decoration(palette, kLimousineQuoteOffer),
        items: [
          for (var i = 0; i < offers.length; i++)
            DropdownMenuItem(
              value: (offers[i]['offer_id'] ?? '').toString(),
              child: Text(labels[i], overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) => setState(() => _applyOffer(value ?? '')),
      ),
    );
  }

  Widget _addressField(
    BusinessThemePalette palette, {
    required LimousineAddressFieldController controller,
    required LocalizedText label,
    required Key inputKey,
    bool showCurrentLocation = false,
  }) {
    return _outlinedControl(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LimousineAddressField(
            controller: controller,
            label: _t(label),
            tokens: LimousineUxTokens.fromBusiness(palette),
            language: _lang,
            showCurrentLocation: showCurrentLocation,
            inputKey: inputKey,
            decoration: _decoration(palette, label),
          ),
          if (controller.value.acceptance ==
              LimousineAddressAcceptance.manualFallback)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _t(kLimousineOwnCustomerAddressUnverified),
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stopRow(BusinessThemePalette palette, int index) {
    final field = _stopFields[index];
    return KeyedSubtree(
      key: ValueKey<String>('limousine_external_stop_row_${field.fieldId}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _addressField(
              palette,
              controller: field,
              label: LocalizedText(
                nl: '${kLimousineQuoteStops.nl} ${index + 1}',
                en: '${kLimousineQuoteStops.en} ${index + 1}',
                fr: '${kLimousineQuoteStops.fr} ${index + 1}',
                es: '${kLimousineQuoteStops.es} ${index + 1}',
              ),
              inputKey: ValueKey<String>('limousine_external_stop_$index'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Column(
              children: [
                IconButton(
                  key: limousineExternalStopMoveUpKey(index),
                  tooltip: _t(kLimousineOwnCustomerMoveStopUp),
                  onPressed: index == 0
                      ? null
                      : () => setState(() => _moveStop(index, -1)),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  key: limousineExternalStopMoveDownKey(index),
                  tooltip: _t(kLimousineOwnCustomerMoveStopDown),
                  onPressed: index == _stopFields.length - 1
                      ? null
                      : () => setState(() => _moveStop(index, 1)),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  key: limousineExternalStopRemoveKey(index),
                  tooltip: _t(kLimousineRemoveStop),
                  onPressed: () => setState(() => _removeStop(index)),
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: palette.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BusinessThemePalette palette, String title, {Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(top: _sectionGap),
      child: KeyedSubtree(
        key: key,
        child: Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _outlinedControl(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: _outlinedGap),
      child: child,
    );
  }

  Widget _plainControl(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: _plainGap),
      child: child,
    );
  }

  InputDecoration _decoration(
    BusinessThemePalette palette,
    LocalizedText label,
  ) {
    return InputDecoration(
      label: Text(
        _t(label),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.textMuted),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.accent),
      ),
    );
  }

  Widget _field(
    BusinessThemePalette palette,
    TextEditingController controller,
    LocalizedText label,
    Key key, {
    TextInputType? keyboard,
  }) {
    return _outlinedControl(
      TextField(
        key: key,
        controller: controller,
        keyboardType: keyboard,
        style: TextStyle(color: palette.textPrimary),
        decoration: _decoration(palette, label),
      ),
    );
  }
}

class LimousineOwnCustomerOriginBadge extends StatelessWidget {
  const LimousineOwnCustomerOriginBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lang = appLanguageNotifier.value;
    final palette = paletteForBusinessTheme(businessThemeNotifier.value);
    return Container(
      key: kLimousineExternalOriginBadgeKey,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        kLimousineOwnCustomerOrigin.of(lang),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10 : 12,
        ),
      ),
    );
  }
}

class LimousineExternalContactSummaryCard extends StatelessWidget {
  const LimousineExternalContactSummaryCard({super.key, required this.contact});

  final LimousineExternalContactSummary contact;

  @override
  Widget build(BuildContext context) {
    final lang = appLanguageNotifier.value;
    final bits = <String>[
      contact.displayName,
      if (contact.companyLabel.isNotEmpty) contact.companyLabel,
      if (contact.mail.isNotEmpty) contact.mail,
      if (contact.mobile.isNotEmpty) contact.mobile,
    ].where((item) => item.isNotEmpty);
    return Container(
      key: kLimousineExternalContactSummaryKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kLimousineExternalContactSection.of(lang)),
          const SizedBox(height: 6),
          Text(bits.join(' · ')),
        ],
      ),
    );
  }
}

class LimousineExternalDeliveryTimeline extends StatelessWidget {
  const LimousineExternalDeliveryTimeline({super.key, required this.delivery});

  final LimousineExternalDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final lang = appLanguageNotifier.value;
    final current = LimousineExternalDeliveryState.normalize(
      delivery.invitationState,
    );
    final reached = current.isEmpty
        ? 0
        : LimousineExternalDeliveryState.timeline.indexOf(current) + 1;
    return Container(
      key: kLimousineExternalTimelineKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kLimousineExternalTimelineTitle.of(lang)),
          const SizedBox(height: 8),
          for (
            var i = 0;
            i < LimousineExternalDeliveryState.timeline.length;
            i++
          )
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${i < reached ? '●' : '○'} ${limousineExternalDeliveryLabel(LimousineExternalDeliveryState.timeline[i], lang)}',
              ),
            ),
        ],
      ),
    );
  }
}
