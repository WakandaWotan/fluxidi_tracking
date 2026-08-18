import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_address_lookup.dart';
import 'limousine_current_location.dart';
import 'limousine_p2d4c1a_ux.dart';

const LocalizedText kLimousineAddressHint = LocalizedText(
  nl: 'Begin te typen voor adresvoorstellen',
  en: 'Start typing for address suggestions',
  fr: 'Commencez à taper pour voir des suggestions',
  es: 'Empiece a escribir para ver sugerencias',
);

const LocalizedText kLimousineAddressLoading = LocalizedText(
  nl: 'Adressen zoeken…',
  en: 'Searching addresses…',
  fr: 'Recherche d’adresses…',
  es: 'Buscando direcciones…',
);

const LocalizedText kLimousineAddressNoResult = LocalizedText(
  nl: 'Geen adres gevonden. Kies een voorstel of vervolledig het adres.',
  en: 'No address found. Pick a suggestion or complete the address.',
  fr: 'Aucune adresse trouvée. Choisissez une suggestion ou complétez l’adresse.',
  es: 'No se encontró ninguna dirección. Elija una sugerencia o complete la dirección.',
);

const LocalizedText kLimousineAddressRetry = LocalizedText(
  nl: 'Opnieuw zoeken',
  en: 'Search again',
  fr: 'Réessayer',
  es: 'Buscar de nuevo',
);

const LocalizedText kLimousineAddressManualFallback = LocalizedText(
  nl: 'Gebruik dit adres',
  en: 'Use this address',
  fr: 'Utiliser cette adresse',
  es: 'Usar esta dirección',
);

const LocalizedText kLimousineAddressClear = LocalizedText(
  nl: 'Wissen',
  en: 'Clear',
  fr: 'Effacer',
  es: 'Borrar',
);

const LocalizedText kLimousineAddressUnavailable = LocalizedText(
  nl: 'Adres zoeken lukt even niet. Controleer je verbinding of bevestig een volledig adres.',
  en: 'Address search is temporarily unavailable. Check your connection or confirm a complete address.',
  fr: 'La recherche d’adresse est temporairement indisponible. Vérifiez votre connexion ou confirmez une adresse complète.',
  es: 'La búsqueda de direcciones no está disponible temporalmente. Comprueba tu conexión o confirma una dirección completa.',
);

Key limousineAddressFieldKey(String id) =>
    ValueKey<String>('limousine_address_field_$id');

Key limousineAddressInputKey(String id) =>
    ValueKey<String>('limousine_address_input_$id');

Key limousineAddressSuggestionsKey(String id) =>
    ValueKey<String>('limousine_address_suggestions_$id');

Key limousineAddressSuggestionKey(String id, int index) =>
    ValueKey<String>('limousine_address_suggestion_${id}_$index');

Key limousineAddressLoadingKey(String id) =>
    ValueKey<String>('limousine_address_loading_$id');

Key limousineAddressNoResultKey(String id) =>
    ValueKey<String>('limousine_address_no_result_$id');

Key limousineAddressRetryKey(String id) =>
    ValueKey<String>('limousine_address_retry_$id');

Key limousineAddressManualKey(String id) =>
    ValueKey<String>('limousine_address_manual_$id');

Key limousineAddressClearKey(String id) =>
    ValueKey<String>('limousine_address_clear_$id');

Key limousineAddressCurrentLocationKey(String id) =>
    ValueKey<String>('limousine_address_current_location_$id');

Key limousineAddressCurrentLocationLoadingKey(String id) =>
    ValueKey<String>('limousine_address_current_location_loading_$id');

Key limousineAddressCurrentLocationErrorKey(String id) =>
    ValueKey<String>('limousine_address_current_location_error_$id');

Key limousineAddressOpenSettingsKey(String id) =>
    ValueKey<String>('limousine_address_open_settings_$id');

