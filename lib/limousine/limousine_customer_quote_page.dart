import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_accepted_booking_page.dart';
import 'limousine_accepted_booking_resume_ui.dart';
import 'limousine_accepted_booking_vault.dart';
import 'limousine_address_field.dart';
import 'limousine_address_lookup.dart';
import 'limousine_current_location.dart';
import 'limousine_customer_entry.dart';
import 'limousine_customer_quote.dart';
import 'limousine_marketplace_labels.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_customer_status_page.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

class LimousineCustomerQuotePage extends StatefulWidget {
  const LimousineCustomerQuotePage({
    super.key,
    this.controller,
    this.gateway,
    this.entryEnabled,
    this.initialPublicPartnerId,
    this.initialOffer,
    this.initialCompanyName = '',
    this.resumeRepository,
    this.placeLookup,
    this.currentLocationPlatform,
  });

  final LimousineCustomerQuoteController? controller;
  final LimousineCustomerQuoteGateway? gateway;
  final LimousineAcceptedBookingResumeRepository? resumeRepository;
  final LimousinePlaceLookup? placeLookup;
  final LimousineCurrentLocationPlatform? currentLocationPlatform;
  final bool? entryEnabled;
  final String? initialPublicPartnerId;
  final LimousinePublishedOffer? initialOffer;
  final String initialCompanyName;

  @override
  State<LimousineCustomerQuotePage> createState() =>
      _LimousineCustomerQuotePageState();
}

