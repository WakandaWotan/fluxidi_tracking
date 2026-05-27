part of '../main.dart';

class _BusinessHomePageState extends State<BusinessHomePage>
    with WidgetsBindingObserver, RouteAware {
  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  int? _openBookingsCount;
  int? _completedRidesCount;
  int? _unpaidCompletedRidesCount;
  int? _monthlyIncomeCents;
  String _kpiCurrency = 'EUR';
  bool _kpiRefreshInFlight = false;
  bool _routeObserverSubscribed = false;
  bool _businessAccessGuardTriggered = false;

  void _guardBusinessAccessOrRedirect({required String reason}) {
    if (_businessAccessGuardTriggered || !mounted) return;
    if (CompanySessionStore.instance.hasValidCompanyContext) return;
    _businessAccessGuardTriggered = true;
    debugPrint('[COMPANY_PAIRING][BUSINESS_GUARD_REDIRECT] reason=$reason');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Bedrijfstoegang vereist eerst activatie of herstel.',
            en: 'Business access requires activation or recovery first.',
            fr: "L'accès entreprise nécessite d'abord une activation ou récupération.",
            es: 'El acceso de empresa requiere primero activación o recuperación.',
          ),
        ),
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const RoleEntryPage()),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardBusinessAccessOrRedirect(reason: 'business_home_init');
    });
    unawaited(_refreshDashboardKpis(reason: 'init'));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      kAppRouteObserver.subscribe(this, route);
      _routeObserverSubscribed = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserverSubscribed) {
      kAppRouteObserver.unsubscribe(this);
      _routeObserverSubscribed = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _guardBusinessAccessOrRedirect(reason: 'business_home_resume');
      unawaited(_refreshDashboardKpis(reason: 'app_resume'));
    }
  }

  @override
  void didPopNext() {
    _guardBusinessAccessOrRedirect(reason: 'business_home_route_return');
    unawaited(_refreshDashboardKpis(reason: 'route_return'));
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Map<String, String> _adminHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = kAdminToken.trim();
    if (token.isNotEmpty) {
      headers['x-admin-token'] = token;
    }
    return headers;
  }

  String _activeMonthToken() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    return '${now.year}-$mm';
  }

  String _metricCountText(int? value) {
    return value == null ? '—' : value.toString();
  }

  String _metricIncomeText() {
    if (_monthlyIncomeCents == null) return '—';
    final amount = _monthlyIncomeCents! / 100.0;
    final useComma = appConfig.currentLanguage != AppLanguage.en;
    final text = amount.toStringAsFixed(2);
    final normalized = useComma ? text.replaceAll('.', ',') : text;
    if (_kpiCurrency.trim().toUpperCase() == 'EUR') {
      return '€$normalized';
    }
    return '${_kpiCurrency.toUpperCase()} $normalized';
  }

  Future<int?> _loadOpenBookingsFallbackCount({
    required Map<String, String> headers,
    required String reason,
  }) async {
    // Keep fallback lightweight: company list index-backed endpoint only.
    final listUri = _withActiveBookingScope(
      kBookingBaseUrl,
      kListBookingsPath,
      extraQuery: <String, String>{
        'limit': '200',
        'include_history': '1',
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    try {
      final res = await http
          .get(listUri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list status=${res.statusCode} trigger=$reason',
        );
        return null;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list reason=invalid_payload trigger=$reason',
        );
        return null;
      }
      final rawItems = (decoded['items'] is List)
          ? (decoded['items'] as List)
          : ((decoded['bookings'] is List)
                ? (decoded['bookings'] as List)
                : null);
      if (rawItems == null) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list reason=missing_items trigger=$reason',
        );
        return null;
      }
      var openCount = 0;
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = _CompanyBookingOverviewItem.fromMap(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (item.bucket == _CompanyBookingsFilter.open) {
          openCount += 1;
        }
      }
      return openCount;
    } catch (e) {
      debugPrint(
        '[BUSINESS_DASHBOARD][KPI][FALLBACK][WARN] source=company_list reason=fetch_failed trigger=$reason error=$e',
      );
      return null;
    }
  }

  Future<void> _refreshDashboardKpis({required String reason}) async {
    if (_kpiRefreshInFlight) return;
    _kpiRefreshInFlight = true;
    try {
      final month = _activeMonthToken();
      final headers = _adminHeaders();
      final bookingsUri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/admin/dashboard/bookings-kpis',
      );
      final tripKpisUri = _withActiveBookingScope(
        kWorkerBaseUrl,
        '/admin/dashboard/trip-kpis',
        extraQuery: <String, String>{'month': month},
      );

      int? nextOpenBookings;
      int? nextCompletedRides;
      int? nextUnpaidCompleted;
      int? nextMonthlyIncomeCents;
      var nextCurrency = 'EUR';

      try {
        try {
          final bookingsRes = await http
              .get(bookingsUri, headers: headers)
              .timeout(const Duration(seconds: 12));
          if (bookingsRes.statusCode == 200) {
            final decoded = jsonDecode(bookingsRes.body);
            if (decoded is Map && decoded['ok'] == true) {
              nextOpenBookings = _asInt(decoded['open_bookings_count']);
            } else {
              debugPrint(
                '[BUSINESS_DASHBOARD][KPI][WARN] source=bookings reason=invalid_payload trigger=$reason',
              );
            }
          } else {
            debugPrint(
              '[BUSINESS_DASHBOARD][KPI][WARN] source=bookings status=${bookingsRes.statusCode} trigger=$reason',
            );
          }
        } catch (e) {
          debugPrint(
            '[BUSINESS_DASHBOARD][KPI][WARN] source=bookings reason=fetch_failed trigger=$reason error=$e',
          );
        }
        nextOpenBookings ??= await _loadOpenBookingsFallbackCount(
          headers: headers,
          reason: reason,
        );
        nextOpenBookings ??= 0;

        try {
          final tripRes = await http
              .get(tripKpisUri, headers: headers)
              .timeout(const Duration(seconds: 12));
          if (tripRes.statusCode == 200) {
            final decoded = jsonDecode(tripRes.body);
            if (decoded is Map && decoded['ok'] == true) {
              nextCompletedRides = _asInt(decoded['completed_rides_count']);
              nextUnpaidCompleted = _asInt(
                decoded['unpaid_completed_rides_count'],
              );
              nextCurrency =
                  (decoded['currency']?.toString().trim().isNotEmpty ?? false)
                  ? decoded['currency'].toString().trim().toUpperCase()
                  : 'EUR';
              final cents = _asInt(decoded['monthly_income_cents']);
              if (cents != null) {
                nextMonthlyIncomeCents = cents;
              } else {
                final eur = _asDouble(decoded['monthly_income_eur']);
                nextMonthlyIncomeCents = eur == null
                    ? null
                    : (eur * 100).round();
              }
            } else {
              debugPrint(
                '[BUSINESS_DASHBOARD][KPI][WARN] source=trip_kpis reason=invalid_payload trigger=$reason',
              );
            }
          } else {
            debugPrint(
              '[BUSINESS_DASHBOARD][KPI][WARN] source=trip_kpis status=${tripRes.statusCode} trigger=$reason',
            );
          }
        } catch (e) {
          debugPrint(
            '[BUSINESS_DASHBOARD][KPI][WARN] source=trip_kpis reason=fetch_failed trigger=$reason error=$e',
          );
        }
      } catch (e) {
        debugPrint(
          '[BUSINESS_DASHBOARD][KPI][WARN] reason=fetch_failed trigger=$reason error=$e',
        );
      }
      if (!mounted) return;
      setState(() {
        _openBookingsCount = nextOpenBookings;
        _completedRidesCount = nextCompletedRides;
        _unpaidCompletedRidesCount = nextUnpaidCompleted;
        _monthlyIncomeCents = nextMonthlyIncomeCents;
        _kpiCurrency = nextCurrency;
      });
    } finally {
      _kpiRefreshInFlight = false;
    }
  }

  Future<void> _openCalculator(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: false,
          entryContext: BookingEntryContext.companyAdmin,
        ),
      ),
    );
    if (created == true) {
      await _refreshDashboardKpis(reason: 'calculator_created');
    }
  }

  String _normalizeBridgeText(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeBridgePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  String _maskBridgeDriverId(String raw) {
    return _maskBridgeDriverIdGlobal(raw);
  }

  bool _isSeededOrPlaceholderDriver(DriverProfile driver) {
    return _isSeededOrPlaceholderBridgeDriver(driver);
  }

  ({DriverProfile? driver, String reason}) _resolveOwnerDriverBridgeMatch() {
    final profile = companyProfileNotifier.value;
    if (profile == null) {
      return (driver: null, reason: 'no_safe_match');
    }

    final activeCompanyId = profile.companyId.trim();
    if (activeCompanyId.isEmpty) {
      return (driver: null, reason: 'no_safe_match');
    }

    final strictCandidates = driversNotifier.value
        .where((driver) {
          if (!driver.isActive) return false;
          final scopedCompanyId = (driver.companyId ?? '').trim();
          if (scopedCompanyId.isEmpty || scopedCompanyId != activeCompanyId) {
            return false;
          }
          if (_isSeededOrPlaceholderDriver(driver)) return false;
          if (driver.id.trim().isEmpty) return false;
          if (driver.employeeNumber.trim().isEmpty) return false;
          return true;
        })
        .toList(growable: false);

    final ownerName = _normalizeBridgeText(profile.ownerName);
    final ownerPhone = _normalizeBridgePhone(profile.phone);
    final ownerEmailToken = _normalizeBridgeText(
      profile.email.trim().isNotEmpty ? profile.email : profile.companyEmail,
    );
    final ownerEmails = <String>{
      if (ownerEmailToken.isNotEmpty) ownerEmailToken,
    };

    final matches = strictCandidates
        .where((driver) {
          final driverName = _normalizeBridgeText(driver.fullName);
          final driverPhone = _normalizeBridgePhone(driver.phone);
          final phoneMatch =
              ownerPhone.isNotEmpty &&
              driverPhone.isNotEmpty &&
              ownerPhone == driverPhone;
          // DriverProfile currently has no persisted email field.
          const driverEmail = '';
          final emailMatch =
              ownerEmails.isNotEmpty &&
              driverEmail.isNotEmpty &&
              ownerEmails.contains(driverEmail);
          final nameMatch =
              ownerName.isNotEmpty &&
              driverName.isNotEmpty &&
              ownerName == driverName;
          return phoneMatch || emailMatch || nameMatch;
        })
        .toList(growable: false);

    if (matches.length > 1) {
      return (driver: null, reason: 'multiple_matches');
    }
    if (matches.length == 1) {
      return (driver: matches.first, reason: 'owner_match');
    }
    return (driver: null, reason: 'no_safe_match');
  }

  List<DriverProfile> _resolveSelectableDriverBridgeCandidates() {
    return _resolveSelectableDriverBridgeCandidatesGlobal(logCandidates: true);
  }

  Future<DriverProfile?> _showDriverOwnerBridgePicker(
    BuildContext context, {
    required List<DriverProfile> selectableDrivers,
  }) {
    return _showDriverOwnerBridgePickerSheet(
      context,
      selectableDrivers: selectableDrivers,
      tr: _tr,
    );
  }

  Future<void> _openDriverCockpitView(BuildContext context) async {
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    await DriverDocumentsStore.instance.load();
    if (!context.mounted) return;
    if (activeDriverSessionNotifier.value != null) {
      setAppRole(AppRole.driver);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const DriverHomePage(openedFromBusinessHome: true),
        ),
      );
      return;
    }
    if (!CompanySessionStore.instance.hasValidCompanyContext) {
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_company_context');
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()));
      return;
    }
    final ownerBridge = _resolveOwnerDriverBridgeMatch();
    final matchedDriver = ownerBridge.driver;
    if (matchedDriver != null) {
      await DriverSessionStore.instance.saveFromDriverProfile(
        matchedDriver,
        linkMethodOverride: kCompanyAdminDriverViewLinkMethod,
      );
      await DriverSessionStore.instance.bootstrap(driversNotifier.value);
      if (!context.mounted) return;
      if (activeDriverSessionNotifier.value != null) {
        debugPrint(
          '[DRIVER_OWNER_BRIDGE][OPEN] driver=${_maskBridgeDriverId(matchedDriver.id)} reason=owner_match',
        );
        setAppRole(AppRole.driver);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DriverHomePage(openedFromBusinessHome: true),
          ),
        );
        return;
      }
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_safe_match');
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()));
      return;
    }
    final selectableDrivers = _resolveSelectableDriverBridgeCandidates();
    if (selectableDrivers.isEmpty) {
      debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_selectable_driver');
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()));
      return;
    }
    DriverProfile? selectedDriver;
    if (selectableDrivers.length == 1) {
      selectedDriver = selectableDrivers.first;
    } else {
      debugPrint(
        '[DRIVER_OWNER_BRIDGE][PICKER_OPEN] count=${selectableDrivers.length}',
      );
      selectedDriver = await _showDriverOwnerBridgePicker(
        context,
        selectableDrivers: selectableDrivers,
      );
      if (!context.mounted) return;
    }
    if (selectedDriver == null) return;
    debugPrint(
      '[DRIVER_OWNER_BRIDGE][SELECTED] driver=${_maskBridgeDriverId(selectedDriver.id)}',
    );
    await DriverSessionStore.instance.saveFromDriverProfile(
      selectedDriver,
      linkMethodOverride: kCompanyAdminDriverViewLinkMethod,
    );
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    if (!context.mounted) return;
    if (activeDriverSessionNotifier.value != null) {
      setAppRole(AppRole.driver);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const DriverHomePage(openedFromBusinessHome: true),
        ),
      );
      return;
    }
    debugPrint('[DRIVER_OWNER_BRIDGE][SKIP] reason=no_safe_match');
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()));
  }

  Future<void> _openBusinessBookingsOverview(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CompanyBookingsOverviewPage(),
      ),
    );
  }

  ({Color bg, Color border, Color text}) _statusColors(CompanyProfile profile) {
    return (
      bg: profile.isSuspended
          ? const Color(0xFF3A1010)
          : profile.isVerified
          ? const Color(0xFF12331F)
          : const Color(0xFF2A2410),
      border: profile.isSuspended
          ? Colors.red.withOpacity(0.45)
          : profile.isVerified
          ? const Color(0xFF4ADE80).withOpacity(0.45)
          : kFluxidiYellow.withOpacity(0.55),
      text: profile.isSuspended
          ? const Color(0xFFFFB4B4)
          : profile.isVerified
          ? const Color(0xFFB8F5C8)
          : const Color(0xFFE5D4A1),
    );
  }

  Widget _statusPill(CompanyProfile profile, {bool compact = false}) {
    final colors = _statusColors(profile);
    final fontSize = compact ? 10.5 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        profile.verificationBadgeLabel(appConfig.currentLanguage),
        style: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _companyInitials(CompanyProfile? profile) {
    final name = profile?.companyName.trim() ?? '';
    if (name.isEmpty) return 'FB';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'FB';
    final first = parts.first.substring(0, 1).toUpperCase();
    final second = parts.length > 1
        ? parts[1].substring(0, 1).toUpperCase()
        : (parts.first.length > 1
              ? parts.first.substring(1, 2).toUpperCase()
              : 'B');
    return '$first$second';
  }

  Future<void> _openCompanyDetails(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CompanyProfileEditPage()),
    );
  }

  String _normalizePublicBookingCompanyCode(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  bool _isValidPublicBookingCompanyCode(String value) {
    final code = _normalizePublicBookingCompanyCode(value);
    if (code.isEmpty) return false;
    return RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(code);
  }

  bool _isGeneratedSequentialPublicCompanyCode(String value) {
    final code = _normalizePublicBookingCompanyCode(value);
    return RegExp(r'^FLX-[0-9]{5,12}$').hasMatch(code);
  }

  String? _resolvePublicBookingCompanyCodeForDashboard() {
    String? readFirstValidFromMap(Map<String, dynamic>? map) {
      if (map == null) return null;
      for (final key in const <String>[
        'public_company_code',
        'publicCompanyCode',
        'company_code',
        'companyCode',
      ]) {
        final normalized = _normalizePublicBookingCompanyCode(
          (map[key] ?? '').toString(),
        );
        if (_isValidPublicBookingCompanyCode(normalized)) return normalized;
      }
      return null;
    }

    final backendMap = localBackendBusinessProfileNotifier.value?.toJson();
    final profileMap = companyProfileNotifier.value?.toJson();
    final sessionCode = _normalizePublicBookingCompanyCode(
      activeCompanySessionNotifier.value?.companyCode ?? '',
    );

    final candidates = <String>[];
    if (backendMap is Map<String, dynamic>) {
      final backendCode = readFirstValidFromMap(backendMap);
      if (backendCode != null) candidates.add(backendCode);
    }
    if (profileMap is Map<String, dynamic>) {
      final profileCode = readFirstValidFromMap(profileMap);
      if (profileCode != null) candidates.add(profileCode);
    }
    if (_isValidPublicBookingCompanyCode(sessionCode)) {
      candidates.add(sessionCode);
    }

    for (final code in candidates) {
      if (_isGeneratedSequentialPublicCompanyCode(code)) return code;
    }
    return candidates.isNotEmpty ? candidates.first : null;
  }

  String _preparedPublicBookingUrlForDashboard(String companyCode) {
    final safeCompanyCode = _normalizePublicBookingCompanyCode(companyCode);
    final base = kPublicBookingBaseUrl.trim().isEmpty
        ? 'https://fluxidi.com'
        : kPublicBookingBaseUrl.trim();
    final encodedCompanyCode = Uri.encodeQueryComponent(safeCompanyCode);
    try {
      final uri = Uri.parse(base);
      final normalizedPath = uri.path.trim().isEmpty || uri.path == '/'
          ? '/book'
          : (uri.path.endsWith('/book') ? uri.path : '${uri.path}/book');
      final nextQuery = Map<String, String>.from(uri.queryParameters);
      nextQuery['company_code'] = safeCompanyCode;
      return uri
          .replace(path: normalizedPath, queryParameters: nextQuery)
          .toString();
    } catch (_) {
      return '$base/book?company_code=$encodedCompanyCode';
    }
  }

  Future<void> _sharePublicBookingQrCardImage({
    required BuildContext context,
    required GlobalKey repaintBoundaryKey,
    required String publicCompanyCode,
    required String publicBookingUrl,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final shareMessage = _t(
      nl: 'Boek je rit eenvoudig via deze QR-code of link.',
      en: 'Book your ride easily using this QR code or link.',
      fr: 'Réservez facilement votre trajet via ce code QR ou ce lien.',
      es: 'Reserva tu viaje fácilmente con este código QR o enlace.',
    );
    final errorMessage = _t(
      nl: 'QR-afbeelding delen mislukt. Probeer opnieuw.',
      en: 'Failed to share QR image. Please try again.',
      fr: 'Le partage de l’image QR a échoué. Réessayez.',
      es: 'No se pudo compartir la imagen QR. Inténtalo de nuevo.',
    );

    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final renderObject = repaintBoundaryKey.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
        return;
      }
      final image = await renderObject.toImage(
        pixelRatio: math.max(2.0, math.min(devicePixelRatio * 2, 3.0)),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
        return;
      }
      final bytes = Uint8List.fromList(byteData.buffer.asUint8List());
      final tempDir = await getTemporaryDirectory();
      final fileCode = publicCompanyCode
          .replaceAll(RegExp(r'[^A-Z0-9-]'), '')
          .replaceAll('-', '');
      final filePath =
          '${tempDir.path}${Platform.pathSeparator}fluxidi_booking_qr_$fileCode.png';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/png')],
        text: shareMessage,
        subject: 'Fluxidi QR',
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  Future<void> _showPublicBookingShareQuickAccess(BuildContext context) async {
    final publicCompanyCode = _resolvePublicBookingCompanyCodeForDashboard();
    if (publicCompanyCode == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Publieke bedrijfscode ontbreekt. Verifieer je bedrijf eerst via Bedrijfsinstellingen.',
              en: 'Public company code is missing. Verify your company first via Business Settings.',
              fr: 'Le code entreprise public est manquant. Vérifiez d’abord votre entreprise via les Paramètres entreprise.',
              es: 'Falta el código público de empresa. Verifica primero tu empresa en Ajustes de empresa.',
            ),
          ),
        ),
      );
      return;
    }

    final publicBookingUrl = _preparedPublicBookingUrlForDashboard(
      publicCompanyCode,
    );
    final qrCardBoundaryKey = GlobalKey();
    final profileName = (companyProfileNotifier.value?.companyName ?? '')
        .trim();
    final qrCardTitle = profileName.isNotEmpty ? profileName : 'Fluxidi';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxQrSize = math.min(
          180.0,
          MediaQuery.of(sheetContext).size.width - 96,
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.38)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 22,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(
                        nl: 'Publieke boekingslink',
                        en: 'Public booking link',
                        fr: 'Lien de réservation public',
                        es: 'Enlace público de reserva',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        nl: 'Deel deze link of QR-code met klanten zodat zij rechtstreeks kunnen boeken.',
                        en: 'Share this link or QR code with customers so they can book directly.',
                        fr: 'Partagez ce lien ou ce code QR avec les clients afin qu’ils puissent réserver directement.',
                        es: 'Comparte este enlace o código QR con los clientes para que puedan reservar directamente.',
                      ),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0B0B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFD4AF4A).withOpacity(0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              nl: 'Publieke bedrijfscode',
                              en: 'Public company code',
                              fr: 'Code entreprise public',
                              es: 'Código público de empresa',
                            ),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            publicCompanyCode,
                            style: const TextStyle(
                              color: Color(0xFFF0C85D),
                              fontFamily: 'monospace',
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0B0B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                        ),
                      ),
                      child: SelectableText(
                        publicBookingUrl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 12.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: RepaintBoundary(
                        key: qrCardBoundaryKey,
                        child: Container(
                          width: math.min(
                            320.0,
                            MediaQuery.of(sheetContext).size.width - 56,
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFD4AF4A).withOpacity(0.55),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                qrCardTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF101010),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  nl: 'Scan om een rit te boeken',
                                  en: 'Scan to book a ride',
                                  fr: 'Scannez pour réserver une course',
                                  es: 'Escanea para reservar un viaje',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF262626),
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              QrImageView(
                                data: publicBookingUrl,
                                version: QrVersions.auto,
                                size: maxQrSize,
                                backgroundColor: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                publicCompanyCode,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF101010),
                                  fontFamily: 'monospace',
                                  fontSize: 12.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  nl: 'Aangedreven door Fluxidi',
                                  en: 'Powered by Fluxidi',
                                  fr: 'Propulsé par Fluxidi',
                                  es: 'Con tecnología de Fluxidi',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(
                                    0xFF2A2A2A,
                                  ).withOpacity(0.78),
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w600,
                                  height: 1.22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: publicCompanyCode),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _t(
                                    nl: 'Publieke bedrijfscode gekopieerd',
                                    en: 'Public company code copied',
                                    fr: 'Code entreprise public copié',
                                    es: 'Código público de empresa copiado',
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: Text(
                            _t(
                              nl: 'Kopieer code',
                              en: 'Copy code',
                              fr: 'Copier le code',
                              es: 'Copiar código',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: publicBookingUrl),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _t(
                                    nl: 'Publieke boekingslink gekopieerd',
                                    en: 'Public booking link copied',
                                    fr: 'Lien de réservation public copié',
                                    es: 'Enlace público de reserva copiado',
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: Text(
                            _t(
                              nl: 'Kopieer link',
                              en: 'Copy link',
                              fr: 'Copier le lien',
                              es: 'Copiar enlace',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _sharePublicBookingQrCardImage(
                            context: context,
                            repaintBoundaryKey: qrCardBoundaryKey,
                            publicCompanyCode: publicCompanyCode,
                            publicBookingUrl: publicBookingUrl,
                          ),
                          icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                          label: Text(
                            _t(
                              nl: 'Deel QR',
                              en: 'Share QR',
                              fr: 'Partager QR',
                              es: 'Compartir QR',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Share.share(publicBookingUrl);
                          },
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: Text(
                            _t(
                              nl: 'Delen',
                              en: 'Share',
                              fr: 'Partager',
                              es: 'Compartir',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final uri = Uri.parse(publicBookingUrl);
                              final launched = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!launched && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        nl: 'Publieke boekingslink kon niet geopend worden.',
                                        en: 'Could not open public booking link.',
                                        fr: 'Impossible d’ouvrir le lien de réservation public.',
                                        es: 'No se pudo abrir el enlace público de reserva.',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _t(
                                      nl: 'Publieke boekingslink kon niet geopend worden.',
                                      en: 'Could not open public booking link.',
                                      fr: 'Impossible d’ouvrir le lien de réservation public.',
                                      es: 'No se pudo abrir el enlace público de reserva.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.open_in_new_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _t(
                              nl: 'Open link',
                              en: 'Open link',
                              fr: 'Ouvrir le lien',
                              es: 'Abrir enlace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchCompany(BuildContext context) async {
    await CompanySessionStore.instance.clearLocalCompanyState();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const RoleEntryPage()),
      (route) => false,
    );
  }

  String _normalizeActivationCompanyCode(String raw) {
    var text = raw.trim().toUpperCase();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'\s+'), '-');
    text = text.replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    text = text.replaceAll(RegExp(r'-+'), '-');
    text = text.replaceAll(RegExp(r'^-+|-+$'), '');
    return text;
  }

  bool _isValidActivationCompanyCode(String value) {
    final code = _normalizeActivationCompanyCode(value);
    if (code.length < 4 || code.length > 24) return false;
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(code)) return false;
    if (!RegExp(r'[A-Z0-9]').hasMatch(code)) return false;
    final parts = code.split('-').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length != 2) return false;
    if (!RegExp(r'^[A-Z0-9]{2,10}$').hasMatch(parts[0])) return false;
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(parts[1])) return false;
    return true;
  }

  ({String tenantId, String companyId})?
  _activeCompanyScopeForPairingCodeCreate() {
    final sessionCompany =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (sessionCompany.isNotEmpty) {
      return (tenantId: sessionCompany, companyId: sessionCompany);
    }
    final profileCompany = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (profileCompany.isNotEmpty) {
      return (tenantId: profileCompany, companyId: profileCompany);
    }
    return null;
  }

  String? _activeCompanyCodeForPairingCodeCreate() {
    final canonicalCode = _resolvePublicBookingCompanyCodeForDashboard();
    final normalized = _normalizeActivationCompanyCode(canonicalCode ?? '');
    if (_isValidActivationCompanyCode(normalized)) return normalized;
    return null;
  }

  String? _publicCompanyCodeFromBootstrapPayload(Map<String, dynamic> payload) {
    String readTopLevel() {
      return _normalizeActivationCompanyCode(
        (payload['public_company_code'] ??
                payload['publicCompanyCode'] ??
                payload['company_code'] ??
                payload['companyCode'] ??
                '')
            .toString(),
      );
    }

    String readCompanyNode() {
      final companyNode = payload['company'];
      if (companyNode is! Map) return '';
      final map = Map<String, dynamic>.from(companyNode);
      return _normalizeActivationCompanyCode(
        (map['public_company_code'] ??
                map['publicCompanyCode'] ??
                map['company_code'] ??
                map['companyCode'] ??
                map['code'] ??
                '')
            .toString(),
      );
    }

    String readBusinessProfileNode() {
      final node = payload['business_profile'];
      if (node is! Map) return '';
      final map = Map<String, dynamic>.from(node);
      return _normalizeActivationCompanyCode(
        (map['public_company_code'] ??
                map['publicCompanyCode'] ??
                map['company_code'] ??
                map['companyCode'] ??
                '')
            .toString(),
      );
    }

    final fromBusinessProfile = readBusinessProfileNode();
    if (_isValidActivationCompanyCode(fromBusinessProfile)) {
      return fromBusinessProfile;
    }
    final fromCompany = readCompanyNode();
    if (_isValidActivationCompanyCode(fromCompany)) return fromCompany;
    final top = readTopLevel();
    if (_isValidActivationCompanyCode(top)) return top;
    return null;
  }

  Future<({String? companyCode, String source})>
  _resolvePublicCompanyCodeForPairingCodeCreate() async {
    final fromSession = _activeCompanyCodeForPairingCodeCreate();
    if (fromSession != null) {
      return (companyCode: fromSession, source: 'canonical');
    }

    final session = activeCompanySessionNotifier.value;
    final token = (session?.companySessionToken ?? '').trim();
    if (token.isEmpty) {
      return (companyCode: null, source: 'none');
    }

    try {
      final bootstrap = await fetchCompanyBootstrapWithToken(
        companySessionToken: token,
      );
      if (bootstrap is Map<String, dynamic>) {
        final fromBootstrap = _publicCompanyCodeFromBootstrapPayload(bootstrap);
        if (fromBootstrap != null) {
          if (session != null) {
            activeCompanySessionNotifier.value = session.copyWith(
              companyCode: fromBootstrap,
            );
          }
          return (companyCode: fromBootstrap, source: 'bootstrap');
        }
      }
    } catch (_) {}
    return (companyCode: null, source: 'none');
  }

  Future<void> _showNewDeviceActivationCodeDialog(BuildContext context) async {
    final adminToken = kAdminToken.trim();
    if (adminToken.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Toestelkoppeling is nu niet beschikbaar.',
              en: 'Device pairing is currently unavailable.',
              fr: 'Le jumelage d’appareil est actuellement indisponible.',
              es: 'La vinculación de dispositivo no está disponible actualmente.',
            ),
          ),
        ),
      );
      return;
    }

    final backendContext = await _resolveBackendUsableCompanyContextForAdmin(
      reason: 'business_home_pairing_code_create',
      logDegraded: true,
    );
    if (!context.mounted) return;
    if (!backendContext.usable) {
      debugPrint(
        '[PAIR_CODE_CREATE][BLOCKED] code=${backendContext.reasonCode} source=${backendContext.tokenSource}',
      );
      await _showDegradedCompanySessionRecoveryDialog(
        context,
        reason: 'business_home_pairing_code_create',
      );
      return;
    }

    final scope = _activeCompanyScopeForPairingCodeCreate();
    final codeResolution =
        await _resolvePublicCompanyCodeForPairingCodeCreate();
    final companyCode = codeResolution.companyCode;
    debugPrint(
      '[PAIR_CODE_CREATE][SCOPE] has_scope=${scope != null} has_public_code=${companyCode != null} source=${codeResolution.source}',
    );
    if (scope == null || companyCode == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Verifieer dit bedrijf eerst voordat u nieuwe toestellen kunt koppelen.',
              en: 'Verify this company first before pairing new devices.',
              fr: 'Vérifiez d’abord cette entreprise avant d’associer de nouveaux appareils.',
              es: 'Verifica primero esta empresa antes de vincular nuevos dispositivos.',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.3,
                color: kFluxidiYellow.withOpacity(0.95),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _t(
                  nl: 'Activatiecode aanmaken...',
                  en: 'Generating activation code...',
                  fr: 'Génération du code d’activation...',
                  es: 'Generando código de activación...',
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    Map<String, dynamic> payload = const <String, dynamic>{};
    int statusCode = -1;
    try {
      final endpoint =
          Uri.parse('$kBookingBaseUrl/admin/company/link-code/create').replace(
            queryParameters: <String, String>{
              'tenant_id': scope.tenantId,
              'company_id': scope.companyId,
            },
          );
      debugPrint(
        '[PAIR_CODE_CREATE][REQ] tenant=${_maskScopeForLog(scope.tenantId)} company=${_maskScopeForLog(scope.companyId)} code=$companyCode',
      );
      final response = await http
          .post(
            endpoint,
            headers: _adminHeaders(),
            body: jsonEncode(<String, dynamic>{
              'tenant_id': scope.tenantId,
              'company_id': scope.companyId,
              'company_code': companyCode,
            }),
          )
          .timeout(const Duration(seconds: 12));
      statusCode = response.statusCode;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        payload = Map<String, dynamic>.from(decoded);
      }
      debugPrint(
        '[PAIR_CODE_CREATE][RES] status=$statusCode ok=${payload['ok'] == true}',
      );
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final ok = statusCode >= 200 && statusCode < 300 && payload['ok'] == true;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Activatiecode kon niet worden aangemaakt. Probeer opnieuw.',
              en: 'Could not generate activation code. Please try again.',
              fr: 'Impossible de générer le code d’activation. Réessayez.',
              es: 'No se pudo generar el código de activación. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }

    final returnedCompanyCode = _normalizeActivationCompanyCode(
      (payload['company_code'] ?? companyCode).toString(),
    );
    final pairingCode = (payload['pairing_code'] ?? '').toString().trim();
    if (!_isValidActivationCompanyCode(returnedCompanyCode) ||
        !RegExp(r'^\d{6}$').hasMatch(pairingCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Activatiecode kon niet worden aangemaakt. Probeer opnieuw.',
              en: 'Could not generate activation code. Please try again.',
              fr: 'Impossible de générer le code d’activation. Réessayez.',
              es: 'No se pudo generar el código de activación. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
      return;
    }

    final activationCode = '$returnedCompanyCode-$pairingCode';
    final expiresAt = (payload['expires_at'] ?? '').toString().trim();
    final expiresInSeconds = int.tryParse(
      (payload['expires_in_seconds'] ?? '').toString().trim(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kFluxidiYellow.withOpacity(0.45)),
        ),
        title: Text(
          _t(
            nl: 'Nieuw toestel koppelen',
            en: 'Pair new device',
            fr: 'Associer un nouvel appareil',
            es: 'Vincular nuevo dispositivo',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                nl: 'Open Fluxidi op het nieuwe toestel en voer deze activatiecode in.',
                en: 'Open Fluxidi on the new device and enter this activation code.',
                fr: 'Ouvrez Fluxidi sur le nouvel appareil et saisissez ce code d’activation.',
                es: 'Abre Fluxidi en el nuevo dispositivo e introduce este código de activación.',
              ),
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.36)),
              ),
              child: SelectableText(
                activationCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (expiresAt.isNotEmpty || expiresInSeconds != null) ...[
              const SizedBox(height: 8),
              Text(
                expiresAt.isNotEmpty
                    ? _t(
                        nl: 'Vervalt op: $expiresAt',
                        en: 'Expires at: $expiresAt',
                        fr: 'Expire le : $expiresAt',
                        es: 'Caduca el: $expiresAt',
                      )
                    : _t(
                        nl: 'Geldig voor ongeveer ${expiresInSeconds ?? 0} seconden.',
                        en: 'Valid for about ${expiresInSeconds ?? 0} seconds.',
                        fr: 'Valable pendant environ ${expiresInSeconds ?? 0} secondes.',
                        es: 'Válido durante aproximadamente ${expiresInSeconds ?? 0} segundos.',
                      ),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11.8,
                ),
              ),
            ],
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: activationCode));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      nl: 'Activatiecode gekopieerd.',
                      en: 'Activation code copied.',
                      fr: 'Code d’activation copié.',
                      es: 'Código de activación copiado.',
                    ),
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: kFluxidiYellow.withOpacity(0.5)),
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(
              _t(nl: 'Kopiëren', en: 'Copy', fr: 'Copier', es: 'Copiar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              _t(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyCompanyFromBusinessHome(BuildContext context) async {
    const roleEntry = RoleEntryPage();
    final activationCode = await roleEntry._promptCompanyActivationCode(
      context,
    );
    if (!context.mounted || activationCode == null) return;
    if (activationCode == RoleEntryPage._companyPairingOnboardingIntent) return;
    final parsed = roleEntry._parseCompanyActivationCode(activationCode);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Ongeldige activatiecode. Gebruik bijvoorbeeld FLX-4821-123456.',
              en: 'Invalid activation code. Use for example FLX-4821-123456.',
              fr: 'Code d’activation invalide. Utilisez par exemple FLX-4821-123456.',
              es: 'Código de activación no válido. Usa por ejemplo FLX-4821-123456.',
            ),
          ),
        ),
      );
      return;
    }

    final verified = await roleEntry._verifyCompanyPairingCode(
      companyCode: parsed.companyCode,
      pairingCode: parsed.pairingCode,
    );
    if (!context.mounted) return;
    if (verified['ok'] != true) {
      final errorCode = roleEntry
          ._safePairingText(verified['error'])
          .toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(roleEntry._companyPairingErrorText(errorCode))),
      );
      return;
    }

    final payload = verified['payload'] is Map
        ? Map<String, dynamic>.from(verified['payload'] as Map)
        : <String, dynamic>{};
    await roleEntry._showCompanyPairingSuccessDialog(context);
    if (!context.mounted) return;
    final opened = await roleEntry._openVerifiedCompanySession(
      context,
      payload,
    );
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            roleEntry._companyPairingErrorText('verification_failed'),
          ),
        ),
      );
    }
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101010), Color(0xFF07080C), Color(0xFF07080C)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.17)),
        boxShadow: [
          BoxShadow(
            color: kFluxidiYellow.withOpacity(0.07),
            blurRadius: 12,
            spreadRadius: 0.2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.36),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _topBar(BuildContext context, CompanyProfile? profile) {
    final publicCompanyCode = _resolvePublicBookingCompanyCodeForDashboard();
    final hasPublicCompanyCode = publicCompanyCode != null;
    String firstNonEmpty(List<String?> values) {
      for (final value in values) {
        final text = (value ?? '').trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final profileJson = profile?.toJson();
    final profilePublicDisplayName = profileJson is Map<String, dynamic>
        ? firstNonEmpty(<String?>[
            profileJson['publicDisplayName']?.toString(),
            profileJson['public_display_name']?.toString(),
          ])
        : '';
    final profileLegalName = profileJson is Map<String, dynamic>
        ? firstNonEmpty(<String?>[
            profileJson['legalName']?.toString(),
            profileJson['legal_name']?.toString(),
          ])
        : '';
    final companyIdentityName = firstNonEmpty(<String?>[
      profile?.companyName,
      profilePublicDisplayName,
      profileLegalName,
      publicCompanyCode,
      profile?.companyId,
      _t(nl: 'Bedrijf', en: 'Business', fr: 'Entreprise', es: 'Empresa'),
    ]);
    final companyName = companyIdentityName;
    final screenW = MediaQuery.of(context).size.width;
    const customerReferenceLogoWidth = 178.0;
    final businessLogoWidth = math.max(
      120.0,
      math.min(customerReferenceLogoWidth, screenW - 250),
    );
    return Row(
      children: [
        Image.asset(
          kFluxidiLogoAsset,
          width: businessLogoWidth,
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        const Spacer(),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kFluxidiYellow.withOpacity(0.28)),
            color: const Color(0xFF111111),
          ),
          child: Icon(
            Icons.notifications_none_rounded,
            size: 19,
            color: kFluxidiYellow.withOpacity(0.93),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          color: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: kFluxidiYellow.withOpacity(0.36)),
          ),
          onSelected: (value) {
            if (value == 'details') {
              _openCompanyDetails(context);
              return;
            }
            if (value == 'verify_company') {
              unawaited(_verifyCompanyFromBusinessHome(context));
              return;
            }
            if (value == 'pair_new_device') {
              unawaited(_showNewDeviceActivationCodeDialog(context));
              return;
            }
            if (value == 'switch') {
              _switchCompany(context);
            }
          },
          itemBuilder: (_) => [
            if (profile != null)
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasPublicCompanyCode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF12331F),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF4ADE80).withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: 'Geverifieerd',
                            en: 'Verified',
                            fr: 'Vérifiée',
                            es: 'Verificada',
                          ),
                          style: const TextStyle(
                            color: Color(0xFFB8F5C8),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      _statusPill(profile, compact: true),
                    const SizedBox(height: 8),
                    Text(
                      companyIdentityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (publicCompanyCode != null) ...[
                      Text(
                        '${_t(nl: 'Fluxidi-code', en: 'Fluxidi code', fr: 'Code Fluxidi', es: 'Código Fluxidi')}: $publicCompanyCode',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      '${_t(nl: 'Interne referentie', en: 'Internal reference', fr: 'Référence interne', es: 'Referencia interna')}: ${profile.companyId}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                    if (!hasPublicCompanyCode &&
                        profile.showsPendingVerificationNotice) ...[
                      const SizedBox(height: 6),
                      Text(
                        profile.verificationPendingNotice(
                          appConfig.currentLanguage,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            PopupMenuItem<String>(
              value: 'details',
              child: Text(
                _t(
                  nl: 'Bedrijfsgegevens',
                  en: 'Company details',
                  fr: 'Données de l’entreprise',
                  es: 'Datos de empresa',
                ),
              ),
            ),
            if (!hasPublicCompanyCode)
              PopupMenuItem<String>(
                value: 'verify_company',
                child: Text(
                  _t(
                    nl: 'Bedrijf verifiëren',
                    en: 'Verify company',
                    fr: 'Vérifier l’entreprise',
                    es: 'Verificar empresa',
                  ),
                ),
              ),
            if (hasPublicCompanyCode)
              PopupMenuItem<String>(
                value: 'pair_new_device',
                child: Text(
                  _t(
                    nl: 'Nieuw toestel koppelen',
                    en: 'Pair new device',
                    fr: 'Associer un nouvel appareil',
                    es: 'Vincular nuevo dispositivo',
                  ),
                ),
              ),
            PopupMenuItem<String>(
              value: 'switch',
              child: Text(
                _t(
                  nl: 'Ander bedrijf',
                  en: 'Other company',
                  fr: 'Autre entreprise',
                  es: 'Otra empresa',
                ),
                style: TextStyle(color: Colors.redAccent.shade100),
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kFluxidiYellow.withOpacity(0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF15120A),
                    border: Border.all(color: kFluxidiYellow.withOpacity(0.5)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _companyInitials(profile),
                    style: const TextStyle(
                      color: Color(0xFFE5B641),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        _t(
                          nl: 'Bedrijf',
                          en: 'Business',
                          fr: 'Entreprise',
                          es: 'Empresa',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.68),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: kFluxidiYellow.withOpacity(0.95),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color accentColor,
    bool compact = false,
  }) {
    return _panel(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 8 : 11,
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 28 : 34,
            height: compact ? 28 : 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withOpacity(0.16),
              border: Border.all(color: accentColor.withOpacity(0.45)),
            ),
            child: Icon(icon, color: accentColor, size: compact ? 16 : 19),
          ),
          SizedBox(width: compact ? 7 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 11.6 : 13.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: compact ? 1 : 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: compact ? 10.0 : 11.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 19 : 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryCta(BuildContext context, {bool compact = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openCalculator(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kFluxidiYellow.withOpacity(0.48)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF15120A), Color(0xFF07080C)],
          ),
          boxShadow: [
            BoxShadow(
              color: kFluxidiYellow.withOpacity(0.13),
              blurRadius: 18,
              spreadRadius: 0.8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 36 : 44,
              height: compact ? 36 : 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kFluxidiYellow.withOpacity(0.35),
                    const Color(0xFF15120A),
                  ],
                ),
                border: Border.all(color: kFluxidiYellow.withOpacity(0.55)),
              ),
              child: const Icon(
                Icons.calculate_outlined,
                color: Color(0xFFE5B641),
                size: 22,
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Bereken & boek je rit',
                      en: 'Calculate & book your ride',
                      fr: 'Calculez et réservez votre course',
                      es: 'Calcula y reserva tu viaje',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 14.0 : 15.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: kFluxidiYellow.withOpacity(0.98),
              size: compact ? 20 : 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isFuture = false,
    String? futureBadge,
    String? statusBadge,
    String? backgroundAsset,
    bool useImageBackground = false,
    bool compact = false,
  }) {
    final active = onTap != null && !isFuture;
    final hasImageBackground =
        useImageBackground && (backgroundAsset ?? '').trim().isNotEmpty;
    final cardPadding = EdgeInsets.fromLTRB(
      compact ? 8 : 12,
      compact ? 8 : 12,
      compact ? 8 : 12,
      compact ? 6 : 10,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: compact ? 36 : 44,
              height: compact ? 36 : 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    (active ? kFluxidiYellow : const Color(0xFF8A8A8A))
                        .withOpacity(0.28),
                    const Color(0xFF15120A),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (active ? kFluxidiYellow : Colors.white).withOpacity(
                    active ? 0.50 : 0.26,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (active ? kFluxidiYellow : Colors.black).withOpacity(
                      active ? 0.10 : 0.16,
                    ),
                    blurRadius: 10,
                    spreadRadius: 0.2,
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: active
                    ? kFluxidiYellow.withOpacity(0.98)
                    : Colors.white.withOpacity(0.60),
                size: compact ? 22 : 29,
              ),
            ),
            const Spacer(),
            if ((futureBadge ?? '').trim().isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 7 : 8,
                  vertical: compact ? 2 : 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF15120A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.42)),
                ),
                child: Text(
                  futureBadge!,
                  style: TextStyle(
                    color: kFluxidiYellow.withOpacity(0.95),
                    fontSize: compact ? 9.5 : 10.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if ((futureBadge ?? '').trim().isEmpty &&
                (statusBadge ?? '').trim().isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 7 : 8,
                  vertical: compact ? 2 : 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A1B0F),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFE5B641).withOpacity(0.55),
                  ),
                ),
                child: Text(
                  statusBadge!,
                  style: TextStyle(
                    color: const Color(0xFFE5B641).withOpacity(0.98),
                    fontSize: compact ? 9.5 : 10.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: compact ? 5 : 9),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(active ? 1.0 : 0.78),
            fontWeight: FontWeight.w800,
            fontSize: compact ? 12.5 : 14.3,
            shadows: hasImageBackground
                ? [
                    Shadow(
                      color: Colors.black.withOpacity(0.62),
                      blurRadius: 6,
                      offset: const Offset(0, 1.2),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(active ? 0.64 : 0.5),
            fontSize: compact ? 10.0 : 11.4,
            shadows: hasImageBackground
                ? [
                    Shadow(
                      color: Colors.black.withOpacity(0.54),
                      blurRadius: 5,
                      offset: const Offset(0, 1.1),
                    ),
                  ]
                : null,
          ),
        ),
        const Spacer(),
        Align(
          alignment: Alignment.bottomRight,
          child: active
              ? Icon(
                  Icons.chevron_right_rounded,
                  size: compact ? 14 : 17,
                  color: kFluxidiYellow.withOpacity(0.9),
                )
              : Icon(
                  Icons.lock_clock_outlined,
                  size: compact ? 13 : 15.5,
                  color: Colors.white.withOpacity(0.44),
                ),
        ),
      ],
    );
    if (!hasImageBackground) {
      return InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: active ? onTap : null,
        child: _panel(padding: cardPadding, child: content),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: active ? onTap : null,
      child: _panel(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                backgroundAsset!,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withOpacity(0.62),
                        Colors.black.withOpacity(0.40),
                        Colors.black.withOpacity(0.24),
                        Colors.black.withOpacity(0.10),
                      ],
                      stops: const [0.0, 0.42, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: cardPadding, child: content),
          ],
        ),
      ),
    );
  }

  bool _isBusinessAdminSessionRecoveryRequired() {
    if (!CompanySessionStore.instance.hasValidCompanyContext) return false;
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final session = activeCompanySessionNotifier.value;
    final sessionCompanyId = (session?.companyId ?? '').trim();
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      return true;
    }
    final token = (session?.companySessionToken ?? '').trim();
    if (token.isEmpty) return true;
    final expiresAt = session?.sessionExpiresAtUtc;
    if (expiresAt != null && !DateTime.now().toUtc().isBefore(expiresAt)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF07080C),
        body: SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF101010),
                  Color(0xFF07080C),
                  Color(0xFF07080C),
                ],
              ),
            ),
            child: ValueListenableBuilder<CompanyProfile?>(
              valueListenable: companyProfileNotifier,
              builder: (context, profile, _) {
                double clampDouble(double v, double min, double max) =>
                    v < min ? min : (v > max ? max : v);
                final size = MediaQuery.sizeOf(context);
                final W = size.width;
                final H = size.height;
                final screenClass = FluxidiBreakpoints.classifyWidth(W);
                final mediaPaddingBottom = MediaQuery.paddingOf(context).bottom;
                final isTabletPortrait =
                    (screenClass == FluxidiScreenClass.tablet ||
                        screenClass == FluxidiScreenClass.desktop) &&
                    W < H &&
                    H >= 900;
                final isTabletLandscape =
                    (screenClass == FluxidiScreenClass.tablet ||
                        screenClass == FluxidiScreenClass.desktop) &&
                    W > H &&
                    W >= 900;
                final useTabletVisualMode =
                    isTabletPortrait || isTabletLandscape;
                final usesTabletHeader = useTabletVisualMode;
                final businessHeaderHeight = isTabletLandscape
                    ? clampDouble(H * 0.17, 110.0, 150.0)
                    : isTabletPortrait
                    ? clampDouble(H * 0.23, 300.0, 360.0)
                    : null;
                const businessHeaderAsset =
                    'assets/fluxidi/zakelijke_tablet_header_foto.png';
                final businessQuickActionCardHeight = isTabletLandscape
                    ? clampDouble(H * 0.21, 150.0, 188.0)
                    : isTabletPortrait
                    ? clampDouble(H * 0.092, 118.0, 132.0)
                    : 132.0;
                final businessQuickActionSpacing = isTabletLandscape
                    ? 8.0
                    : isTabletPortrait
                    ? 14.0
                    : 12.0;
                final businessBackButtonGap = isTabletLandscape
                    ? clampDouble(H * 0.025, 10.0, 22.0)
                    : isTabletPortrait
                    ? 10.0
                    : 14.0;
                final businessListBottomPadding = isTabletLandscape
                    ? math.max(mediaPaddingBottom + 12.0, 22.0)
                    : isTabletPortrait
                    ? 12.0
                    : 20.0;
                final businessSectionGap = isTabletLandscape ? 6.0 : 10.0;
                final businessQuickActionsTitleGap = isTabletLandscape
                    ? 8.0
                    : 14.0;
                final businessQuickActionsGridTopGap = isTabletLandscape
                    ? 8.0
                    : 10.0;
                final headerTitleFontSize = isTabletLandscape ? 15.0 : 19.0;
                final headerSubtitleFontSize = isTabletLandscape ? 11.0 : 12.5;
                final headerTextBottomGap = isTabletLandscape ? 2.0 : 3.0;
                final headerContentPadding = isTabletLandscape
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                    : const EdgeInsets.fromLTRB(12, 12, 12, 14);

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    businessListBottomPadding,
                  ),
                  children: [
                    if (usesTabletHeader)
                      Container(
                        height: businessHeaderHeight,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: kFluxidiYellow.withOpacity(0.22),
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              businessHeaderAsset,
                              fit: BoxFit.cover,
                              alignment: isTabletLandscape
                                  ? const Alignment(0.25, 0.35)
                                  : Alignment.center,
                              errorBuilder: (_, __, ___) => const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF101010),
                                      Color(0xFF07080C),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.12),
                                      Colors.black.withOpacity(0.22),
                                      Colors.black.withOpacity(0.58),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: headerContentPadding,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ValueListenableBuilder<
                                      ActiveCompanySession?
                                    >(
                                      valueListenable:
                                          activeCompanySessionNotifier,
                                      builder: (context, _, __) =>
                                          _topBar(context, profile),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _t(
                                        nl: 'Goedemorgen! 👋',
                                        en: 'Good morning! 👋',
                                        fr: 'Bonjour ! 👋',
                                        es: '¡Buenos días! 👋',
                                      ),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: headerTitleFontSize,
                                      ),
                                    ),
                                    SizedBox(height: headerTextBottomGap),
                                    Text(
                                      _t(
                                        nl: 'Bedrijfsoverzicht',
                                        en: 'Business overview',
                                        fr: 'Aperçu de l’entreprise',
                                        es: 'Resumen de empresa',
                                      ),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.78),
                                        fontSize: headerSubtitleFontSize,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      ValueListenableBuilder<ActiveCompanySession?>(
                        valueListenable: activeCompanySessionNotifier,
                        builder: (context, _, __) => _topBar(context, profile),
                      ),
                      const SizedBox(height: 12),
                      _panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Goedemorgen! 👋',
                                en: 'Good morning! 👋',
                                fr: 'Bonjour ! 👋',
                                es: '¡Buenos días! 👋',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _t(
                                nl: 'Bedrijfsoverzicht',
                                en: 'Business overview',
                                fr: 'Aperçu de l’entreprise',
                                es: 'Resumen de empresa',
                              ),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.74),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: businessSectionGap),
                    _primaryCta(context, compact: isTabletLandscape),
                    SizedBox(height: businessSectionGap),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked =
                            !isTabletLandscape && constraints.maxWidth < 430;
                        if (stacked) {
                          return Column(
                            children: [
                              _metricCard(
                                icon: Icons.calendar_month_outlined,
                                title: _t(
                                  nl: 'Open boekingen',
                                  en: 'Open bookings',
                                  fr: 'Réservations ouvertes',
                                  es: 'Reservas abiertas',
                                ),
                                subtitle: _t(
                                  nl: 'Gepland',
                                  en: 'Planned',
                                  fr: 'Planifiées',
                                  es: 'Planificadas',
                                ),
                                value: _metricCountText(_openBookingsCount),
                                accentColor: const Color(0xFF60A5FA),
                                compact: isTabletLandscape,
                              ),
                              SizedBox(height: isTabletLandscape ? 6 : 8),
                              _metricCard(
                                icon: Icons.directions_car_outlined,
                                title: _t(
                                  nl: 'Voltooide ritten',
                                  en: 'Completed rides',
                                  fr: 'Courses terminées',
                                  es: 'Viajes completados',
                                ),
                                subtitle: _t(
                                  nl: 'Afgerond',
                                  en: 'Completed',
                                  fr: 'Terminées',
                                  es: 'Completados',
                                ),
                                value: _metricCountText(_completedRidesCount),
                                accentColor: const Color(0xFF4ADE80),
                                compact: isTabletLandscape,
                              ),
                              SizedBox(height: isTabletLandscape ? 6 : 8),
                              _metricCard(
                                icon: Icons.payments_outlined,
                                title: _t(
                                  nl: 'Nog te betalen',
                                  en: 'To be paid',
                                  fr: 'À payer',
                                  es: 'Por pagar',
                                ),
                                subtitle: _t(
                                  nl: 'Afgerond maar onbetaald',
                                  en: 'Completed but unpaid',
                                  fr: 'Terminées mais impayées',
                                  es: 'Completados sin pagar',
                                ),
                                value: _metricCountText(
                                  _unpaidCompletedRidesCount,
                                ),
                                accentColor: const Color(0xFFF97373),
                                compact: isTabletLandscape,
                              ),
                              SizedBox(height: isTabletLandscape ? 6 : 8),
                              _metricCard(
                                icon: Icons.euro_rounded,
                                title: _t(
                                  nl: 'Maandomzet',
                                  en: 'Monthly income',
                                  fr: 'Revenus mensuels',
                                  es: 'Ingresos mensuales',
                                ),
                                subtitle: _t(
                                  nl: 'Betaald',
                                  en: 'Paid',
                                  fr: 'Payées',
                                  es: 'Pagado',
                                ),
                                value: _metricIncomeText(),
                                accentColor: const Color(0xFFE5B641),
                                compact: isTabletLandscape,
                              ),
                            ],
                          );
                        }
                        final columns = isTabletLandscape
                            ? 4
                            : constraints.maxWidth < 760
                            ? 2
                            : 4;
                        final spacing = isTabletLandscape ? 6.0 : 8.0;
                        final cardWidth =
                            (constraints.maxWidth - ((columns - 1) * spacing)) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _metricCard(
                                icon: Icons.calendar_month_outlined,
                                title: _t(
                                  nl: 'Open boekingen',
                                  en: 'Open bookings',
                                  fr: 'Réservations ouvertes',
                                  es: 'Reservas abiertas',
                                ),
                                subtitle: _t(
                                  nl: 'Gepland',
                                  en: 'Planned',
                                  fr: 'Planifiées',
                                  es: 'Planificadas',
                                ),
                                value: _metricCountText(_openBookingsCount),
                                accentColor: const Color(0xFF60A5FA),
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _metricCard(
                                icon: Icons.directions_car_outlined,
                                title: _t(
                                  nl: 'Voltooide ritten',
                                  en: 'Completed rides',
                                  fr: 'Courses terminées',
                                  es: 'Viajes completados',
                                ),
                                subtitle: _t(
                                  nl: 'Afgerond',
                                  en: 'Completed',
                                  fr: 'Terminées',
                                  es: 'Completados',
                                ),
                                value: _metricCountText(_completedRidesCount),
                                accentColor: const Color(0xFF4ADE80),
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _metricCard(
                                icon: Icons.payments_outlined,
                                title: _t(
                                  nl: 'Nog te betalen',
                                  en: 'To be paid',
                                  fr: 'À payer',
                                  es: 'Por pagar',
                                ),
                                subtitle: _t(
                                  nl: 'Afgerond maar onbetaald',
                                  en: 'Completed but unpaid',
                                  fr: 'Terminées mais impayées',
                                  es: 'Completados sin pagar',
                                ),
                                value: _metricCountText(
                                  _unpaidCompletedRidesCount,
                                ),
                                accentColor: const Color(0xFFF97373),
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _metricCard(
                                icon: Icons.euro_rounded,
                                title: _t(
                                  nl: 'Maandomzet',
                                  en: 'Monthly income',
                                  fr: 'Revenus mensuels',
                                  es: 'Ingresos mensuales',
                                ),
                                subtitle: _t(
                                  nl: 'Betaald',
                                  en: 'Paid',
                                  fr: 'Payées',
                                  es: 'Pagado',
                                ),
                                value: _metricIncomeText(),
                                accentColor: const Color(0xFFE5B641),
                                compact: isTabletLandscape,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: businessQuickActionsTitleGap),
                    Text(
                      _t(
                        nl: 'Snelle acties',
                        en: 'Quick actions',
                        fr: 'Actions rapides',
                        es: 'Acciones rápidas',
                      ),
                      style: TextStyle(
                        color: kFluxidiYellow.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_isBusinessAdminSessionRecoveryRequired()) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1B0F),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFFE5B641).withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          _t(
                            nl: 'Bedrijfssessie herstellen vereist',
                            en: 'Company admin session recovery required',
                            fr: "Récupération de session entreprise requise",
                            es: 'Se requiere recuperar la sesión de empresa',
                          ),
                          style: TextStyle(
                            color: const Color(0xFFE5B641).withOpacity(0.98),
                            fontSize: 10.7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: businessQuickActionsGridTopGap),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final quickActionColumns = isTabletLandscape ? 5 : 2;
                        final totalHorizontalSpacing =
                            businessQuickActionSpacing *
                            (quickActionColumns - 1);
                        final cardWidth =
                            (constraints.maxWidth - totalHorizontalSpacing) /
                            quickActionColumns;
                        return Wrap(
                          spacing: businessQuickActionSpacing,
                          runSpacing: businessQuickActionSpacing,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.business_center_outlined,
                                title: _t(
                                  nl: 'Instellingen',
                                  en: 'Settings',
                                  fr: 'Réglages',
                                  es: 'Ajustes',
                                ),
                                subtitle: _t(
                                  nl: 'Profiel & branding',
                                  en: 'Profile & branding',
                                  fr: 'Profil & branding',
                                  es: 'Perfil y marca',
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const BusinessSettingsPage(),
                                    ),
                                  );
                                },
                                backgroundAsset:
                                    'assets/fluxidi/settings_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            if (isTabletLandscape)
                              SizedBox(
                                width: cardWidth,
                                height: businessQuickActionCardHeight,
                                child: _quickActionCard(
                                  icon: Icons.calendar_month_outlined,
                                  title: _t(
                                    nl: 'Boekingen',
                                    en: 'Bookings',
                                    fr: 'Réservations',
                                    es: 'Reservas',
                                  ),
                                  subtitle: _t(
                                    nl: 'Alle boekingen',
                                    en: 'All bookings',
                                    fr: 'Toutes les réservations',
                                    es: 'Todas las reservas',
                                  ),
                                  onTap: () =>
                                      _openBusinessBookingsOverview(context),
                                  backgroundAsset:
                                      'assets/fluxidi/bookings_background_company.png',
                                  useImageBackground: useTabletVisualMode,
                                  compact: isTabletLandscape,
                                ),
                              ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.credit_card_outlined,
                                title: _t(
                                  nl: 'Abonnement',
                                  en: 'Plan',
                                  fr: 'Abonnement',
                                  es: 'Plan',
                                ),
                                subtitle: _t(
                                  nl: 'Facturatie',
                                  en: 'Billing',
                                  fr: 'Facturation',
                                  es: 'Facturación',
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const CompanySubscriptionBillingPage(),
                                    ),
                                  );
                                },
                                backgroundAsset:
                                    'assets/fluxidi/plan_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.directions_car_filled_outlined,
                                title: _t(
                                  nl: 'Voertuigen',
                                  en: 'Vehicles',
                                  fr: 'Véhicules',
                                  es: 'Vehículos',
                                ),
                                subtitle: _t(
                                  nl: 'Wagenpark',
                                  en: 'Fleet',
                                  fr: 'Flotte',
                                  es: 'Flota',
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const VehicleManagementPage(),
                                    ),
                                  );
                                },
                                backgroundAsset:
                                    'assets/fluxidi/vehicles_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.fact_check_outlined,
                                title: _t(
                                  nl: 'Chiron',
                                  en: 'Chiron',
                                  fr: 'Chiron',
                                  es: 'Chiron',
                                ),
                                subtitle: 'Compliance',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const ChironComplianceDashboardPage(),
                                    ),
                                  );
                                },
                                backgroundAsset:
                                    'assets/fluxidi/chiron_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.local_taxi_outlined,
                                title: _t(
                                  nl: 'Chauffeurs',
                                  en: 'Drivers',
                                  fr: 'Chauffeurs',
                                  es: 'Conductores',
                                ),
                                subtitle: _t(
                                  nl: 'Team',
                                  en: 'Team',
                                  fr: 'Équipe',
                                  es: 'Equipo',
                                ),
                                statusBadge:
                                    _isBusinessAdminSessionRecoveryRequired()
                                    ? _t(
                                        nl: 'Herstel vereist',
                                        en: 'Recovery required',
                                        fr: 'Récupération requise',
                                        es: 'Recuperación requerida',
                                      )
                                    : null,
                                onTap: () async {
                                  final backendContext =
                                      await _resolveBackendUsableCompanyContextForAdmin(
                                        reason: 'business_home_manage_drivers',
                                        logDegraded: true,
                                      );
                                  if (!context.mounted) return;
                                  if (!backendContext.usable) {
                                    debugPrint(
                                      '[COMPANY_SESSION][ADMIN_ENTRY_BLOCKED] flow=business_home_manage_drivers code=${backendContext.reasonCode} source=${backendContext.tokenSource}',
                                    );
                                    await _showDegradedCompanySessionRecoveryDialog(
                                      context,
                                      reason: 'business_home_manage_drivers',
                                    );
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const CompanyDriverManagementPage(),
                                    ),
                                  );
                                },
                                backgroundAsset:
                                    'assets/fluxidi/drivers_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.speed_rounded,
                                title: _t(
                                  nl: 'Chauffeur weergave',
                                  en: 'Driver view',
                                  fr: 'Vue chauffeur',
                                  es: 'Vista de conductor',
                                ),
                                subtitle: _t(
                                  nl: 'Ga naar de bestaande chauffeurcockpit zonder uit te loggen.',
                                  en: 'Open the existing driver cockpit without signing out.',
                                  fr: 'Ouvrir le cockpit chauffeur existant sans se déconnecter.',
                                  es: 'Abre la cabina de conductor existente sin cerrar sesión.',
                                ),
                                onTap: () => _openDriverCockpitView(context),
                                backgroundAsset:
                                    'assets/fluxidi/driver_view_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.radar_rounded,
                                title: _t(
                                  nl: 'Vraagradar',
                                  en: 'Demand radar',
                                  fr: 'Radar demande',
                                  es: 'Radar demanda',
                                ),
                                subtitle: _t(
                                  nl: 'Klantvraag',
                                  en: 'Customer demand',
                                  fr: 'Demande clients',
                                  es: 'Demanda clientes',
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const BusinessRegionalDemandPage(),
                                    ),
                                  );
                                },
                                backgroundAsset:
                                    'assets/fluxidi/demand_radar_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.qr_code_2_outlined,
                                title: _t(
                                  nl: 'Deel boekingslink',
                                  en: 'Share booking link',
                                  fr: 'Partager le lien de réservation',
                                  es: 'Compartir enlace de reserva',
                                ),
                                subtitle: _t(
                                  nl: 'Link + QR',
                                  en: 'Link + QR',
                                  fr: 'Lien + QR',
                                  es: 'Enlace + QR',
                                ),
                                onTap: () =>
                                    _showPublicBookingShareQuickAccess(context),
                                backgroundAsset:
                                    'assets/fluxidi/share_booking_link_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                            if (!isTabletLandscape)
                              SizedBox(
                                width: cardWidth,
                                height: businessQuickActionCardHeight,
                                child: _quickActionCard(
                                  icon: Icons.calendar_month_outlined,
                                  title: _t(
                                    nl: 'Boekingen',
                                    en: 'Bookings',
                                    fr: 'Réservations',
                                    es: 'Reservas',
                                  ),
                                  subtitle: _t(
                                    nl: 'Planning & opvolging',
                                    en: 'Planning & follow-up',
                                    fr: 'Planification & suivi',
                                    es: 'Planificación y seguimiento',
                                  ),
                                  onTap: () =>
                                      _openBusinessBookingsOverview(context),
                                  backgroundAsset:
                                      'assets/fluxidi/bookings_background_company.png',
                                  useImageBackground: useTabletVisualMode,
                                  compact: isTabletLandscape,
                                ),
                              ),
                            SizedBox(
                              width: cardWidth,
                              height: businessQuickActionCardHeight,
                              child: _quickActionCard(
                                icon: Icons.auto_awesome_outlined,
                                title: _t(
                                  nl: 'AI Dispatch',
                                  en: 'AI Dispatch',
                                  fr: 'Dispatch IA',
                                  es: 'Despacho IA',
                                ),
                                subtitle: _t(
                                  nl: 'Binnenkort',
                                  en: 'Coming soon',
                                  fr: 'Bientôt',
                                  es: 'Próximamente',
                                ),
                                isFuture: true,
                                futureBadge: _t(
                                  nl: 'Binnenkort',
                                  en: 'Soon',
                                  fr: 'Bientôt',
                                  es: 'Pronto',
                                ),
                                backgroundAsset:
                                    'assets/fluxidi/ai_dispatch_background_company.png',
                                useImageBackground: useTabletVisualMode,
                                compact: isTabletLandscape,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: businessBackButtonGap),
                    const FluxidiBackToStartButton(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