class LimousineAddressFieldController extends ChangeNotifier {
  LimousineAddressFieldController({
    required this.lookup,
    required this.fieldId,
    this.language = 'nl',
    this.debounce = kLimousineAddressDebounce,
    this.currentLocation,
  });

  final LimousinePlaceLookup lookup;
  final String fieldId;
  String language;
  final Duration debounce;
  LimousineCurrentLocationResolver? currentLocation;
  final TextEditingController textController = TextEditingController();

  Timer? _debounce;
  int _requestId = 0;
  bool _disposed = false;
  bool loading = false;
  bool searched = false;
  bool hadError = false;
  bool resolvingCurrentLocation = false;
  LimousineCurrentLocationFailure? currentLocationFailure;
  List<LimousinePlaceSuggestion> suggestions = const [];
  LimousineAddressValue value = const LimousineAddressValue();

  bool get isRouteReady => value.isRouteReady;

  void seedText(String raw, {bool acceptApprovedDraft = false}) {
    final text = raw.trim();
    textController.value = TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    );
    if (text.isEmpty) {
      value = const LimousineAddressValue();
    } else if (acceptApprovedDraft &&
        !limousineAddressLooksLikeIncompleteFragment(text)) {
      value = LimousineAddressValue(
        displayText: text,
        canonicalLabel: text,
        acceptance: LimousineAddressAcceptance.manualFallback,
      );
    } else {
      value = LimousineAddressValue(
        displayText: text,
        acceptance: LimousineAddressAcceptance.incomplete,
      );
    }
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = false;
    currentLocationFailure = null;
    notifyListeners();
  }

  void acceptCopy(LimousineAddressValue other) {
    final text = other.routeText;
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    value = LimousineAddressValue(
      displayText: text,
      canonicalLabel: other.canonicalLabel.trim().isEmpty
          ? text
          : other.canonicalLabel,
      lat: other.lat,
      lon: other.lon,
      placeId: other.placeId,
      acceptance: other.acceptance,
      fromCurrentLocation: other.fromCurrentLocation,
    );
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = false;
    currentLocationFailure = null;
    notifyListeners();
  }

  void onTextChanged(String raw) {
    _debounce?.cancel();
    final requestId = ++_requestId;
    currentLocationFailure = null;
    final text = raw;
    if (value.isRouteReady) {
      value = LimousineAddressValue(
        displayText: text,
        acceptance: text.trim().isEmpty
            ? LimousineAddressAcceptance.empty
            : LimousineAddressAcceptance.incomplete,
      );
    } else {
      value = LimousineAddressValue(
        displayText: text,
        acceptance: text.trim().isEmpty
            ? LimousineAddressAcceptance.empty
            : LimousineAddressAcceptance.incomplete,
      );
    }
    if (text.trim().length < kLimousineAddressMinQueryLength) {
      loading = false;
      searched = false;
      hadError = false;
      suggestions = const [];
      notifyListeners();
      return;
    }
    notifyListeners();
    _debounce = Timer(debounce, () {
      unawaited(_runSearch(text, requestId));
    });
  }

  Future<void> retry() => _runSearch(textController.text, ++_requestId);

  Future<void> _runSearch(String raw, int requestId) async {
    if (raw.trim().length < kLimousineAddressMinQueryLength) return;
    loading = true;
    searched = true;
    notifyListeners();
    final result = await lookup.search(raw, language: language);
    if (requestId != _requestId || textController.text.trim() != raw.trim()) {
      return;
    }
    loading = false;
    hadError = result.hadError;
    suggestions = result.suggestions;
    notifyListeners();
  }

  void selectSuggestion(
    LimousinePlaceSuggestion suggestion, {
    bool fromCurrentLocation = false,
  }) {
    _debounce?.cancel();
    _requestId += 1;
    textController.value = TextEditingValue(
      text: suggestion.label,
      selection: TextSelection.collapsed(offset: suggestion.label.length),
    );
    value = LimousineAddressValue(
      displayText: suggestion.label,
      canonicalLabel: suggestion.label,
      lat: suggestion.lat,
      lon: suggestion.lon,
      placeId: suggestion.placeId,
      acceptance: LimousineAddressAcceptance.selected,
      fromCurrentLocation: fromCurrentLocation,
    );
    suggestions = const [];
    loading = false;
    searched = false;
    hadError = false;
    currentLocationFailure = null;
    notifyListeners();
  }

  bool confirmManualFallback() {
    final text = textController.text.trim();
    if (!limousineAddressAllowsManualFallback(text)) return false;
    _debounce?.cancel();
    _requestId += 1;
    value = LimousineAddressValue(
      displayText: text,
      canonicalLabel: text,
      acceptance: LimousineAddressAcceptance.manualFallback,
    );
    suggestions = const [];
    loading = false;
    searched = false;
    hadError = false;
    currentLocationFailure = null;
    notifyListeners();
    return true;
  }

  void clear() {
    _debounce?.cancel();
    _requestId += 1;
    textController.clear();
    value = const LimousineAddressValue();
    suggestions = const [];
    loading = false;
    searched = false;
    hadError = false;
    currentLocationFailure = null;
    notifyListeners();
  }

  Future<void> useCurrentLocation() async {
    final resolver = currentLocation;
    if (resolver == null || resolvingCurrentLocation) return;
    _debounce?.cancel();
    _requestId += 1;
    resolvingCurrentLocation = true;
    currentLocationFailure = null;
    suggestions = const [];
    loading = false;
    searched = false;
    _emit();
    try {
      final suggestion = await resolver.resolve(language: language);
      if (_disposed) return;
      if (suggestion == null) return;
      selectSuggestion(suggestion, fromCurrentLocation: true);
    } on LimousineCurrentLocationException catch (error) {
      if (_disposed) return;
      currentLocationFailure = error.failure;
    } finally {
      resolvingCurrentLocation = false;
      _emit();
    }
  }

  Future<void> openAppSettings() async {
    await currentLocation?.openAppSettings();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    textController.dispose();
    super.dispose();
  }
}

