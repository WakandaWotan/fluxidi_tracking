import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_address_lookup.dart';
import 'limousine_event_lookup.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_transfer_endpoint.dart';

const LocalizedText kLimousineEventSearchLabel = LocalizedText(
  nl: 'Zoek evenementlocatie',
  en: 'Search event venue',
  fr: 'Rechercher le lieu de l’événement',
  es: 'Buscar ubicación del evento',
);

const LocalizedText kLimousineEventHint = LocalizedText(
  nl: 'Concertzaal, evenementenhal, trouwlocatie, theater, stadion, congres of festival',
  en: 'Concert hall, event hall, wedding venue, theatre, stadium, congress or festival',
  fr: 'Salle de concert, hall d’événement, lieu de mariage, théâtre, stade, congrès ou festival',
  es: 'Sala de conciertos, recinto, boda, teatro, estadio, congreso o festival',
);

const LocalizedText kLimousineEventNameLabel = LocalizedText(
  nl: 'Naam evenement',
  en: 'Event name',
  fr: 'Nom de l’événement',
  es: 'Nombre del evento',
);

const LocalizedText kLimousineEventLoading = LocalizedText(
  nl: 'Evenementlocaties zoeken…',
  en: 'Searching event venues…',
  fr: 'Recherche de lieux d’événement…',
  es: 'Buscando ubicaciones de evento…',
);

const LocalizedText kLimousineEventEmpty = LocalizedText(
  nl: 'Geen locatie gevonden. Probeer een andere naam of vul het adres handmatig in.',
  en: 'No venue found. Try another name or enter the address manually.',
  fr: 'Aucun lieu trouvé. Essayez un autre nom ou saisissez l’adresse manuellement.',
  es: 'No se encontró ninguna ubicación. Pruebe otro nombre o introduzca la dirección.',
);

const LocalizedText kLimousineEventError = LocalizedText(
  nl: 'Zoeken lukt even niet. Controleer je verbinding of vul het adres handmatig in.',
  en: 'Search is temporarily unavailable. Check your connection or enter the address manually.',
  fr: 'La recherche est temporairement indisponible. Vérifiez votre connexion ou saisissez l’adresse.',
  es: 'La búsqueda no está disponible. Compruebe la conexión o introduzca la dirección.',
);

const LocalizedText kLimousineEventManual = LocalizedText(
  nl: 'Locatie niet gevonden? Adres handmatig invoeren',
  en: 'Venue not found? Enter the address manually',
  fr: 'Lieu introuvable ? Saisir l’adresse manuellement',
  es: '¿No encuentra el lugar? Introducir la dirección manualmente',
);

const LocalizedText kLimousineEventRetry = LocalizedText(
  nl: 'Opnieuw zoeken',
  en: 'Search again',
  fr: 'Réessayer',
  es: 'Buscar de nuevo',
);

const LocalizedText kLimousineCustomerDesiredArrivalTime = LocalizedText(
  nl: 'Gewenste aankomsttijd',
  en: 'Desired arrival time',
  fr: 'Heure d’arrivée souhaitée',
  es: 'Hora de llegada deseada',
);

const Key kLimousineEventFieldKey = ValueKey<String>('limousine_event_field');
const Key kLimousineEventInputKey = ValueKey<String>('limousine_event_input');
const Key kLimousineEventNameInputKey = ValueKey<String>(
  'limousine_event_name_input',
);
const Key kLimousineEventLoadingKey = ValueKey<String>('limousine_event_loading');
const Key kLimousineEventEmptyKey = ValueKey<String>('limousine_event_empty');
const Key kLimousineEventErrorKey = ValueKey<String>('limousine_event_error');
const Key kLimousineEventManualKey = ValueKey<String>('limousine_event_manual');
const Key kLimousineEventSelectedCardKey = ValueKey<String>(
  'limousine_event_selected_card',
);

Key limousineEventSuggestionKey(int index) =>
    ValueKey<String>('limousine_event_suggestion_$index');

class LimousineEventFieldController extends ChangeNotifier {
  LimousineEventFieldController({
    required this.lookup,
    this.language = 'nl',
    this.debounce = kLimousineEventDebounce,
  });

  final LimousineEventLookup lookup;
  String language;
  final Duration debounce;
  final TextEditingController textController = TextEditingController();
  final TextEditingController eventNameController = TextEditingController();

  Timer? _debounce;
  int _requestId = 0;
  bool loading = false;
  bool searched = false;
  bool hadError = false;
  List<LimousineEventVenueSuggestion> suggestions = const [];
  LimousineTransferEndpoint? selected;

  bool get hasSelection => selected != null && !selected!.isEmpty;

  String get eventName => eventNameController.text.trim();

