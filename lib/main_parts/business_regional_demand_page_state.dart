part of '../main.dart';

class BusinessRegionalDemandPage extends StatefulWidget {
  const BusinessRegionalDemandPage({super.key});

  @override
  State<BusinessRegionalDemandPage> createState() =>
      _BusinessRegionalDemandPageState();
}

class _BusinessRegionalDemandPageState
    extends State<BusinessRegionalDemandPage> {
  BusinessThemePalette get _businessThemePalette =>
      paletteForBusinessTheme(businessThemeNotifier.value);
  bool _loading = false;
  String _country = 'BE';
  String _city = '';
  String _primaryPostcode = '';
  String _serviceRadiusKm = '';
  double? _coverageLat;
  double? _coverageLng;
  double _coverageRadiusKm = 8.0;
  mb.MapboxMap? _coverageMap;
  mb.PointAnnotationManager? _coverageCenterManager;
  mb.PolylineAnnotationManager? _coverageRadiusManager;
  List<String> _postcodes = const <String>[];
  List<_BusinessRegionalDemandRow> _rows = const <_BusinessRegionalDemandRow>[];
  int _totalCount = 0;
  /// RELEASE-P0 demand-radar: true when the primary region has no valid
  /// server response. Must never be presented as a numeric `0+`.
  bool _totalUnavailable = false;
  /// Monotonic load generation so late responses from an older refresh or
  /// previous company session are ignored.
  int _loadGeneration = 0;
  String? _boundCompanyId;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_loadDemand());
  }

  @override
  void dispose() {
    unawaited(_coverageCenterManager?.deleteAll() ?? Future<void>.value());
    unawaited(_coverageRadiusManager?.deleteAll() ?? Future<void>.value());
    _coverageCenterManager = null;
    _coverageRadiusManager = null;
    _coverageMap = null;
    super.dispose();
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

  String _normalizeCountry(String raw) => normalizeDemandRadarCountry(raw);

  ({String tenantId, String companyId})? _activeDemandScope() {
    final profileId = companyProfileNotifier.value?.companyId.trim() ?? '';
    final sessionId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (profileId.isNotEmpty &&
        sessionId.isNotEmpty &&
        profileId != sessionId) {
      return null;
    }
    final base = profileId.isNotEmpty ? profileId : sessionId;
    if (base.isEmpty) return null;
    return (tenantId: base, companyId: base);
  }

  String _normalizePostcode(String raw) => normalizeDemandRadarPostcode(raw);

  List<String> _parseServedPostcodes(String raw) =>
      parseDemandRadarServedPostcodes(raw);

  String _locationLabel() {
    if (_primaryPostcode.isNotEmpty && _city.isNotEmpty) {
      return '$_primaryPostcode · $_city';
    }
    if (_primaryPostcode.isNotEmpty) return _primaryPostcode;
    return _t(
      nl: 'jouw regio',
      en: 'your area',
      fr: 'votre région',
      es: 'tu zona',
    );
  }

  String _totalDisplayCount() {
    if (_totalUnavailable) {
      return demandRadarUnavailableLabel(currentLanguageCode);
    }
    return '$_totalCount+';
  }

  bool _hasText(String? value) => (value ?? '').trim().isNotEmpty;

  BackendBusinessProfile _mergeDemandProfile({
    required BackendBusinessProfile local,
    required BackendBusinessProfile server,
  }) {
    String pick(String localValue, String serverValue) =>
        _hasText(serverValue) ? serverValue : localValue;
    return BackendBusinessProfile(
      companyName: pick(local.companyName, server.companyName),
      legalName: pick(local.legalName, server.legalName),
      vatNumber: pick(local.vatNumber, server.vatNumber),
      companyRegistrationNumber: pick(
        local.companyRegistrationNumber,
        server.companyRegistrationNumber,
      ),
      address: pick(local.address, server.address),
      postcode: pick(local.postcode, server.postcode),
      city: pick(local.city, server.city),
      country: pick(local.country, server.country),
      phone: pick(local.phone, server.phone),
      email: pick(local.email, server.email),
      website: pick(local.website, server.website),
      bookingEmail: pick(local.bookingEmail, server.bookingEmail),
      publicLogoUrl: pick(local.publicLogoUrl, server.publicLogoUrl),
      publicHeroPhotoUrl: pick(
        local.publicHeroPhotoUrl,
        server.publicHeroPhotoUrl,
      ),
      publicServedPostcodes: pick(
        local.publicServedPostcodes,
        server.publicServedPostcodes,
      ),
      publicCoverageLat: pick(
        local.publicCoverageLat,
        server.publicCoverageLat,
      ),
      publicCoverageLng: pick(
        local.publicCoverageLng,
        server.publicCoverageLng,
      ),
      publicServiceRadiusKm: pick(
        local.publicServiceRadiusKm,
        server.publicServiceRadiusKm,
      ),
      publicPaymentOptions: server.publicPaymentOptions.isNotEmpty
          ? server.publicPaymentOptions
          : local.publicPaymentOptions,
      publicPartnerProfilePublishedAt: pick(
        local.publicPartnerProfilePublishedAt,
        server.publicPartnerProfilePublishedAt,
      ),
      publicPartnerProfilePublishStatus: pick(
        local.publicPartnerProfilePublishStatus,
        server.publicPartnerProfilePublishStatus,
      ),
      invoiceEmail: pick(local.invoiceEmail, server.invoiceEmail),
      iban: pick(local.iban, server.iban),
      paymentReferencePrefix: pick(
        local.paymentReferencePrefix,
        server.paymentReferencePrefix,
      ),
      invoiceReceiptFooterText: pick(
        local.invoiceReceiptFooterText,
        server.invoiceReceiptFooterText,
      ),
    );
  }

  Future<void> _useCurrentLocationAsBusinessLocation() async {
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatieservices zijn uitgeschakeld op dit toestel.',
                en: 'Location services are disabled on this device.',
                fr: 'Les services de localisation sont désactivés sur cet appareil.',
                es: 'Los servicios de ubicación están desactivados en este dispositivo.',
              ),
            ),
          ),
        );
        return;
      }
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang geweigerd.',
                en: 'Location access denied.',
                fr: 'Accès à la localisation refusé.',
                es: 'Acceso a la ubicación denegado.',
              ),
            ),
          ),
        );
        return;
      }
      if (permission == geo.LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang permanent geweigerd. Schakel toestemming in via instellingen.',
                en: 'Location access is permanently denied. Enable permission in settings.',
                fr: 'L’accès à la localisation est refusé définitivement. Activez l’autorisation dans les paramètres.',
                es: 'El acceso a la ubicación está denegado permanentemente. Activa el permiso en la configuración.',
              ),
            ),
          ),
        );
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      final local =
          localBackendBusinessProfileNotifier.value ??
          mergeLocalIntoBackendPreview(
            BackendBusinessProfile.defaults(),
            companyProfileNotifier.value,
          );
      final updated = BackendBusinessProfile(
        companyName: local.companyName,
        legalName: local.legalName,
        vatNumber: local.vatNumber,
        companyRegistrationNumber: local.companyRegistrationNumber,
        address: local.address,
        postcode: local.postcode,
        city: local.city,
        country: local.country,
        phone: local.phone,
        email: local.email,
        website: local.website,
        bookingEmail: local.bookingEmail,
        publicLogoUrl: local.publicLogoUrl,
        publicHeroPhotoUrl: local.publicHeroPhotoUrl,
        publicServedPostcodes: local.publicServedPostcodes,
        publicCoverageLat: pos.latitude.toStringAsFixed(6),
        publicCoverageLng: pos.longitude.toStringAsFixed(6),
        publicServiceRadiusKm: local.publicServiceRadiusKm,
        publicPaymentOptions: local.publicPaymentOptions,
        publicPartnerProfilePublishedAt: local.publicPartnerProfilePublishedAt,
        publicPartnerProfilePublishStatus:
            local.publicPartnerProfilePublishStatus,
        invoiceEmail: local.invoiceEmail,
        iban: local.iban,
        paymentReferencePrefix: local.paymentReferencePrefix,
        invoiceReceiptFooterText: local.invoiceReceiptFooterText,
      );

      await updateLocalBackendBusinessProfileCache(updated);
      final scope = _activeDemandScope();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_DEMAND_SCOPE][BLOCK] reason=missing_strict_company_scope action=save_backend_business_profile',
        );
      } else {
        try {
          final saved = await saveBackendBusinessProfile(
            updated,
            tenantId: scope.tenantId,
            companyId: scope.companyId,
          );
          final merged = _mergeDemandProfile(local: updated, server: saved);
          await updateLocalBackendBusinessProfileCache(merged);
        } catch (_) {
          // Local cache already updated; continue with local-first UX.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Bedrijfslocatie ingesteld. Vraagradar wordt vernieuwd.',
              en: 'Business location set. Demand radar is refreshing.',
              fr: 'Emplacement professionnel défini. Le radar de demande se met à jour.',
              es: 'Ubicación de empresa configurada. El radar de demanda se está actualizando.',
            ),
          ),
        ),
      );
      await _loadDemand();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Huidige locatie kon niet worden ingesteld als bedrijfslocatie.',
              en: 'Could not set current location as business location.',
              fr: 'Impossible de définir la position actuelle comme emplacement d’entreprise.',
              es: 'No se pudo establecer la ubicación actual como ubicación de empresa.',
            ),
          ),
        ),
      );
    }
  }

  bool get _hasCoverageCenter =>
      _coverageLat != null &&
      _coverageLng != null &&
      _coverageLat! >= -90 &&
      _coverageLat! <= 90 &&
      _coverageLng! >= -180 &&
      _coverageLng! <= 180;

  bool get _canRenderCoverageMap =>
      _hasCoverageCenter && kMapboxToken.trim().isNotEmpty;

  double _mapZoomForRadius(double radiusKm) {
    final r = radiusKm <= 0 ? 8.0 : radiusKm;
    if (r >= 60) return 8.7;
    if (r >= 35) return 9.4;
    if (r >= 20) return 10.2;
    if (r >= 12) return 10.8;
    if (r >= 7) return 11.4;
    return 12.1;
  }

  List<mb.Position> _circlePositions({
    required double lat,
    required double lng,
    required double radiusKm,
    int points = 72,
  }) {
    final safeRadiusKm = radiusKm <= 0 ? 8.0 : radiusKm;
    const earthRadiusKm = 6371.0;
    final latRad = lat * math.pi / 180.0;
    final lngRad = lng * math.pi / 180.0;
    final angularDistance = safeRadiusKm / earthRadiusKm;
    final out = <mb.Position>[];
    for (var i = 0; i <= points; i++) {
      final bearing = (2 * math.pi * i) / points;
      final sinLat = math.sin(latRad);
      final cosLat = math.cos(latRad);
      final sinAd = math.sin(angularDistance);
      final cosAd = math.cos(angularDistance);
      final sinLat2 = sinLat * cosAd + cosLat * sinAd * math.cos(bearing);
      final lat2 = math.asin(sinLat2);
      final y = math.sin(bearing) * sinAd * cosLat;
      final x = cosAd - sinLat * sinLat2;
      final lng2 = lngRad + math.atan2(y, x);
      out.add(mb.Position(lng2 * 180.0 / math.pi, lat2 * 180.0 / math.pi));
    }
    return out;
  }

  Future<void> _renderCoverageOverlay() async {
    final map = _coverageMap;
    if (map == null || !_hasCoverageCenter) return;
    final lat = _coverageLat!;
    final lng = _coverageLng!;
    final radiusKm = _coverageRadiusKm;
    final center = mb.Point(coordinates: mb.Position(lng, lat));
    await map.flyTo(
      mb.CameraOptions(center: center, zoom: _mapZoomForRadius(radiusKm)),
      mb.MapAnimationOptions(duration: 450),
    );

    _coverageCenterManager ??= await map.annotations
        .createPointAnnotationManager();
    _coverageRadiusManager ??= await map.annotations
        .createPolylineAnnotationManager();
    try {
      await _coverageCenterManager!.deleteAll();
      await _coverageRadiusManager!.deleteAll();
    } catch (_) {
      // Best-effort overlay refresh.
    }
    await _coverageCenterManager!.create(
      mb.PointAnnotationOptions(
        geometry: center,
        iconColor: const Color(0xFF34D29A).value,
        iconSize: 0.95,
      ),
    );

    final ring = _circlePositions(lat: lat, lng: lng, radiusKm: radiusKm);
    await _coverageRadiusManager!.create(
      mb.PolylineAnnotationOptions(
        geometry: mb.LineString(coordinates: ring),
        lineColor: _businessThemePalette.accent.value,
        lineWidth: 2.2,
        lineOpacity: 0.82,
      ),
    );
  }

  Future<void> _onCoverageMapCreated(mb.MapboxMap mapboxMap) async {
    _coverageMap = mapboxMap;
    await _renderCoverageOverlay();
  }

  Future<_BusinessRegionalDemandRow> _fetchPostcodeDemand({
    required String country,
    required String postcode,
    required String correlationId,
    required int radiusKm,
    String? companyId,
  }) async {
    final normalizedPostcode = _normalizePostcode(postcode);
    final uri = Uri.parse(
      '$kBookingBaseUrl/region-interest/radar'
      '?country=${Uri.encodeQueryComponent(country)}'
      '&postcode=${Uri.encodeQueryComponent(normalizedPostcode)}',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      debugPrint(
        formatDemandRadarDiag(
          correlationId: correlationId,
          country: country,
          postcode: normalizedPostcode,
          radiusKm: radiusKm,
          httpStatus: res.statusCode,
          source: res.statusCode >= 200 && res.statusCode < 300
              ? DemandRadarCountSource.network
              : DemandRadarCountSource.unavailable,
          cacheHit: false,
          companyId: companyId,
        ),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return _BusinessRegionalDemandRow(
          postcode: normalizedPostcode,
          displayCount: demandRadarRowDisplayCount(
            unavailable: true,
            count: 0,
            languageCode: currentLanguageCode,
          ),
          count: 0,
          status: '',
          unavailable: true,
        );
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        return _BusinessRegionalDemandRow(
          postcode: normalizedPostcode,
          displayCount: demandRadarRowDisplayCount(
            unavailable: true,
            count: 0,
            languageCode: currentLanguageCode,
          ),
          count: 0,
          status: '',
          unavailable: true,
        );
      }
      final count = _asInt(decoded['count']) ?? 0;
      final rawDisplay = (decoded['display_count'] ?? '').toString().trim();
      final status = (decoded['status'] ?? '').toString().trim();
      return _BusinessRegionalDemandRow(
        postcode: normalizedPostcode,
        displayCount: demandRadarRowDisplayCount(
          unavailable: false,
          count: count,
          languageCode: currentLanguageCode,
          serverDisplayCount: rawDisplay,
        ),
        count: count,
        status: status,
        unavailable: false,
      );
    } catch (_) {
      debugPrint(
        formatDemandRadarDiag(
          correlationId: correlationId,
          country: country,
          postcode: normalizedPostcode,
          radiusKm: radiusKm,
          httpStatus: null,
          source: DemandRadarCountSource.unavailable,
          cacheHit: false,
          companyId: companyId,
        ),
      );
      return _BusinessRegionalDemandRow(
        postcode: normalizedPostcode,
        displayCount: demandRadarRowDisplayCount(
          unavailable: true,
          count: 0,
          languageCode: currentLanguageCode,
        ),
        count: 0,
        status: '',
        unavailable: true,
      );
    }
  }

  Future<void> _loadDemand() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final correlationId =
        'dr_${DateTime.now().millisecondsSinceEpoch}_$generation';
    final scope = _activeDemandScope();
    final companyId = scope?.companyId;
    // Company switch: drop previous session rows so tenant A cache cannot
    // paint tenant B's radar.
    if (_boundCompanyId != null &&
        companyId != null &&
        _boundCompanyId != companyId) {
      _rows = const <_BusinessRegionalDemandRow>[];
      _postcodes = const <String>[];
      _totalCount = 0;
      _totalUnavailable = true;
    }
    _boundCompanyId = companyId;

    setState(() {
      _loading = true;
    });

    final company = companyProfileNotifier.value;
    final localFallback =
        localBackendBusinessProfileNotifier.value ??
        mergeLocalIntoBackendPreview(
          BackendBusinessProfile.defaults(),
          companyProfileNotifier.value,
        );
    BackendBusinessProfile backend = localFallback;
    if (scope == null) {
      debugPrint(
        '[BUSINESS_DEMAND_SCOPE][BLOCK] reason=missing_strict_company_scope action=fetch_backend_business_profile',
      );
    } else {
      try {
        final server = await fetchBackendBusinessProfile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
        if (!mounted || generation != _loadGeneration) return;
        backend = _mergeDemandProfile(local: localFallback, server: server);
        unawaited(updateLocalBackendBusinessProfileCache(backend));
      } catch (_) {
        // Keep local fallback only.
      }
    }

    final primary = _normalizePostcode(
      (company?.postalCode ?? '').trim().isNotEmpty
          ? company!.postalCode
          : backend.postcode,
    );
    final country = _normalizeCountry(
      (company?.countryCode ?? '').trim().isNotEmpty
          ? company!.countryCode
          : backend.country,
    );
    final city = (company?.city ?? '').trim().isNotEmpty
        ? company!.city.trim()
        : backend.city.trim();
    final radius = backend.publicServiceRadiusKm.trim();
    final coverageLat = _asDouble(backend.publicCoverageLat);
    final coverageLng = _asDouble(backend.publicCoverageLng);
    final coverageRadiusKm = (_asDouble(radius) ?? 8.0).clamp(1.0, 100.0);
    debugPrint(
      '[VRAAGRADAR_MAP] lat=${coverageLat?.toStringAsFixed(6) ?? 'null'}',
    );
    debugPrint(
      '[VRAAGRADAR_MAP] lng=${coverageLng?.toStringAsFixed(6) ?? 'null'}',
    );
    debugPrint(
      '[VRAAGRADAR_MAP] radius=${coverageRadiusKm.toStringAsFixed(1)}',
    );
    final limitedPostcodes = buildDemandRadarPostcodeQueryList(
      primaryRaw: primary,
      servedRaw: backend.publicServedPostcodes,
    );
    debugPrint(
      '[DEMAND_RADAR_DIAG] corr=$correlationId '
      'cache_key=${demandRadarRegionCacheKey(country: country, postcode: primary, radiusKm: coverageRadiusKm.round())} '
      'tenant=${maskDemandRadarTenantId(companyId ?? '')}',
    );

    List<_BusinessRegionalDemandRow> rows =
        const <_BusinessRegionalDemandRow>[];
    if (limitedPostcodes.isNotEmpty) {
      final fetched = await Future.wait(
        limitedPostcodes.map(
          (postcode) => _fetchPostcodeDemand(
            country: country,
            postcode: postcode,
            correlationId: correlationId,
            radiusKm: coverageRadiusKm.round(),
            companyId: companyId,
          ),
        ),
      );
      if (!mounted || generation != _loadGeneration) return;
      final indexed = fetched
          .asMap()
          .entries
          .map((entry) => (idx: entry.key, row: entry.value))
          .toList(growable: false);
      indexed.sort((a, b) {
        final byCount = b.row.count.compareTo(a.row.count);
        if (byCount != 0) return byCount;
        if (a.row.postcode == primary) return -1;
        if (b.row.postcode == primary) return 1;
        return a.idx.compareTo(b.idx);
      });
      rows = indexed.map((e) => e.row).toList(growable: false);
    }
    if (!mounted || generation != _loadGeneration) return;

    final hero = decideDemandRadarHeroTotal(
      primaryPostcode: primary,
      rows: rows
          .map(
            (row) => (
              postcode: row.postcode,
              count: row.count,
              unavailable: row.unavailable,
            ),
          )
          .toList(growable: false),
    );

    setState(() {
      _country = country;
      _city = city;
      _primaryPostcode = primary;
      _serviceRadiusKm = radius;
      _coverageLat = coverageLat;
      _coverageLng = coverageLng;
      _coverageRadiusKm = coverageRadiusKm;
      _postcodes = limitedPostcodes;
      _rows = rows;
      _totalCount = hero.count;
      _totalUnavailable = !hero.available;
      _loading = false;
    });
    unawaited(_renderCoverageOverlay());
  }

  Widget _panel({required Widget child, EdgeInsetsGeometry? padding}) {
    final palette = _businessThemePalette;
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.isDark
              ? <Color>[palette.surface, palette.background, palette.background]
              : <Color>[palette.surface, palette.surfaceAlt, palette.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.border.withOpacity(palette.isDark ? 0.7 : 0.92),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withOpacity(palette.isDark ? 0.07 : 0.03),
            blurRadius: 12,
            spreadRadius: 0.2,
          ),
          BoxShadow(
            color: palette.shadow.withOpacity(palette.isDark ? 0.52 : 0.24),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, themeVariant, __) {
        final palette = paletteForBusinessTheme(themeVariant);
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: appLanguageNotifier,
          builder: (context, _, __) => Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              backgroundColor: palette.background,
              foregroundColor: palette.textPrimary,
              title: Text(
                _t(
                  nl: 'Vraagradar',
                  en: 'Demand radar',
                  fr: 'Radar demande',
                  es: 'Radar demanda',
                ),
              ),
              actions: [
                IconButton(
                  tooltip: _t(
                    nl: 'Vernieuwen',
                    en: 'Refresh',
                    fr: 'Actualiser',
                    es: 'Actualizar',
                  ),
                  onPressed: _loading ? null : _loadDemand,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            nl: 'Vraag in jouw regio',
                            en: 'Demand in your area',
                            fr: 'Demande dans votre région',
                            es: 'Demanda en tu zona',
                          ),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 17.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.surfaceAlt,
                                border: Border.all(
                                  color: palette.accent.withOpacity(0.52),
                                ),
                              ),
                              child: Icon(
                                Icons.radar_rounded,
                                color: palette.accent.withOpacity(0.98),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _loading ? '…' : _totalDisplayCount(),
                                    style: TextStyle(
                                      color: _totalUnavailable
                                          ? palette.textSecondary.withOpacity(
                                              0.92,
                                            )
                                          : palette.accent.withOpacity(0.98),
                                      fontWeight: FontWeight.w900,
                                      fontSize: _totalUnavailable ? 15 : 29,
                                    ),
                                  ),
                                  if (!_totalUnavailable)
                                    Text(
                                      _t(
                                        nl: 'potentiële klanten',
                                        en: 'potential customers',
                                        fr: 'clients potentiels',
                                        es: 'clientes potenciales',
                                      ),
                                      style: TextStyle(
                                        color: palette.textSecondary
                                            .withOpacity(0.92),
                                        fontSize: 11.8,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: palette.accent.withOpacity(
                                  palette.isDark ? 0.12 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: palette.accent.withOpacity(0.44),
                                ),
                              ),
                              child: Text(
                                _locationLabel(),
                                style: TextStyle(
                                  color: palette.accent.withOpacity(0.98),
                                  fontSize: 10.7,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_serviceRadiusKm.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _t(
                              nl: 'Service radius: $_serviceRadiusKm km (context, geen postcode-generator).',
                              en: 'Service radius: $_serviceRadiusKm km (context only, no postcode generator).',
                              fr: 'Rayon de service : $_serviceRadiusKm km (contexte uniquement, sans générateur de codes postaux).',
                              es: 'Radio de servicio: $_serviceRadiusKm km (solo contexto, sin generador de códigos postales).',
                            ),
                            style: TextStyle(
                              color: palette.textMuted.withOpacity(0.92),
                              fontSize: 10.8,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            nl: 'Alleen geaggregeerde en anonieme regionale interesse wordt getoond.',
                            en: 'Only aggregated and anonymous regional interest is shown.',
                            fr: 'Seul l’intérêt régional agrégé et anonyme est affiché.',
                            es: 'Solo se muestra interés regional agregado y anónimo.',
                          ),
                          style: TextStyle(
                            color: palette.textMuted.withOpacity(0.88),
                            fontSize: 10.9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.map_outlined,
                              color: palette.accent.withOpacity(0.95),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _t(
                                nl: 'Regionale kaart',
                                en: 'Regional map',
                                fr: 'Carte régionale',
                                es: 'Mapa regional',
                              ),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_canRenderCoverageMap)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 228,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  mb.MapWidget(
                                    key: ValueKey<String>(
                                      'business_demand_map_$_coverageLat$_coverageLng$_coverageRadiusKm',
                                    ),
                                    textureView: true,
                                    androidHostingMode:
                                        mb.AndroidPlatformViewHostingMode.HC,
                                    styleUri:
                                        'mapbox://styles/mapbox/navigation-night-v1',
                                    cameraOptions: mb.CameraOptions(
                                      center: mb.Point(
                                        coordinates: mb.Position(
                                          _coverageLng!,
                                          _coverageLat!,
                                        ),
                                      ),
                                      zoom: _mapZoomForRadius(
                                        _coverageRadiusKm,
                                      ),
                                    ),
                                    onMapCreated: _onCoverageMapCreated,
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter:
                                            _BusinessDemandMapOverlayPainter(
                                              totalDemand: _totalCount,
                                              demandColor: palette.accent,
                                              centerColor: palette.success,
                                            ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: IgnorePointer(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.isDark
                                              ? Colors.black.withOpacity(0.52)
                                              : palette.background.withOpacity(
                                                  0.74,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: palette.accent.withOpacity(
                                              0.34,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _t(
                                            nl: 'Geaggregeerde vraag',
                                            en: 'Aggregated demand',
                                            fr: 'Demande agrégée',
                                            es: 'Demanda agregada',
                                          ),
                                          style: TextStyle(
                                            color: palette.textPrimary
                                                .withOpacity(0.94),
                                            fontSize: 10.3,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 168,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: palette.surfaceAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: palette.accent.withOpacity(0.26),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _RegionRadarPainter(
                                      customerColor: palette.accent.withOpacity(
                                        0.95,
                                      ),
                                      partnerColor: palette.success,
                                      showPartnerOpportunity: true,
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _hasCoverageCenter
                                              ? _t(
                                                  nl: 'Mapbox-token ontbreekt. Configureer de kaarttoegang om de kaart te tonen.',
                                                  en: 'Mapbox token is missing. Configure map access to show the map.',
                                                  fr: 'Le jeton Mapbox manque. Configurez l’accès carte pour afficher la carte.',
                                                  es: 'Falta el token de Mapbox. Configura el acceso al mapa para mostrarlo.',
                                                )
                                              : _t(
                                                  nl: 'Stel je bedrijfslocatie in om de kaart te tonen.',
                                                  en: 'Set your business location to show the map.',
                                                  fr: 'Définissez l’emplacement de votre entreprise pour afficher la carte.',
                                                  es: 'Configura la ubicación de tu empresa para mostrar el mapa.',
                                                ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: palette.textSecondary
                                                .withOpacity(0.92),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.1,
                                          ),
                                        ),
                                        if (!_hasCoverageCenter) ...[
                                          const SizedBox(height: 10),
                                          OutlinedButton.icon(
                                            onPressed:
                                                _useCurrentLocationAsBusinessLocation,
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: palette.accent
                                                  .withOpacity(0.98),
                                              side: BorderSide(
                                                color: palette.accent
                                                    .withOpacity(0.44),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.my_location_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              _t(
                                                nl: 'Gebruik huidige locatie als bedrijfslocatie',
                                                en: 'Use current location as business location',
                                                fr: 'Utiliser ma position actuelle comme emplacement d’entreprise',
                                                es: 'Usar ubicación actual como ubicación de empresa',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      const BusinessSettingsPage(),
                                                ),
                                              );
                                            },
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: palette
                                                  .textSecondary
                                                  .withOpacity(0.92),
                                              side: BorderSide(
                                                color: palette.border
                                                    .withOpacity(0.22),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.settings_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              _t(
                                                nl: 'Bedrijfslocatie instellen',
                                                en: 'Set business location',
                                                fr: 'Définir l’emplacement',
                                                es: 'Configurar ubicación',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 7),
                        Text(
                          _t(
                            nl: 'Kaart toont alleen geaggregeerde regio-indicatie en servicebereik.',
                            en: 'Map shows only aggregated regional indication and service range.',
                            fr: 'La carte affiche uniquement une indication régionale agrégée et la zone de service.',
                            es: 'El mapa solo muestra una indicación regional agregada y el rango de servicio.',
                          ),
                          style: TextStyle(
                            color: palette.textMuted.withOpacity(0.86),
                            fontSize: 10.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette.accent.withOpacity(0.96),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _t(
                                  nl: 'Postcode-niveau vraag (geaggregeerd)',
                                  en: 'Postcode-level demand (aggregated)',
                                  fr: 'Demande par code postal (agrégée)',
                                  es: 'Demanda por código postal (agregada)',
                                ),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_postcodes.isEmpty)
                          Text(
                            _t(
                              nl: 'Voeg je bedrijfsregio toe om lokale vraag te zien.',
                              en: 'Add your business area to see local demand.',
                              fr: 'Ajoutez votre région d’activité pour voir la demande locale.',
                              es: 'Añade tu zona de actividad para ver la demanda local.',
                            ),
                            style: TextStyle(
                              color: palette.textSecondary.withOpacity(0.92),
                              fontSize: 12.0,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (_rows.isEmpty && _loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          Column(
                            children: _rows
                                .map(
                                  (row) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.surfaceAlt,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: palette.accent.withOpacity(0.24),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          color: palette.accent.withOpacity(
                                            0.95,
                                          ),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            row.postcode,
                                            style: TextStyle(
                                              color: palette.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.1,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          row.unavailable
                                              ? demandRadarUnavailableLabel(
                                                  currentLanguageCode,
                                                )
                                              : row.displayCount,
                                          style: TextStyle(
                                            color: row.unavailable
                                                ? palette.textMuted.withOpacity(
                                                    0.92,
                                                  )
                                                : palette.accent.withOpacity(
                                                    0.98,
                                                  ),
                                            fontWeight: FontWeight.w800,
                                            fontSize: row.unavailable
                                                ? 11.2
                                                : 14.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        if (_postcodes.length >= 50) ...[
                          const SizedBox(height: 4),
                          Text(
                            _t(
                              nl: 'Toont de eerste 50 postcodes om requests beperkt te houden.',
                              en: 'Showing the first 50 postcodes to keep requests bounded.',
                              fr: 'Affiche les 50 premiers codes postaux pour limiter les requêtes.',
                              es: 'Mostrando los primeros 50 códigos postales para limitar solicitudes.',
                            ),
                            style: TextStyle(
                              color: palette.textMuted.withOpacity(0.84),
                              fontSize: 10.8,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            nl: 'Landcontext: $_country',
                            en: 'Country context: $_country',
                            fr: 'Contexte pays : $_country',
                            es: 'Contexto de país: $_country',
                          ),
                          style: TextStyle(
                            color: palette.textMuted.withOpacity(0.84),
                            fontSize: 10.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BusinessRegionalDemandRow {
  const _BusinessRegionalDemandRow({
    required this.postcode,
    required this.displayCount,
    required this.count,
    required this.status,
    required this.unavailable,
  });

  final String postcode;
  final String displayCount;
  final int count;
  final String status;
  final bool unavailable;
}