class LimousineAddressField extends StatelessWidget {
  const LimousineAddressField({
    super.key,
    required this.controller,
    required this.label,
    required this.tokens,
    required this.language,
    this.showCurrentLocation = false,
  });

  final LimousineAddressFieldController controller;
  final String label;
  final LimousineUxTokens tokens;
  final AppLanguage language;
  final bool showCurrentLocation;

  String _t(LocalizedText text) => text.of(language);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ready = controller.isRouteReady;
        final showManual =
            !ready &&
            (controller.hadError ||
                (controller.searched &&
                    !controller.loading &&
                    controller.suggestions.isEmpty)) &&
            limousineAddressAllowsManualFallback(
              controller.textController.text,
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            key: limousineAddressFieldKey(controller.fieldId),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: limousineAddressInputKey(controller.fieldId),
                controller: controller.textController,
                style: TextStyle(color: tokens.onSurface),
                scrollPadding: const EdgeInsets.only(bottom: 220),
                keyboardType: TextInputType.streetAddress,
                textInputAction: TextInputAction.next,
                onChanged: controller.onTextChanged,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: _t(kLimousineAddressHint),
                  hintStyle: TextStyle(color: tokens.muted),
                  filled: true,
                  fillColor: tokens.fieldFill,
                  suffixIcon: _suffix(controller),
                  suffixIconConstraints: _suffixConstraints(controller),
                ),
              ),
              if (ready)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    controller.value.routeText,
                    style: TextStyle(
                      color: tokens.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (controller.resolvingCurrentLocation)
                Padding(
                  key: limousineAddressCurrentLocationLoadingKey(
                    controller.fieldId,
                  ),
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        color: tokens.gold,
                        backgroundColor: tokens.border,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(kLimousineCurrentLocationLoading),
                        style: TextStyle(color: tokens.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              if (controller.currentLocationFailure != null)
                Padding(
                  key: limousineAddressCurrentLocationErrorKey(
                    controller.fieldId,
                  ),
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          limousineCurrentLocationMessage(
                            controller.currentLocationFailure!,
                          ),
                        ),
                        style: TextStyle(color: tokens.muted, fontSize: 12.5),
                      ),
                      if (controller.currentLocationFailure ==
                          LimousineCurrentLocationFailure
                              .permissionPermanentlyDenied)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: limousineAddressOpenSettingsKey(
                              controller.fieldId,
                            ),
                            onPressed: controller.openAppSettings,
                            child: Text(
                              _t(kLimousineCurrentLocationOpenSettings),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (controller.loading && !controller.resolvingCurrentLocation)
                Padding(
                  key: limousineAddressLoadingKey(controller.fieldId),
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        color: tokens.gold,
                        backgroundColor: tokens.border,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(kLimousineAddressLoading),
                        style: TextStyle(color: tokens.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              if (controller.suggestions.isNotEmpty)
                Container(
                  key: limousineAddressSuggestionsKey(controller.fieldId),
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    border: Border.all(color: tokens.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: controller.suggestions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: tokens.border),
                    itemBuilder: (context, index) {
                      final suggestion = controller.suggestions[index];
                      return ListTile(
                        key: limousineAddressSuggestionKey(
                          controller.fieldId,
                          index,
                        ),
                        dense: true,
                        title: Text(
                          suggestion.label,
                          style: TextStyle(color: tokens.onSurface),
                        ),
                        onTap: () => controller.selectSuggestion(suggestion),
                      );
                    },
                  ),
                ),
              if (!controller.loading &&
                  controller.searched &&
                  controller.suggestions.isEmpty)
                Padding(
                  key: limousineAddressNoResultKey(controller.fieldId),
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.hadError
                        ? _t(kLimousineAddressUnavailable)
                        : _t(kLimousineAddressNoResult),
                    style: TextStyle(color: tokens.muted, fontSize: 12.5),
                  ),
                ),
              if (controller.hadError ||
                  (controller.searched &&
                      !controller.loading &&
                      controller.suggestions.isEmpty))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: limousineAddressRetryKey(controller.fieldId),
                    onPressed: controller.retry,
                    child: Text(_t(kLimousineAddressRetry)),
                  ),
                ),
              if (showManual)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: limousineAddressManualKey(controller.fieldId),
                    onPressed: controller.confirmManualFallback,
                    child: Text(_t(kLimousineAddressManualFallback)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  BoxConstraints? _suffixConstraints(
    LimousineAddressFieldController controller,
  ) {
    final showClear = controller.textController.text.isNotEmpty;
    if (!showCurrentLocation && !showClear) return null;
    final count = (showCurrentLocation ? 1 : 0) + (showClear ? 1 : 0);
    return BoxConstraints(minHeight: 48, minWidth: 48.0 * count);
  }

  Widget? _suffix(LimousineAddressFieldController controller) {
    final showClear = controller.textController.text.isNotEmpty;
    if (!showCurrentLocation && !showClear) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCurrentLocation)
          IconButton(
            key: limousineAddressCurrentLocationKey(controller.fieldId),
            tooltip: _t(kLimousineCurrentLocationTooltip),
            onPressed: controller.resolvingCurrentLocation
                ? null
                : controller.useCurrentLocation,
            icon: controller.resolvingCurrentLocation
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(tokens.gold),
                    ),
                  )
                : Icon(Icons.my_location, color: tokens.gold),
          ),
        if (showClear)
          IconButton(
            key: limousineAddressClearKey(controller.fieldId),
            tooltip: _t(kLimousineAddressClear),
            onPressed: controller.resolvingCurrentLocation
                ? null
                : controller.clear,
            icon: Icon(Icons.clear, color: tokens.muted),
          ),
      ],
    );
  }
}
