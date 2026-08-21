import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_hotel_lookup.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_transfer_endpoint.dart';

const LocalizedText kLimousineHotelHint = LocalizedText(
  nl: 'Zoek op hotelnaam, plaats, postcode of adres',
  en: 'Search by hotel name, city, postcode or address',
  fr: 'Recherchez par nom d’hôtel, ville, code postal ou adresse',
  es: 'Busque por nombre de hotel, ciudad, código postal o dirección',
);

const LocalizedText kLimousineHotelLoading = LocalizedText(
  nl: 'Hotels zoeken…',
  en: 'Searching hotels…',
  fr: 'Recherche d’hôtels…',
  es: 'Buscando hoteles…',
);

const LocalizedText kLimousineHotelEmpty = LocalizedText(
  nl: 'Geen hotels gevonden. Probeer een andere naam of plaats, of voer het adres handmatig in.',
  en: 'No hotels found. Try another name or place, or enter the address manually.',
  fr: 'Aucun hôtel trouvé. Essayez un autre nom ou lieu, ou saisissez l’adresse manuellement.',
  es: 'No se encontraron hoteles. Pruebe otro nombre o lugar, o introduzca la dirección manualmente.',
);

const LocalizedText kLimousineHotelError = LocalizedText(
  nl: 'Hotelzoeken lukt even niet. Controleer je verbinding of vul een handmatig adres in.',
  en: 'Hotel search is temporarily unavailable. Check your connection or enter a manual address.',
  fr: 'La recherche d’hôtel est temporairement indisponible. Vérifiez votre connexion ou saisissez une adresse manuelle.',
  es: 'La búsqueda de hoteles no está disponible temporalmente. Comprueba tu conexión o introduce una dirección manual.',
);

const LocalizedText kLimousineHotelAuthError = LocalizedText(
  nl: 'Hotelzoeken is niet geautoriseerd. Vul het adres handmatig in of probeer later opnieuw.',
  en: 'Hotel search is not authorized. Enter the address manually or try again later.',
  fr: 'La recherche d’hôtel n’est pas autorisée. Saisissez l’adresse manuellement ou réessayez plus tard.',
  es: 'La búsqueda de hoteles no está autorizada. Introduzca la dirección manualmente o inténtelo más tarde.',
);

const LocalizedText kLimousineHotelManual = LocalizedText(
  nl: 'Hotel niet gevonden? Adres handmatig invoeren',
  en: 'Hotel not found? Enter the address manually',
  fr: 'Hôtel introuvable ? Saisir l’adresse manuellement',
  es: '¿Hotel no encontrado? Introducir la dirección manualmente',
);

const LocalizedText kLimousineHotelRetry = LocalizedText(
  nl: 'Opnieuw zoeken',
  en: 'Search again',
  fr: 'Réessayer',
  es: 'Buscar de nuevo',
);

const Key kLimousineHotelFieldKey = ValueKey<String>('limousine_hotel_field');
const Key kLimousineHotelInputKey = ValueKey<String>('limousine_hotel_input');
const Key kLimousineHotelLoadingKey = ValueKey<String>('limousine_hotel_loading');
const Key kLimousineHotelEmptyKey = ValueKey<String>('limousine_hotel_empty');
const Key kLimousineHotelErrorKey = ValueKey<String>('limousine_hotel_error');
const Key kLimousineHotelManualKey = ValueKey<String>('limousine_hotel_manual');
const Key kLimousineHotelSelectedCardKey = ValueKey<String>(
  'limousine_hotel_selected_card',
);

Key limousineHotelSuggestionKey(int index) =>
    ValueKey<String>('limousine_hotel_suggestion_$index');

String _hotelSuggestionSubtitle(LimousineHotelSuggestion suggestion) {
  final parts = <String>[suggestion.formattedAddress];
  final place = [
    suggestion.city,
    suggestion.postcode,
    suggestion.countryCode,
  ].where((part) => (part ?? '').trim().isNotEmpty).join(' ');
  if (place.isNotEmpty && !suggestion.formattedAddress.contains(place)) {
    parts.add(place);
  }
  final distance = suggestion.distanceMeters;
  if (distance != null && distance.isFinite && distance >= 0) {
    parts.add(
      distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} km'
          : '${distance.round()} m',
    );
  }
  return parts.where((part) => part.trim().isNotEmpty).join(' · ');
}

class LimousineHotelFieldController extends ChangeNotifier {
  LimousineHotelFieldController({
    required this.lookup,
    this.language = 'nl',
    this.debounce = kLimousineHotelDebounce,
  });

  final LimousineHotelLookup lookup;
  String language;
  final Duration debounce;
  double? proximityLat;
  double? proximityLng;
  final TextEditingController textController = TextEditingController();

  Timer? _debounce;
  int _requestId = 0;
  bool loading = false;
  bool searched = false;
  bool hadError = false;
  String lastErrorCode = '';
  List<LimousineHotelSuggestion> suggestions = const [];
  LimousineTransferEndpoint? selected;

  bool get hasSelection => selected != null && !selected!.isEmpty;

