import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import '../company/company_fleet_operational.dart';
import 'limousine_business_setup.dart';
import 'limousine_external_quote.dart';
import 'limousine_external_quote_labels.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_api.dart';
import 'limousine_quote_inbox_labels.dart';
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
  });

  final LimousineExternalQuoteGateway gateway;
  final List<Map<String, dynamic>> offers;
  final List<VehicleProfile> vehicles;
  final Future<void> Function(String url)? share;
  final Future<void> Function(String url)? copy;
  final LimousineCompanyQuoteDraft? quoteDraft;

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
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _stops = TextEditingController();
  final _pax = TextEditingController(text: '2');
  final _bags = TextEditingController(text: '0');
  final _occasion = TextEditingController();
  String _locale = 'nl';
  bool _roundtrip = false;
  DateTime _when = DateTime.now().add(const Duration(days: 3));
  String _offerId = '';
  String _vehicleId = '';
  bool _submitting = false;
  String? _error;
  LimousineExternalQuoteCreateResult? _created;
  List<Map<String, dynamic>> _offers = const <Map<String, dynamic>>[];

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

  @override
  void initState() {
    super.initState();
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
    _from.dispose();
    _to.dispose();
    _stops.dispose();
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
    final quoteOffers = _offers.where(limousineQuoteOnRequestIsEnabled).toList();
    if (quoteOffers.isNotEmpty) {
      _offerId = (quoteOffers.first['offer_id'] ?? '').toString();
      _vehicleId = (quoteOffers.first['vehicle_id'] ?? '').toString();
    }
    final limos = limousineSetupLimousineVehicles(
      widget.vehicles.isNotEmpty
          ? widget.vehicles
          : companyOperationalVehicles(),
    );
    if (_vehicleId.isEmpty && limos.isNotEmpty) {
      _vehicleId = limos.first.id;
    }
  }

  LimousineExternalContactSummary _contact() {
    return LimousineExternalContactSummary(
      displayName: _name.text.trim(),
      mail: _email.text.trim(),
      mobile: _mobile.text.trim(),
      locale: _locale,
      companyLabel: _company.text.trim(),
    );
  }

  LimousineExternalJourneyDraft _journey() {
    return LimousineExternalJourneyDraft(
      offerId: _offerId,
      vehicleId: _vehicleId,
      from: _from.text.trim(),
      to: _to.text.trim(),
      stops: _stops.text
          .split(RegExp(r'[\n,]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      scheduledPickupIso: _when.toUtc().toIso8601String(),
      roundtrip: _roundtrip,
      pax: int.tryParse(_pax.text.trim()),
      bags: int.tryParse(_bags.text.trim()),
      occasion: _occasion.text.trim(),
      locale: _locale,
    );
  }

  bool _contactValid() {
    final contact = _contact();
    return contact.displayName.isNotEmpty &&
        (contact.mail.isNotEmpty || contact.mobile.isNotEmpty);
  }

  Future<void> _continueToQuote() async {
    if (!_contactValid() ||
        _from.text.trim().isEmpty ||
        _to.text.trim().isEmpty ||
        _offerId.isEmpty) {
      setState(() => _error = _t(kLimousineExternalContactRequired));
      return;
    }
    final provided = widget.quoteDraft;
    if (provided != null) {
      await _submit(provided);
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
    await _submit(draft);
  }

  Future<void> _submit(LimousineCompanyQuoteDraft draft) async {
    if (_submitting) return;
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
      setState(() => _created = created);
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
    setState(() => _created = LimousineExternalQuoteCreateResult(
      record: result.record,
      invitationUrl: url,
      contact: created.contact,
    ));
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
    setState(() => _created = LimousineExternalQuoteCreateResult(
      record: result.record,
      invitationUrl: url,
      contact: created.contact,
    ));
  }

  @override
  Widget build(BuildContext context) {
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
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                _t(kLimousineExternalQuoteCreateSubtitle),
                style: TextStyle(color: palette.textSecondary, height: 1.35),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: palette.danger)),
              ],
              if (_created != null) ...[
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
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  _t(kLimousineExternalContactSection),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _field(palette, _name, kLimousineExternalContactName, kLimousineExternalContactNameKey),
                _field(palette, _email, kLimousineExternalContactEmail, kLimousineExternalContactEmailKey),
                _field(palette, _mobile, kLimousineExternalContactMobile, kLimousineExternalContactMobileKey),
                _field(palette, _company, kLimousineExternalContactCompany, kLimousineExternalContactCompanyKey),
                DropdownButtonFormField<String>(
                  key: kLimousineExternalContactLocaleKey,
                  value: _locale,
                  decoration: InputDecoration(labelText: _t(kLimousineExternalContactLocale)),
                  items: const [
                    DropdownMenuItem(value: 'nl', child: Text('NL')),
                    DropdownMenuItem(value: 'en', child: Text('EN')),
                    DropdownMenuItem(value: 'fr', child: Text('FR')),
                    DropdownMenuItem(value: 'es', child: Text('ES')),
                  ],
                  onChanged: (value) => setState(() => _locale = value ?? 'nl'),
                ),
                const SizedBox(height: 16),
                Text(
                  _t(kLimousineQuoteJourneyCard),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _field(palette, _from, kLimousineQuotePickup, kLimousineExternalPickupKey),
                _field(palette, _to, kLimousineQuoteDestination, kLimousineExternalDestinationKey),
                FilledButton(
                  key: kLimousineExternalSubmitKey,
                  onPressed: _submitting ? null : _continueToQuote,
                  child: Text(_t(kLimousineQuoteEditorTitle)),
                ),
                _field(palette, _stops, kLimousineQuoteStops, kLimousineExternalStopsKey),
                ListTile(
                  key: kLimousineExternalWhenKey,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t(kLimousineQuoteWhen)),
                  subtitle: Text(_when.toLocal().toString()),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _when,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_when),
                    );
                    if (!mounted) return;
                    setState(() {
                      _when = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? _when.hour,
                        time?.minute ?? _when.minute,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  key: kLimousineExternalReturnKey,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t(kLimousineQuoteJourneyCard)),
                  value: _roundtrip,
                  onChanged: (value) => setState(() => _roundtrip = value),
                ),
                _field(palette, _pax, kLimousineQuotePassengers, kLimousineExternalPaxKey),
                _field(palette, _bags, kLimousineQuoteLuggage, kLimousineExternalBagsKey),
                _field(palette, _occasion, kLimousineQuoteImportantInfo, kLimousineExternalOccasionKey),
                if (_quoteOffers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: kLimousineExternalOfferKey,
                    value: _quoteOffers.any((offer) => (offer['offer_id'] ?? '').toString() == _offerId)
                        ? _offerId
                        : null,
                    decoration: InputDecoration(labelText: _t(kLimousineQuoteOffer)),
                    items: [
                      for (final offer in _quoteOffers)
                        DropdownMenuItem(
                          value: (offer['offer_id'] ?? '').toString(),
                          child: Text((offer['offer_id'] ?? '').toString()),
                        ),
                    ],
                    onChanged: (value) => setState(() => _offerId = value ?? ''),
                  ),
                if (_limousineVehicles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: kLimousineExternalVehicleKey,
                    value: _limousineVehicles.any((vehicle) => vehicle.id == _vehicleId)
                        ? _vehicleId
                        : null,
                    decoration: InputDecoration(labelText: _t(kLimousineQuoteVehicle)),
                    items: [
                      for (final vehicle in _limousineVehicles)
                        DropdownMenuItem(
                          value: vehicle.id,
                          child: Text(vehicle.vehicleName.isEmpty ? vehicle.id : vehicle.vehicleName),
                        ),
                    ],
                    onChanged: (value) => setState(() => _vehicleId = value ?? ''),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    BusinessThemePalette palette,
    TextEditingController controller,
    LocalizedText label,
    Key key,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        key: key,
        controller: controller,
        decoration: InputDecoration(labelText: _t(label)),
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
  const LimousineExternalDeliveryTimeline({
    super.key,
    required this.delivery,
  });

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
          for (var i = 0; i < LimousineExternalDeliveryState.timeline.length; i++)
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