class _LimousineCustomerQuotePageState extends State<LimousineCustomerQuotePage>
    with WidgetsBindingObserver {
  late final LimousineCustomerQuoteController _controller;
  late final bool _ownsController;
  late final LimousinePlaceLookup _placeLookup;
  late final bool _ownsPlaceLookup;
  late final LimousineAddressFieldController _pickup;
  late final LimousineAddressFieldController _destination;
  late final LimousineAddressFieldController _returnPickup;
  late final LimousineAddressFieldController _returnDestination;
  final _postcode = TextEditingController();
  final _note = TextEditingController();
  final _duration = TextEditingController();
  final List<LimousineAddressFieldController> _stops =
      <LimousineAddressFieldController>[];

  bool get _entryEnabled =>
      widget.entryEnabled ?? LimousineCustomerEntryContract.isVisible;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final existing = widget.controller;
    _ownsController = existing == null;
    _controller =
        existing ??
        LimousineCustomerQuoteController(
          gateway: widget.gateway ?? HttpLimousineCustomerQuoteGateway(),
          resumeRepository: widget.resumeRepository,
        );
    _controller.addListener(_onChanged);
    _ownsPlaceLookup = widget.placeLookup == null;
    _placeLookup = widget.placeLookup ?? LimousinePlaceLookup();
    _pickup = _createAddressField('pickup', listen: false);
    _pickup.currentLocation = LimousineCurrentLocationResolver(
      lookup: _placeLookup,
      platform:
          widget.currentLocationPlatform ??
          const LimousineCurrentLocationPlatform(),
    );
    _destination = _createAddressField('destination', listen: false);
    _returnPickup = _createAddressField('return_pickup', listen: false);
    _returnDestination = _createAddressField('return_destination', listen: false);
    if (widget.resumeRepository != null) {
      unawaited(_controller.detectSecureResume());
    }
    final initialOffer = widget.initialOffer;
    final initialPartner = (widget.initialPublicPartnerId ?? '').trim();
    if (initialOffer != null && initialPartner.isNotEmpty) {
      _controller.applyShowroomSelection(
        publicPartnerId: initialPartner,
        offer: initialOffer,
        companyName: widget.initialCompanyName,
      );
    }
    _pickup.seedText(_controller.draft.from);
    _destination.seedText(_controller.draft.to);
    for (var i = 0; i < _controller.draft.stops.length; i++) {
      _addStop(initialText: _controller.draft.stops[i], listen: false);
    }
    _note.text = _controller.draft.customerNote;
    _pickup.addListener(_onAddressChanged);
    _destination.addListener(_onAddressChanged);
    _returnPickup.addListener(_onAddressChanged);
    _returnDestination.addListener(_onAddressChanged);
    for (final stop in _stops) {
      stop.addListener(_onAddressChanged);
    }
  }

  LimousineAddressFieldController _createAddressField(
    String id, {
    bool listen = true,
  }) {
    final field = LimousineAddressFieldController(
      lookup: _placeLookup,
      fieldId: id,
      language: _lang.name,
    );
    if (listen) field.addListener(_onAddressChanged);
    return field;
  }

  void _addStop({String initialText = '', bool listen = true}) {
    if (_stops.length >= 8) return;
    final field = _createAddressField(
      'stop_${_stops.length}',
      listen: listen,
    );
    if (initialText.isNotEmpty) field.seedText(initialText);
    _stops.add(field);
  }

  void _onAddressChanged() {
    _pickup.language = _lang.name;
    _destination.language = _lang.name;
    _returnPickup.language = _lang.name;
    _returnDestination.language = _lang.name;
    for (final stop in _stops) {
      stop.language = _lang.name;
    }
    _controller.updateDraft(_syncedDraft());
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resumePolling();
    } else {
      _controller.pausePolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.stopPolling();
    if (_ownsController) _controller.dispose();
    _postcode.dispose();
    _pickup.dispose();
    _destination.dispose();
    _returnPickup.dispose();
    _returnDestination.dispose();
    _note.dispose();
    _duration.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    if (_ownsPlaceLookup) _placeLookup.dispose();
    super.dispose();
  }

  CustomerThemePalette get _palette =>
      paletteForCustomerTheme(customerThemeNotifier.value);

  LimousineUxTokens get _tokens => LimousineUxTokens.fromCustomer(_palette);

  bool get _tablet =>
      limousineQuoteInboxIsTablet(MediaQuery.sizeOf(context).shortestSide);

  LimousineRequestWizardStep get _wizardStep =>
      limousineRequestWizardStepOf(_controller.step);

  List<LimousineRequestStepGap> get _gaps => limousineRequestWizardGaps(
    step: _wizardStep,
    draft: _syncedDraft(),
    offer: _controller.selectedOffer,
    hasProvider: _controller.selectedProvider != null,
    pickupAddress: _pickup.value,
    destinationAddress: _destination.value,
    stopAddresses: _stops.map((stop) => stop.value).toList(growable: false),
    returnPickupAddress: _returnPickup.value,
    returnDestinationAddress: _returnDestination.value,
  );

  bool get _canAdvance => _gaps.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_entryEnabled && widget.controller == null && widget.gateway == null) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = _tokens;
    return Theme(
      data: limousineUxThemeData(tokens),
      child: Scaffold(
        key: kLimousineCustomerQuotePageKey,
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.surface,
          foregroundColor: tokens.onSurface,
          title: Text(_t(kLimousineCustomerPageTitle)),
        ),
        body: SafeArea(
          child: KeyedSubtree(
            key: _tablet
                ? kLimousineCustomerTabletLayoutKey
                : kLimousineCustomerPhoneLayoutKey,
            child: _pageBody(reduceMotion, tokens),
          ),
        ),
      ),
    );
  }

  Widget _pageBody(bool reduceMotion, LimousineUxTokens tokens) {
    final width = MediaQuery.sizeOf(context).width;
    final columnWidth = limousineRequestWizardContentWidth(width);
    final draftMode =
        _controller.phase != LimousineCustomerQuotePhase.unavailable &&
        _controller.request == null &&
        !(_controller.restoredFromSecureResume && _controller.handoff != null);
    return Column(
      key: kLimousineRequestWizardKey,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: columnWidth,
              child: Column(
                children: [
                  _hero(reduceMotion, tokens),
                  const SizedBox(height: 12),
                  if (draftMode) _stepper(tokens),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: columnWidth,
              child: ListView(
                key: kLimousineRequestWizardScrollKey,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_controller.restoredFromSecureResume &&
                      _controller.handoff != null) ...[
                    LimousineAcceptedBookingContinueAction(
                      language: _lang,
                      onContinue: () => openLimousineAcceptedBookingReview(
                        context,
                        quoteController: _controller,
                        entryEnabled: _entryEnabled,
                      ),
                      onDiscard: () =>
                          unawaited(_controller.discardSecureResume()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_controller.phase ==
                          LimousineCustomerQuotePhase.unavailable ||
                      _controller.safeError == 'unavailable')
                    LimousineCustomerUnavailableBanner(language: _lang)
                  else if (_controller.request != null)
                    LimousineCustomerStatusView(
                      controller: _controller,
                      language: _lang,
                      palette: _palette,
                    )
                  else if (!(_controller.restoredFromSecureResume &&
                      _controller.handoff != null))
                    _stepCard(tokens),
                ],
              ),
            ),
          ),
        ),
        if (draftMode) _footer(tokens),
      ],
    );
  }

  Widget _hero(bool reduceMotion, LimousineUxTokens tokens) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: _tablet ? 168 : 128,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              LimousineCustomerEntryContract.visualAsset,
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: tokens.surfaceAlt),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    tokens.heroScrim.withOpacity(reduceMotion ? 0.55 : 0.28),
                    tokens.heroScrim,
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _t(kLimousineBookLabel),
                  style: TextStyle(
                    color: tokens.onHero,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    shadows: [Shadow(color: tokens.heroScrim, blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper(LimousineUxTokens tokens) {
    final current = _wizardStep;
    return SingleChildScrollView(
      key: kLimousineRequestWizardStepperKey,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < kLimousineRequestWizardSteps.length; i++) ...[
            if (i > 0)
              Container(
                width: 18,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: tokens.border,
              ),
            _stepChip(kLimousineRequestWizardSteps[i], i + 1, current, tokens),
          ],
        ],
      ),
    );
  }

  Widget _stepChip(
    LimousineRequestWizardStep step,
    int number,
    LimousineRequestWizardStep current,
    LimousineUxTokens tokens,
  ) {
    final selected = step == current;
    final past =
        kLimousineRequestWizardSteps.indexOf(step) <
        kLimousineRequestWizardSteps.indexOf(current);
    return Material(
      key: limousineRequestWizardStepKey(step),
      color: selected ? tokens.gold.withOpacity(0.22) : tokens.surfaceAlt,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: past
            ? () => _controller.goTo(limousineCustomerQuoteStepOf(step))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            '$number  ${limousineRequestWizardStepLabel(step).of(_lang)}',
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepCard(LimousineUxTokens tokens) {
    return Card(
      key: kLimousineRequestWizardColumnKey,
      color: tokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _draftSteps(),
        ),
      ),
    );
  }

  List<Widget> _draftSteps() {
    switch (_wizardStep) {
      case LimousineRequestWizardStep.journey:
        return _journeyStep();
      case LimousineRequestWizardStep.provider:
        return _providerStep();
      case LimousineRequestWizardStep.details:
        return _detailsStep();
      case LimousineRequestWizardStep.review:
        return _reviewStep();
    }
  }

  List<Widget> _journeyStep() {
    return [
      LimousineAddressField(
        controller: _pickup,
        label: _t(kLimousineCustomerFrom),
        tokens: _tokens,
        language: _lang,
        showCurrentLocation: true,
      ),
      LimousineAddressField(
        controller: _destination,
        label: _t(kLimousineCustomerTo),
        tokens: _tokens,
        language: _lang,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in const [
            'point_to_point',
            'airport_transfer',
            'hotel_transfer',
            'event_transfer',
            'hourly_package',
          ])
            ChoiceChip(
              label: Text(
                (kLimousineJourneyTypeLabels[type] ??
                        kLimousineCustomerStepJourney)
                    .of(_lang),
                style: TextStyle(color: _tokens.onSurface),
              ),
              selected: _controller.draft.journeyType == type,
              onSelected: (_) {
                _controller.updateDraft(
                  _controller.draft.copyWith(journeyType: type),
                );
              },
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_t(kLimousineCustomerRoundtrip)),
        value: _controller.draft.roundtrip,
        onChanged: (value) {
          _controller.updateDraft(_controller.draft.copyWith(roundtrip: value));
          if (value) {
            if (_destination.isRouteReady) {
              _returnPickup.acceptCopy(_destination.value);
            }
            if (_pickup.isRouteReady) {
              _returnDestination.acceptCopy(_pickup.value);
            }
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_t(kLimousineCustomerPickupTime)),
        subtitle: Text(
          _controller.draft.scheduledPickupIso.isEmpty
              ? _t(kLimousineRequestIncompleteHint)
              : _controller.draft.scheduledPickupIso,
          style: TextStyle(color: _tokens.muted),
        ),
        onTap: () => _pickSchedule(returnTrip: false),
      ),
      if (_controller.draft.roundtrip) ...[
        LimousineAddressField(
          controller: _returnPickup,
          label: _t(kLimousineCustomerReturnPickupAddress),
          tokens: _tokens,
          language: _lang,
        ),
        LimousineAddressField(
          controller: _returnDestination,
          label: _t(kLimousineCustomerReturnDestinationAddress),
          tokens: _tokens,
          language: _lang,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_t(kLimousineCustomerReturnTime)),
          subtitle: Text(
            _controller.draft.returnPickupIso.isEmpty
                ? _t(kLimousineRequestIncompleteHint)
                : _controller.draft.returnPickupIso,
            style: TextStyle(color: _tokens.muted),
          ),
          onTap: () => _pickSchedule(returnTrip: true),
        ),
      ],
      if (_controller.draft.journeyType == 'hourly_package')
        _field(
          _t(kLimousineCustomerDuration),
          _duration,
          onChanged: (value) {
            _controller.updateDraft(
              _controller.draft.copyWith(
                requestedDurationMinutes: int.tryParse(value.trim()),
              ),
            );
          },
        ),
      ..._stopFields(),
    ];
  }

  List<Widget> _stopFields() {
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: kLimousineRequestAddStopKey,
          onPressed: _stops.length >= 8
              ? null
              : () {
                  setState(_addStop);
                },
          icon: const Icon(Icons.add),
          label: Text(_t(kLimousineCustomerAddStop)),
        ),
      ),
      for (var i = 0; i < _stops.length; i++)
        LimousineAddressField(
          controller: _stops[i],
          label: '${_t(kLimousineCustomerStops)} ${i + 1}',
          tokens: _tokens,
          language: _lang,
        ),
    ];
  }

  List<Widget> _providerStep() {
    final locked = _controller.providerOfferLocked;
    return [
      if (!locked) ...[
        _field(_t(kLimousineCustomerSearchHint), _postcode),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed:
                _controller.discovering ||
                    !limousineRequestWizardAllowsHttp(
                      step: LimousineRequestWizardStep.provider,
                      draft: _syncedDraft(),
                      offer: _controller.selectedOffer,
                      hasProvider: _controller.selectedProvider != null,
                      action: 'discover',
                      pickupAddress: _pickup.value,
                      destinationAddress: _destination.value,
                      stopAddresses: _stops
                          .map((stop) => stop.value)
                          .toList(growable: false),
                      returnPickupAddress: _returnPickup.value,
                      returnDestinationAddress: _returnDestination.value,
                    )
                ? null
                : () => _controller.discover(postcode: _postcode.text),
            child: Text(_t(kLimousineCustomerSearchAction)),
          ),
        ),
      ],
      if (_controller.discovering) const LinearProgressIndicator(),
      if (!_controller.discovering &&
          _controller.lastDiscoveryCount == 0 &&
          _controller.lastDiscoveryService == 'limousine')
        Padding(
          key: kLimousineCustomerDiscoverEmptyKey,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_t(kLimousineCustomerEmptyDiscovery)),
        ),
      for (final provider in _controller.providers)
        ListTile(
          leading: Icon(
            Icons.directions_car_filled_outlined,
            color: _tokens.onSurface,
          ),
          title: Text(provider.companyName),
          subtitle: Text(provider.serviceArea.take(3).join(' · ')),
          selected:
              _controller.selectedProvider?.provider.partnerId ==
              provider.partnerId,
          onTap: locked ? null : () => _controller.selectProvider(provider),
        ),
      if (_controller.selectedProvider != null) ...[
        const SizedBox(height: 8),
        for (final offer in _controller.selectedProvider!.offers)
          RadioListTile<String>(
            value: offer.offerId,
            groupValue: _controller.selectedOffer?.offerId,
            title: Text(
              localizedLimousineText(offer.title, languageCode: _lang.name),
            ),
            subtitle: Text(
              limousineCustomerPresentationLabel(
                offer.pricePresentation,
                _lang,
              ),
            ),
            onChanged: locked ? null : (_) => _controller.selectOffer(offer),
          ),
      ],
    ];
  }

  List<Widget> _detailsStep() {
    return [
      _stepperField(_t(kLimousineCustomerPax), _controller.draft.pax ?? 1, (
        value,
      ) {
        _controller.updateDraft(_controller.draft.copyWith(pax: value));
      }),
      _stepperField(_t(kLimousineCustomerBags), _controller.draft.bags ?? 0, (
        value,
      ) {
        _controller.updateDraft(_controller.draft.copyWith(bags: value));
      }),
      if (_controller.selectedOffer != null)
        ..._controller.selectedOffer!.paidExtras.map((extra) {
          final id = (extra['extra_id'] ?? '').toString();
          final selected = _controller.draft.selectedExtraIds.contains(id);
          return CheckboxListTile(
            value: selected,
            title: Text(
              localizedLimousineText(
                extra['label'] is Map
                    ? Map<String, String>.from(
                        (extra['label'] as Map).map(
                          (key, value) => MapEntry(key.toString(), '$value'),
                        ),
                      )
                    : const <String, String>{},
                languageCode: _lang.name,
              ),
            ),
            onChanged: (value) {
              final next = List<String>.from(
                _controller.draft.selectedExtraIds,
              );
              if (value == true) {
                if (!next.contains(id)) next.add(id);
              } else {
                next.remove(id);
              }
              _controller.updateDraft(
                _controller.draft.copyWith(selectedExtraIds: next),
              );
            },
          );
        }),
      _field(
        _t(kLimousineCustomerNote),
        _note,
        maxLines: 3,
        onChanged: (value) {
          _controller.updateDraft(
            _controller.draft.copyWith(customerNote: value),
          );
        },
      ),
    ];
  }

  List<Widget> _reviewStep() {
    final rows = buildLimousineRequestReviewRows(
      draft: _syncedDraft(),
      language: _lang,
      providerName: _controller.selectedProvider?.provider.companyName ?? '',
      offer: _controller.selectedOffer,
      returnPickupAddress: _returnPickup.value.routeText,
      returnDestinationAddress: _returnDestination.value.routeText,
    );
    return [
      Column(
        key: kLimousineRequestReviewSummaryKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label,
                    style: TextStyle(
                      color: _tokens.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    row.value,
                    style: TextStyle(
                      color: _tokens.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  Widget _footer(LimousineUxTokens tokens) {
    final isReview = _wizardStep == LimousineRequestWizardStep.review;
    return Material(
      key: kLimousineRequestWizardFooterKey,
      color: tokens.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: limousineRequestWizardContentWidth(
                MediaQuery.sizeOf(context).width,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_canAdvance)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _t(kLimousineRequestIncompleteHint),
                        key: kLimousineRequestWizardHintKey,
                        style: TextStyle(color: tokens.muted, fontSize: 12.5),
                      ),
                    ),
                  Row(
                    children: [
                      if (_wizardStep != LimousineRequestWizardStep.journey)
                        TextButton(
                          key: kLimousineRequestWizardBackKey,
                          onPressed: _goBack,
                          child: Text(_t(kLimousineCustomerBack)),
                        ),
                      const Spacer(),
                      FilledButton(
                        key: isReview
                            ? kLimousineCustomerSubmitKey
                            : kLimousineRequestWizardNextKey,
                        onPressed: !_canAdvance || _controller.submitting
                            ? null
                            : () => unawaited(_goNext()),
                        child: Text(
                          isReview
                              ? _t(kLimousineCustomerSubmit)
                              : _t(kLimousineCustomerContinue),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBack() {
    switch (_wizardStep) {
      case LimousineRequestWizardStep.provider:
        _controller.goTo(LimousineCustomerQuoteStep.journey);
        break;
      case LimousineRequestWizardStep.details:
        _controller.goTo(LimousineCustomerQuoteStep.providerOffer);
        break;
      case LimousineRequestWizardStep.review:
        _controller.goTo(LimousineCustomerQuoteStep.detailsExtras);
        break;
      case LimousineRequestWizardStep.journey:
        break;
    }
  }

  Future<void> _goNext() async {
    _syncDraft();
    if (!_canAdvance) return;
    switch (_wizardStep) {
      case LimousineRequestWizardStep.journey:
        _controller.goTo(LimousineCustomerQuoteStep.providerOffer);
        break;
      case LimousineRequestWizardStep.provider:
        _controller.goTo(LimousineCustomerQuoteStep.detailsExtras);
        break;
      case LimousineRequestWizardStep.details:
        _controller.goTo(LimousineCustomerQuoteStep.reviewRequest);
        break;
      case LimousineRequestWizardStep.review:
        if (!limousineRequestWizardAllowsHttp(
          step: LimousineRequestWizardStep.review,
          draft: _syncedDraft(),
          offer: _controller.selectedOffer,
          hasProvider: _controller.selectedProvider != null,
          action: 'submit',
          pickupAddress: _pickup.value,
          destinationAddress: _destination.value,
          stopAddresses: _stops
              .map((stop) => stop.value)
              .toList(growable: false),
          returnPickupAddress: _returnPickup.value,
          returnDestinationAddress: _returnDestination.value,
        )) {
          return;
        }
        final locale = switch (_lang) {
          AppLanguage.fr => 'fr',
          AppLanguage.es => 'es',
          AppLanguage.en => 'en',
          _ => 'nl',
        };
        _controller.updateDraft(_controller.draft.copyWith(locale: locale));
        final ok = await _controller.submitRequest();
        if (ok) _controller.startPolling();
        break;
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(color: _tokens.onSurface),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintStyle: TextStyle(color: _tokens.muted),
          filled: true,
          fillColor: _tokens.fieldFill,
        ),
      ),
    );
  }

  Widget _stepperField(String label, int value, ValueChanged<int> onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value <= 0 ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value', style: TextStyle(color: _tokens.onSurface)),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  LimousineQuoteCreateDraft _syncedDraft() {
    final onJourney = _wizardStep == LimousineRequestWizardStep.journey;
    return _controller.draft.copyWith(
      from: _pickup.isRouteReady
          ? _pickup.value.routeText
          : (onJourney ? '' : _controller.draft.from),
      to: _destination.isRouteReady
          ? _destination.value.routeText
          : (onJourney ? '' : _controller.draft.to),
      customerNote: _note.text,
      stops: _stops
          .map((controller) => controller.value.routeText)
          .where((text) => text.isNotEmpty)
          .toList(growable: false),
    );
  }

  void _syncDraft() {
    _controller.updateDraft(_syncedDraft());
  }

  Future<void> _pickSchedule({required bool returnTrip}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );
    if (time == null) return;
    final iso = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc().toIso8601String();
    _controller.updateDraft(
      returnTrip
          ? _controller.draft.copyWith(returnPickupIso: iso)
          : _controller.draft.copyWith(scheduledPickupIso: iso),
    );
  }
}

void openLimousineCustomerQuoteFlow(
  BuildContext context, {
  String? publicPartnerId,
  LimousinePublishedOffer? offer,
  String companyName = '',
  bool? entryEnabled,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LimousineCustomerQuotePage(
        entryEnabled: entryEnabled,
        initialPublicPartnerId: publicPartnerId,
        initialOffer: offer,
        initialCompanyName: companyName,
        resumeRepository: LimousineAcceptedBookingResumeRepository(),
      ),
    ),
  );
}