  void onTextChanged(String raw) {
    selected = null;
    _debounce?.cancel();
    final query = raw.trim();
    if (query.length < kLimousineEventMinQueryLength) {
      loading = false;
      searched = false;
      hadError = false;
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

  void onEventNameChanged(String raw) {
    final name = raw.trim();
    if (selected != null) {
      selected = selected!.copyWith(eventName: name, clearEventName: name.isEmpty);
    }
    notifyListeners();
  }

  Future<void> retry() => _search(textController.text.trim(), ++_requestId);

  Future<void> _search(String query, int id) async {
    loading = true;
    notifyListeners();
    final result = await lookup.search(query, language: language);
    if (id != _requestId) return;
    loading = false;
    searched = true;
    hadError = result.hadError;
    suggestions = result.suggestions;
    notifyListeners();
  }

  void accept(LimousineEventVenueSuggestion suggestion) {
    selected = suggestion.toEndpoint(eventName: eventName);
    textController.value = TextEditingValue(
      text: '${suggestion.name} — ${suggestion.formattedAddress}',
      selection: TextSelection.collapsed(
        offset: '${suggestion.name} — ${suggestion.formattedAddress}'.length,
      ),
    );
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = false;
    notifyListeners();
  }

  Future<void> acceptManual() async {
    final pending = limousineManualEventEndpoint(
      textController.text,
      eventName: eventName,
    );
    selected = pending;
    suggestions = const [];
    searched = false;
    hadError = false;
    loading = true;
    notifyListeners();
    final resolved = await lookup.resolveManual(
      textController.text,
      language: language,
      eventName: eventName,
    );
    selected = resolved.copyWith(manual: true, eventName: eventName);
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
    final name = (endpoint?.eventName ?? '').trim();
    eventNameController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
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
    eventNameController.dispose();
    super.dispose();
  }
}

class LimousineEventField extends StatelessWidget {
  const LimousineEventField({
    super.key,
    required this.controller,
    required this.tokens,
    required this.language,
  });

  final LimousineEventFieldController controller;
  final LimousineUxTokens tokens;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final query = controller.textController.text.trim();
        final canManual = limousineAddressAllowsManualFallback(query);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            key: kLimousineEventFieldKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: kLimousineEventInputKey,
                controller: controller.textController,
                style: TextStyle(color: tokens.onSurface),
                scrollPadding: const EdgeInsets.only(bottom: 240),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                onChanged: controller.onTextChanged,
                decoration: InputDecoration(
                  labelText: kLimousineEventSearchLabel.of(language),
                  hintText: kLimousineEventHint.of(language),
                  hintStyle: TextStyle(color: tokens.muted),
                  filled: true,
                  fillColor: tokens.fieldFill,
                  prefixIcon: const Icon(Icons.celebration_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: kLimousineEventNameInputKey,
                controller: controller.eventNameController,
                style: TextStyle(color: tokens.onSurface),
                onChanged: controller.onEventNameChanged,
                decoration: InputDecoration(
                  labelText: kLimousineEventNameLabel.of(language),
                  filled: true,
                  fillColor: tokens.fieldFill,
                ),
              ),
              if (controller.hasSelection)
                Container(
                  key: kLimousineEventSelectedCardKey,
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
                        controller.selected!.venueName ??
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
                      if ((controller.selected!.eventName ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            controller.selected!.eventName!.trim(),
                            style: TextStyle(color: tokens.onSurface),
                          ),
                        ),
                    ],
                  ),
                ),
              if (controller.loading)
                Padding(
                  key: kLimousineEventLoadingKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    kLimousineEventLoading.of(language),
                    style: TextStyle(color: tokens.muted),
                  ),
                ),
              if (controller.hadError && !controller.loading)
                Padding(
                  key: kLimousineEventErrorKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kLimousineEventError.of(language),
                        style: TextStyle(color: tokens.danger),
                      ),
                      TextButton(
                        onPressed: controller.retry,
                        child: Text(kLimousineEventRetry.of(language)),
                      ),
                    ],
                  ),
                ),
              if (controller.searched &&
                  !controller.loading &&
                  !controller.hadError &&
                  controller.suggestions.isEmpty)
                Padding(
                  key: kLimousineEventEmptyKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    kLimousineEventEmpty.of(language),
                    style: TextStyle(color: tokens.muted),
                  ),
                ),
              for (var i = 0; i < controller.suggestions.length; i++)
                ListTile(
                  key: limousineEventSuggestionKey(i),
                  contentPadding: EdgeInsets.zero,
                  title: Text(controller.suggestions[i].name),
                  subtitle: Text(controller.suggestions[i].formattedAddress),
                  onTap: () => controller.accept(controller.suggestions[i]),
                ),
              if (canManual && !controller.hasSelection)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: kLimousineEventManualKey,
                    onPressed: () => unawaited(controller.acceptManual()),
                    child: Text(kLimousineEventManual.of(language)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