  void onTextChanged(String raw) {
    selected = null;
    _debounce?.cancel();
    final query = raw.trim();
    if (query.length < kLimousineHotelMinQueryLength) {
      loading = false;
      searched = false;
      hadError = false;
      lastErrorCode = '';
      suggestions = const [];
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    final id = ++_requestId;
    _debounce = Timer(debounce, () {
      unawaited(_search(query, id));
    });
  }

  Future<void> retry() => _search(textController.text.trim(), ++_requestId);

  void onFocus() {
    if (hasSelection) return;
    if (textController.text.trim().isNotEmpty) return;
    _debounce?.cancel();
    loading = true;
    notifyListeners();
    final id = ++_requestId;
    _debounce = Timer(debounce, () {
      unawaited(_search(kLimousineHotelNearbyQuery, id));
    });
  }

  Future<void> _search(String query, int id) async {
    loading = true;
    notifyListeners();
    final result = await lookup.search(
      query,
      language: language,
      proximityLat: proximityLat,
      proximityLng: proximityLng,
    );
    if (id != _requestId) return;
    loading = false;
    searched = true;
    hadError = result.hadError;
    lastErrorCode = result.errorCode;
    suggestions = result.suggestions;
    notifyListeners();
  }

  Future<void> accept(LimousineHotelSuggestion suggestion) async {
    final id = ++_requestId;
    loading = true;
    hadError = false;
    notifyListeners();
    final resolved = await lookup.resolveSuggestion(suggestion);
    if (id != _requestId) return;
    if (resolved == null || !resolved.isUsable) {
      loading = false;
      hadError = true;
      notifyListeners();
      return;
    }
    selected = resolved.toEndpoint();
    final label = '${resolved.name} — ${resolved.formattedAddress}';
    textController.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = false;
    notifyListeners();
  }

  void acceptManual() {
    selected = limousineManualHotelEndpoint(textController.text);
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = false;
    notifyListeners();
  }

  void seed(LimousineTransferEndpoint? endpoint) {
    selected = endpoint;
    final text = endpoint?.routeText ?? '';
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    textController.dispose();
    super.dispose();
  }
}

class LimousineHotelField extends StatelessWidget {
  const LimousineHotelField({
    super.key,
    required this.controller,
    required this.label,
    required this.tokens,
    required this.language,
  });

  final LimousineHotelFieldController controller;
  final String label;
  final LimousineUxTokens tokens;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final query = controller.textController.text.trim();
        final canManual = query.length >= 8 && query.contains(RegExp(r'[\s,]'));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            key: kLimousineHotelFieldKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: kLimousineHotelInputKey,
                controller: controller.textController,
                style: TextStyle(color: tokens.onSurface),
                scrollPadding: const EdgeInsets.only(bottom: 240),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                onChanged: controller.onTextChanged,
                onTap: controller.onFocus,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: kLimousineHotelHint.of(language),
                  hintStyle: TextStyle(color: tokens.muted),
                  filled: true,
                  fillColor: tokens.fieldFill,
                  prefixIcon: const Icon(Icons.hotel_outlined),
                ),
              ),
              if (controller.hasSelection)
                Container(
                  key: kLimousineHotelSelectedCardKey,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.gold.withOpacity(0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.selected!.displayName,
                        style: TextStyle(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        controller.selected!.formattedAddress,
                        style: TextStyle(color: tokens.muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              if (controller.loading)
                Padding(
                  key: kLimousineHotelLoadingKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    kLimousineHotelLoading.of(language),
                    style: TextStyle(color: tokens.muted),
                  ),
                ),
              if (controller.hadError && !controller.loading)
                Padding(
                  key: kLimousineHotelErrorKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (controller.lastErrorCode == 'authorization'
                                ? kLimousineHotelAuthError
                                : kLimousineHotelError)
                            .of(language),
                        style: TextStyle(color: tokens.danger),
                      ),
                      TextButton(
                        onPressed: controller.retry,
                        child: Text(kLimousineHotelRetry.of(language)),
                      ),
                    ],
                  ),
                ),
              if (controller.searched &&
                  !controller.loading &&
                  !controller.hadError &&
                  controller.suggestions.isEmpty)
                Padding(
                  key: kLimousineHotelEmptyKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    kLimousineHotelEmpty.of(language),
                    style: TextStyle(color: tokens.muted),
                  ),
                ),
              if (controller.suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: tokens.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.gold.withOpacity(0.35)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < controller.suggestions.length; i++)
                        ListTile(
                          key: limousineHotelSuggestionKey(i),
                          leading: Icon(
                            Icons.hotel_outlined,
                            color: tokens.gold,
                          ),
                          title: Text(
                            controller.suggestions[i].name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _hotelSuggestionSubtitle(controller.suggestions[i]),
                          ),
                          onTap: () =>
                              controller.accept(controller.suggestions[i]),
                        ),
                    ],
                  ),
                ),
              if (canManual && !controller.hasSelection)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: kLimousineHotelManualKey,
                    onPressed: controller.acceptManual,
                    child: Text(kLimousineHotelManual.of(language)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
