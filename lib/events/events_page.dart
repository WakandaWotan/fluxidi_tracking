import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

import 'event_ai_intent_parser.dart';
import 'event_category_results_page.dart';
import 'event_data_source.dart';
import 'event_models.dart';
import 'saved_events_page.dart';

EventDataSource buildDefaultEventLocatorDataSource({required String baseUrl}) {
  return RemoteEventDataSource(
    baseUrl: baseUrl,
    fallbackDataSource: const LocalSeedEventDataSource(),
  );
}

class EventsPage extends StatefulWidget {
  const EventsPage({this.onBookEvent, this.dataSource, super.key});

  final EventBookCallback? onBookEvent;
  final EventDataSource? dataSource;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  static const List<String> _dateFilterKeys = <String>[
    EventDateMode.all,
    EventDateMode.today,
    EventDateMode.weekend,
    EventDateMode.month,
  ];
  static const List<String> _categoryFilterKeys = <String>[
    'all',
    EventCategoryKey.music,
    EventCategoryKey.sport,
    EventCategoryKey.theater,
    EventCategoryKey.comedy,
    EventCategoryKey.family,
    EventCategoryKey.food,
    EventCategoryKey.business,
    EventCategoryKey.culture,
  ];
  static const List<String> _marketKeys = <String>[
    'be',
    'nl',
    'fr',
    'uk',
    'es',
  ];
  static const List<String> _sortModes = <String>[
    'default',
    'soonest',
    'latest',
    'popular',
  ];

  final TextEditingController _searchController = TextEditingController();
  static const List<String> _eventAiPromptExamples = <String>[
    'Concerten dit weekend in België',
    'Sportevents in Spanje',
    'Comedy in UK',
    'Familie events in Nederland',
    'Theater in Frankrijk',
  ];
  late final EventDataSource _dataSource;
  late String _selectedMarketKey;
  String _selectedDateMode = EventDateMode.all;
  DateTime? _selectedMonthStartUtc;
  DateTime? _selectedMonthEndUtc;
  String _selectedCategoryKey = 'all';
  String _selectedSortMode = 'default';
  bool _didPrecacheCategoryImages = false;
  final Map<String, ImageProvider<Object>> _categoryImageProviders =
      <String, ImageProvider<Object>>{};

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
        return nl;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedMarketKey = _marketKeys.first;
    _dataSource = widget.dataSource ?? const LocalSeedEventDataSource();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheCategoryTileImages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _precacheCategoryTileImages() {
    if (_didPrecacheCategoryImages) return;
    _didPrecacheCategoryImages = true;
    for (final key in _categoryFilterKeys) {
      precacheImage(_categoryImageProvider(key), context).catchError((_) {});
    }
  }

  ImageProvider<Object> _categoryImageProvider(String categoryKey) {
    return _categoryImageProviders.putIfAbsent(
      categoryKey,
      () => AssetImage(_categoryTileAssetPath(categoryKey)),
    );
  }

  String _marketLabel(String key) {
    switch (key) {
      case 'be':
        return _t(nl: 'België', en: 'Belgium', fr: 'Belgique', es: 'Bélgica');
      case 'nl':
        return _t(
          nl: 'Nederland',
          en: 'Netherlands',
          fr: 'Pays-Bas',
          es: 'Países Bajos',
        );
      case 'fr':
        return _t(nl: 'Frankrijk', en: 'France', fr: 'France', es: 'Francia');
      case 'uk':
        return _t(
          nl: 'Verenigd Koninkrijk',
          en: 'United Kingdom',
          fr: 'Royaume-Uni',
          es: 'Reino Unido',
        );
      case 'es':
        return _t(nl: 'Spanje', en: 'Spain', fr: 'Espagne', es: 'España');
      default:
        return key.toUpperCase();
    }
  }

  String _dateFilterLabel(String key) {
    switch (key) {
      case EventDateMode.all:
        return _t(nl: 'Alles', en: 'All', fr: 'Tout', es: 'Todo');
      case EventDateMode.today:
        return _t(nl: 'Vandaag', en: 'Today', fr: 'Aujourd’hui', es: 'Hoy');
      case EventDateMode.weekend:
        return _t(
          nl: 'Dit weekend',
          en: 'This weekend',
          fr: 'Ce week-end',
          es: 'Este fin de semana',
        );
      case EventDateMode.month:
        if (_selectedMonthStartUtc == null) {
          return _t(nl: 'Maand', en: 'Month', fr: 'Mois', es: 'Mes');
        }
        final local = _selectedMonthStartUtc!.toLocal();
        return '${local.month.toString().padLeft(2, '0')}-${local.year}';
      default:
        return key;
    }
  }

  String _categoryFilterLabel(String key) {
    switch (key) {
      case 'all':
        return _t(
          nl: 'Alle categorieën',
          en: 'All categories',
          fr: 'Toutes catégories',
          es: 'Todas categorías',
        );
      case EventCategoryKey.music:
        return _t(nl: 'Muziek', en: 'Music', fr: 'Musique', es: 'Música');
      case EventCategoryKey.sport:
        return _t(nl: 'Sport', en: 'Sport', fr: 'Sport', es: 'Deporte');
      case EventCategoryKey.theater:
        return _t(nl: 'Theater', en: 'Theater', fr: 'Théâtre', es: 'Teatro');
      case EventCategoryKey.comedy:
        return _t(nl: 'Comedy', en: 'Comedy', fr: 'Comédie', es: 'Comedia');
      case EventCategoryKey.family:
        return _t(nl: 'Familie', en: 'Family', fr: 'Famille', es: 'Familia');
      case EventCategoryKey.food:
        return _t(nl: 'Food', en: 'Food', fr: 'Cuisine', es: 'Comida');
      case EventCategoryKey.business:
        return _t(
          nl: 'Zakelijk',
          en: 'Business',
          fr: 'Business',
          es: 'Negocios',
        );
      case EventCategoryKey.culture:
        return _t(nl: 'Cultuur', en: 'Culture', fr: 'Culture', es: 'Cultura');
      case EventCategoryKey.other:
        return _t(nl: 'Overig', en: 'Other', fr: 'Autre', es: 'Otro');
      default:
        return key;
    }
  }

  String _sortModeLabel(String key) {
    switch (key) {
      case 'soonest':
        return _t(
          nl: 'Eerstkomend',
          en: 'Soonest first',
          fr: 'Plus proche',
          es: 'Mas cercano',
        );
      case 'latest':
        return _t(
          nl: 'Later/laatst',
          en: 'Latest first',
          fr: 'Plus tard',
          es: 'Mas tarde',
        );
      case 'popular':
        return _t(
          nl: 'Populair',
          en: 'Popular',
          fr: 'Populaire',
          es: 'Popular',
        );
      case 'default':
      default:
        return _t(
          nl: 'Standaard',
          en: 'Default',
          fr: 'Defaut',
          es: 'Predeterminado',
        );
    }
  }

  String _formatMonthLabel(DateTime startUtc) {
    final local = startUtc.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.year}';
  }

  String get _activeFilterSummaryText {
    final parts = <String>[
      _marketLabel(_selectedMarketKey),
      _dateFilterLabel(_selectedDateMode),
      _sortModeLabel(_selectedSortMode),
    ];
    if (_selectedCategoryKey != 'all') {
      parts.add(_categoryFilterLabel(_selectedCategoryKey));
    }
    final joined = parts.join(' · ');
    return _t(
      nl: 'Actief: $joined',
      en: 'Active: $joined',
      fr: 'Actif : $joined',
      es: 'Activo: $joined',
    );
  }

  List<_MonthFilterOption> _nextTwelveMonthOptions() {
    final nowLocal = DateTime.now().toLocal();
    final firstMonthLocal = DateTime(nowLocal.year, nowLocal.month, 1);
    return List<_MonthFilterOption>.generate(12, (index) {
      final monthStartLocal = DateTime(
        firstMonthLocal.year,
        firstMonthLocal.month + index,
        1,
      );
      final nextMonthStartLocal = DateTime(
        monthStartLocal.year,
        monthStartLocal.month + 1,
        1,
      );
      return _MonthFilterOption(
        startUtc: monthStartLocal.toUtc(),
        endUtc: nextMonthStartLocal
            .subtract(const Duration(milliseconds: 1))
            .toUtc(),
      );
    });
  }

  Future<void> _openMonthPicker() async {
    final options = _nextTwelveMonthOptions();
    final selectedStartUtc = _selectedMonthStartUtc;
    final chosen = await showModalBottomSheet<_MonthFilterOption>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Selecteer maand',
                    en: 'Select month',
                    fr: 'Sélectionner le mois',
                    es: 'Seleccionar mes',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: _gold.withOpacity(0.16), height: 1),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected =
                          selectedStartUtc != null &&
                          option.startUtc.isAtSameMomentAs(selectedStartUtc);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          _formatMonthLabel(option.startUtc),
                          style: TextStyle(
                            color: isSelected ? _gold : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(option),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _selectedDateMode = EventDateMode.month;
      _selectedMonthStartUtc = chosen.startUtc;
      _selectedMonthEndUtc = chosen.endUtc;
    });
  }

  Future<void> _openSavedEventsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<SavedEventsPage>(
        builder: (_) => SavedEventsPage(onBookEvent: widget.onBookEvent),
      ),
    );
  }

  Future<void> _openResultsPage({
    required String title,
    required String categoryKey,
    required String searchQuery,
    String? marketKey,
    String? dateMode,
    DateTime? monthStartUtc,
    DateTime? monthEndUtc,
    String? sortMode,
    bool useProvidedMonthRangeOnly = false,
  }) async {
    final targetMarketKey = marketKey ?? _selectedMarketKey;
    final targetDateMode = dateMode ?? _selectedDateMode;
    final targetSortMode = sortMode ?? _selectedSortMode;
    final targetMonthStartUtc = useProvidedMonthRangeOnly
        ? monthStartUtc
        : (monthStartUtc ?? _selectedMonthStartUtc);
    final targetMonthEndUtc = useProvidedMonthRangeOnly
        ? monthEndUtc
        : (monthEndUtc ?? _selectedMonthEndUtc);
    await Navigator.of(context).push(
      MaterialPageRoute<EventCategoryResultsPage>(
        builder: (_) => EventCategoryResultsPage(
          title: title,
          dataSource: _dataSource,
          marketKey: targetMarketKey,
          dateMode: targetDateMode,
          monthStartUtc: targetMonthStartUtc,
          monthEndUtc: targetMonthEndUtc,
          categoryKey: categoryKey,
          searchQuery: searchQuery.trim(),
          sortMode: targetSortMode,
          onBookEvent: widget.onBookEvent,
        ),
      ),
    );
  }

  Future<void> _openSearchResults() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    await _openResultsPage(
      title: _t(nl: 'Zoeken', en: 'Search', fr: 'Recherche', es: 'Buscar'),
      categoryKey: _selectedCategoryKey,
      searchQuery: query,
    );
  }

  String _eventAiDateLabel(String dateSignal) {
    switch (dateSignal) {
      case EventDateMode.today:
        return _t(nl: 'vandaag', en: 'today', fr: 'aujourd’hui', es: 'hoy');
      case EventDateMode.weekend:
        return _t(
          nl: 'dit weekend',
          en: 'this weekend',
          fr: 'ce week-end',
          es: 'este fin de semana',
        );
      case EventDateMode.month:
        return _t(
          nl: 'deze maand',
          en: 'this month',
          fr: 'ce mois',
          es: 'este mes',
        );
      case 'year':
        return _t(
          nl: 'dit jaar',
          en: 'this year',
          fr: 'cette année',
          es: 'este año',
        );
      default:
        return '';
    }
  }

  String _eventAiExplanation(EventAiIntent intent) {
    final categoryPart = intent.categoryKey == 'all'
        ? _t(nl: 'events', en: 'events', fr: 'événements', es: 'eventos')
        : '${_categoryFilterLabel(intent.categoryKey).toLowerCase()}-events';
    final locationPart = _marketLabel(intent.marketKey);
    final datePart = _eventAiDateLabel(intent.dateSignal);
    final queryPart = intent.searchQuery.isEmpty
        ? ''
        : _t(
            nl: ' Zoekterm: "${intent.searchQuery}".',
            en: ' Query: "${intent.searchQuery}".',
            fr: ' Terme: "${intent.searchQuery}".',
            es: ' Búsqueda: "${intent.searchQuery}".',
          );
    if (datePart.isNotEmpty) {
      return _t(
            nl: 'Ik zoek $categoryPart in $locationPart voor $datePart.',
            en: 'I am looking for $categoryPart in $locationPart for $datePart.',
            fr: 'Je cherche des $categoryPart en $locationPart pour $datePart.',
            es: 'Busco $categoryPart en $locationPart para $datePart.',
          ) +
          queryPart;
    }
    return _t(
          nl: 'Ik zoek $categoryPart in $locationPart.',
          en: 'I am looking for $categoryPart in $locationPart.',
          fr: 'Je cherche des $categoryPart en $locationPart.',
          es: 'Busco $categoryPart en $locationPart.',
        ) +
        queryPart;
  }

  Future<void> _submitEventAiInput({
    required String rawInput,
    required void Function(String errorText) showValidation,
  }) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      showValidation(
        _t(
          nl: 'Voer een vraag in voor Fluxidi AI.',
          en: 'Enter a request for Fluxidi AI.',
          fr: 'Saisissez une demande pour Fluxidi AI.',
          es: 'Introduce una solicitud para Fluxidi AI.',
        ),
      );
      return;
    }
    final intent = parseEventAiIntent(
      input: trimmed,
      fallbackMarketKey: _selectedMarketKey,
      fallbackDateMode: _selectedDateMode,
    );
    debugPrint('[EVENT_AI] input=$trimmed');
    debugPrint(
      '[EVENT_AI] parsed market=${intent.marketKey} category=${intent.categoryKey} date=${intent.dateSignal} query=${intent.searchQuery}',
    );
    if (!mounted) return;
    final aiMarketKey = intent.marketKey;
    final aiCategoryKey = intent.categoryKey;
    final aiDateKey = intent.dateMode;
    final aiSearchQuery = intent.searchQuery;
    debugPrint(
      '[EVENT_AI] navigate market=$aiMarketKey category=$aiCategoryKey date=$aiDateKey query=$aiSearchQuery',
    );
    debugPrint('[EVENT_AI] state_isolated=true');
    Navigator.of(context).pop();
    await _openResultsPage(
      title: _t(
        nl: 'Fluxidi AI resultaten',
        en: 'Fluxidi AI results',
        fr: 'Résultats Fluxidi AI',
        es: 'Resultados Fluxidi AI',
      ),
      marketKey: aiMarketKey,
      dateMode: aiDateKey,
      monthStartUtc: aiDateKey == EventDateMode.month
          ? _selectedMonthStartUtc
          : null,
      monthEndUtc: aiDateKey == EventDateMode.month
          ? _selectedMonthEndUtc
          : null,
      useProvidedMonthRangeOnly: true,
      categoryKey: aiCategoryKey,
      searchQuery: aiSearchQuery,
    );
  }

  Future<void> _openEventAiAssistant() async {
    final aiController = TextEditingController(
      text: _searchController.text.trim(),
    );
    String currentInput = aiController.text;
    String? validationError;
    EventAiIntent currentIntent = parseEventAiIntent(
      input: currentInput,
      fallbackMarketKey: _selectedMarketKey,
      fallbackDateMode: _selectedDateMode,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final hasInput = currentInput.trim().isNotEmpty;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 16 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(
                          nl: 'Vraag Fluxidi AI',
                          en: 'Ask Fluxidi AI',
                          fr: 'Demander à Fluxidi AI',
                          es: 'Preguntar a Fluxidi AI',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: aiController,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          setSheetState(() {
                            currentInput = value;
                            validationError = null;
                            currentIntent = parseEventAiIntent(
                              input: value,
                              fallbackMarketKey: _selectedMarketKey,
                              fallbackDateMode: _selectedDateMode,
                            );
                          });
                        },
                        onSubmitted: (_) => _submitEventAiInput(
                          rawInput: currentInput,
                          showValidation: (message) => setSheetState(() {
                            validationError = message;
                          }),
                        ),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _t(
                            nl: 'Bijv. concerten dit weekend in België',
                            en: 'E.g. concerts this weekend in Belgium',
                            fr: 'Ex. concerts ce week-end en Belgique',
                            es: 'Ej. conciertos este fin de semana en Bélgica',
                          ),
                          hintStyle: const TextStyle(color: Color(0xFF8C8C8C)),
                          filled: true,
                          fillColor: const Color(0xFF151515),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _gold.withOpacity(0.24),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _gold,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                      if (validationError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationError!,
                          style: const TextStyle(
                            color: Color(0xFFFF8D8D),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _eventAiPromptExamples.map((prompt) {
                          return ActionChip(
                            label: Text(
                              prompt,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: const Color(0xFF171717),
                            side: BorderSide(color: _gold.withOpacity(0.3)),
                            onPressed: () {
                              aiController.text = prompt;
                              aiController
                                  .selection = TextSelection.fromPosition(
                                TextPosition(offset: aiController.text.length),
                              );
                              setSheetState(() {
                                currentInput = prompt;
                                validationError = null;
                                currentIntent = parseEventAiIntent(
                                  input: prompt,
                                  fallbackMarketKey: _selectedMarketKey,
                                  fallbackDateMode: _selectedDateMode,
                                );
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (hasInput) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _gold.withOpacity(0.26)),
                          ),
                          child: Text(
                            _eventAiExplanation(currentIntent),
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 11.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _submitEventAiInput(
                            rawInput: currentInput,
                            showValidation: (message) => setSheetState(() {
                              validationError = message;
                            }),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: const Color(0xFF1A1307),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 17,
                          ),
                          label: Text(
                            _t(
                              nl: 'Zoeken',
                              en: 'Search',
                              fr: 'Rechercher',
                              es: 'Buscar',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    aiController.dispose();
  }

  Future<void> _openMarketPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Kies regio',
                    en: 'Choose region',
                    fr: 'Choisir la region',
                    es: 'Elegir region',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _marketKeys.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: _gold.withOpacity(0.16), height: 1),
                    itemBuilder: (context, index) {
                      final key = _marketKeys[index];
                      final isSelected = key == _selectedMarketKey;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          _marketLabel(key),
                          style: TextStyle(
                            color: isSelected ? _gold : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(key),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null || selected == _selectedMarketKey) return;
    setState(() => _selectedMarketKey = selected);
  }

  Future<void> _openDatePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Kies datumfilter',
                    en: 'Choose date filter',
                    fr: 'Choisir le filtre de date',
                    es: 'Elegir filtro de fecha',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _dateFilterKeys.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: _gold.withOpacity(0.16), height: 1),
                    itemBuilder: (context, index) {
                      final key = _dateFilterKeys[index];
                      final isSelected = key == _selectedDateMode;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          _dateFilterLabel(key),
                          style: TextStyle(
                            color: isSelected ? _gold : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(key),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    if (selected == EventDateMode.month) {
      await _openMonthPicker();
      return;
    }
    setState(() => _selectedDateMode = selected);
  }

  Future<void> _openCategoryPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Kies categorie',
                    en: 'Choose category',
                    fr: 'Choisir categorie',
                    es: 'Elegir categoria',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _categoryFilterKeys.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: _gold.withOpacity(0.16), height: 1),
                    itemBuilder: (context, index) {
                      final key = _categoryFilterKeys[index];
                      final isSelected = key == _selectedCategoryKey;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          _categoryFilterLabel(key),
                          style: TextStyle(
                            color: isSelected ? _gold : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(key),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedCategoryKey = selected);
    await _openResultsPage(
      title: _categoryFilterLabel(selected),
      categoryKey: selected,
      searchQuery: _searchController.text,
    );
  }

  Future<void> _openSortPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Sorteer events',
                    en: 'Sort events',
                    fr: 'Trier evenements',
                    es: 'Ordenar eventos',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _sortModes.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: _gold.withOpacity(0.16), height: 1),
                    itemBuilder: (context, index) {
                      final key = _sortModes[index];
                      final isSelected = key == _selectedSortMode;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          _sortModeLabel(key),
                          style: TextStyle(
                            color: isSelected ? _gold : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(key),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedSortMode = selected);
  }

  List<Color> _categoryTileGradient(String categoryKey) {
    switch (categoryKey) {
      case EventCategoryKey.music:
        return const <Color>[Color(0xFF1C2144), Color(0xFF11152C)];
      case EventCategoryKey.sport:
        return const <Color>[Color(0xFF173228), Color(0xFF0E2019)];
      case EventCategoryKey.theater:
        return const <Color>[Color(0xFF3A2244), Color(0xFF1D1327)];
      case EventCategoryKey.comedy:
        return const <Color>[Color(0xFF3D2A1B), Color(0xFF1E140E)];
      case EventCategoryKey.family:
        return const <Color>[Color(0xFF293F53), Color(0xFF162433)];
      case EventCategoryKey.food:
        return const <Color>[Color(0xFF3F2A1A), Color(0xFF21150D)];
      case EventCategoryKey.business:
        return const <Color>[Color(0xFF26374A), Color(0xFF172331)];
      case EventCategoryKey.culture:
        return const <Color>[Color(0xFF3D2E4F), Color(0xFF1C1630)];
      case EventCategoryKey.other:
      case 'all':
      default:
        return const <Color>[Color(0xFF2A1B06), Color(0xFF100B04)];
    }
  }

  String _categoryTileAssetPath(String categoryKey) {
    switch (categoryKey) {
      case 'all':
        return 'assets/events/categories/event_category_all.webp';
      case EventCategoryKey.music:
        return 'assets/events/categories/event_category_music.webp';
      case EventCategoryKey.sport:
        return 'assets/events/categories/event_category_sport.webp';
      case EventCategoryKey.theater:
        return 'assets/events/categories/event_category_theater.webp';
      case EventCategoryKey.comedy:
        return 'assets/events/categories/event_category_comedy.webp';
      case EventCategoryKey.family:
        return 'assets/events/categories/event_category_family.webp';
      case EventCategoryKey.food:
        return 'assets/events/categories/event_category_food.webp';
      case EventCategoryKey.business:
        return 'assets/events/categories/event_category_business.webp';
      case EventCategoryKey.culture:
        return 'assets/events/categories/event_category_culture.webp';
      case EventCategoryKey.other:
        return 'assets/events/categories/event_category_other.webp';
      default:
        return 'assets/events/categories/event_category_all.webp';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaQuery = MediaQuery.of(context);
            const horizontalPadding = 14.0;
            const topPadding = 10.0;
            const bottomPadding = 18.0;
            final screenWidth = constraints.maxWidth;
            final shortestSide = mediaQuery.size.shortestSide;
            final isTabletLayout = shortestSide >= 600 || screenWidth >= 700;
            final headerToSearchSpacing = isTabletLayout ? 10.0 : 8.0;
            final searchToControlsSpacing = isTabletLayout ? 10.0 : 8.0;
            final controlsToHeadingSpacing = isTabletLayout ? 12.0 : 10.0;
            final headingToGridSpacing = isTabletLayout ? 10.0 : 8.0;
            final estimatedHeaderHeight = isTabletLayout ? 58.0 : 50.0;
            final estimatedSearchHeight = isTabletLayout ? 56.0 : 48.0;
            final estimatedControlsHeight = isTabletLayout ? 132.0 : 102.0;
            final estimatedHeadingHeight = isTabletLayout ? 30.0 : 22.0;
            final tileSpacing = isTabletLayout ? 12.0 : 10.0;
            final columns = screenWidth < 360 ? 2 : 3;
            final rows = (_categoryFilterKeys.length / columns).ceil();
            final contentWidth = screenWidth - (horizontalPadding * 2);
            final tileWidth =
                (contentWidth - ((columns - 1) * tileSpacing)) / columns;

            final estimatedTopContentHeight =
                topPadding +
                estimatedHeaderHeight +
                headerToSearchSpacing +
                estimatedSearchHeight +
                searchToControlsSpacing +
                estimatedControlsHeight +
                controlsToHeadingSpacing +
                estimatedHeadingHeight +
                headingToGridSpacing +
                bottomPadding;
            final remainingHeight =
                constraints.maxHeight - estimatedTopContentHeight;
            final unclampedTileHeight =
                (remainingHeight - ((rows - 1) * tileSpacing)) / rows;
            final minTileHeight = isTabletLayout
                ? 215.0
                : (screenWidth < 360 ? 108.0 : 130.0);
            final maxTileHeight = isTabletLayout
                ? 300.0
                : (screenWidth < 360 ? 145.0 : 165.0);
            final tileHeight = unclampedTileHeight
                .clamp(minTileHeight, maxTileHeight)
                .toDouble();
            final gridHeight = (tileHeight * rows) + ((rows - 1) * tileSpacing);
            final tileAspectRatio = tileWidth / tileHeight;
            final categoryLabelFontSize = isTabletLayout ? 22.0 : 12.2;
            final categoryIconSize = isTabletLayout ? 28.0 : 16.0;
            final categoryTileInset = isTabletLayout ? 14.0 : 8.0;
            final categoryLabelMaxLines = isTabletLayout ? 2 : 1;
            final categoryLabelSpacing = isTabletLayout ? 6.0 : 3.0;
            final headingFontSize = isTabletLayout ? 22.0 : 14.0;

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                bottomPadding,
              ),
              children: [
                _buildHeader(context, isTabletLayout: isTabletLayout),
                SizedBox(height: headerToSearchSpacing),
                _buildSearchField(isTabletLayout: isTabletLayout),
                SizedBox(height: searchToControlsSpacing),
                _buildCompactDiscoveryControls(isTabletLayout: isTabletLayout),
                SizedBox(height: controlsToHeadingSpacing),
                Text(
                  _t(
                    nl: 'Categorieën',
                    en: 'Categories',
                    fr: 'Categories',
                    es: 'Categorias',
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: headingFontSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: headingToGridSpacing),
                SizedBox(
                  height: gridHeight,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _categoryFilterKeys.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: tileSpacing,
                      mainAxisSpacing: tileSpacing,
                      childAspectRatio: tileAspectRatio,
                    ),
                    itemBuilder: (context, index) => _buildCategoryTile(
                      _categoryFilterKeys[index],
                      iconSize: categoryIconSize,
                      labelFontSize: categoryLabelFontSize,
                      labelMaxLines: categoryLabelMaxLines,
                      contentInset: categoryTileInset,
                      labelSpacing: categoryLabelSpacing,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isTabletLayout}) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, size: isTabletLayout ? 27 : 24),
          color: _gold,
          tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
        ),
        Expanded(
          child: Text(
            _t(
              nl: 'Evenementen',
              en: 'Events',
              fr: 'Événements',
              es: 'Eventos',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: isTabletLayout ? 24 : 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openSavedEventsPage,
          style: OutlinedButton.styleFrom(
            backgroundColor: _panelBlack,
            foregroundColor: _gold,
            side: BorderSide(color: _gold.withOpacity(0.34)),
            minimumSize: Size(0, isTabletLayout ? 46 : 38),
            padding: EdgeInsets.symmetric(
              horizontal: isTabletLayout ? 13 : 10,
              vertical: isTabletLayout ? 8 : 6,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: Icon(Icons.bookmark_rounded, size: isTabletLayout ? 20 : 16),
          label: Text(
            _t(
              nl: 'Opgeslagen',
              en: 'Saved',
              fr: 'Enregistres',
              es: 'Guardados',
            ),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isTabletLayout ? 14.5 : 11.8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField({required bool isTabletLayout}) {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _openSearchResults(),
      style: TextStyle(color: Colors.white, fontSize: isTabletLayout ? 16 : 14),
      decoration: InputDecoration(
        hintText: _t(
          nl: 'Zoek evenement of locatie',
          en: 'Search event or location',
          fr: 'Rechercher un evenement ou un lieu',
          es: 'Buscar evento o ubicación',
        ),
        hintStyle: TextStyle(
          color: const Color(0xFF8C8C8C),
          fontSize: isTabletLayout ? 15.2 : 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: _gold,
          size: isTabletLayout ? 24 : 20,
        ),
        suffixIcon: IconButton(
          onPressed: _openSearchResults,
          icon: Icon(
            Icons.arrow_forward_rounded,
            color: _gold,
            size: isTabletLayout ? 24 : 20,
          ),
        ),
        filled: true,
        fillColor: _panelBlack,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isTabletLayout ? 14 : 11,
          vertical: isTabletLayout ? 12 : 9,
        ),
        isDense: !isTabletLayout,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withOpacity(0.24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.2),
        ),
      ),
    );
  }

  Widget _buildCompactDiscoveryControls({required bool isTabletLayout}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTabletLayout ? 12 : 10,
        isTabletLayout ? 11 : 9,
        isTabletLayout ? 12 : 10,
        isTabletLayout ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildCompactFilterButton(
                  label: _t(nl: 'Datum', en: 'Date', fr: 'Date', es: 'Fecha'),
                  value: _dateFilterLabel(_selectedDateMode),
                  icon: Icons.calendar_month_rounded,
                  onTap: _openDatePicker,
                  isTabletLayout: isTabletLayout,
                ),
              ),
              SizedBox(width: isTabletLayout ? 10 : 8),
              Expanded(
                child: _buildCompactFilterButton(
                  label: _t(
                    nl: 'Categorie',
                    en: 'Category',
                    fr: 'Categorie',
                    es: 'Categoria',
                  ),
                  value: _categoryFilterLabel(_selectedCategoryKey),
                  icon: Icons.grid_view_rounded,
                  onTap: _openCategoryPicker,
                  isTabletLayout: isTabletLayout,
                ),
              ),
              SizedBox(width: isTabletLayout ? 10 : 8),
              Expanded(
                child: _buildCompactFilterButton(
                  label: _t(
                    nl: 'Sorteren',
                    en: 'Sort',
                    fr: 'Trier',
                    es: 'Ordenar',
                  ),
                  value: _sortModeLabel(_selectedSortMode),
                  icon: Icons.swap_vert_rounded,
                  onTap: _openSortPicker,
                  isTabletLayout: isTabletLayout,
                ),
              ),
            ],
          ),
          SizedBox(height: isTabletLayout ? 10 : 8),
          Row(
            children: [
              _buildRegionSelectorChip(isTabletLayout: isTabletLayout),
              SizedBox(width: isTabletLayout ? 10 : 8),
              Expanded(
                child: _buildActiveSummaryBar(isTabletLayout: isTabletLayout),
              ),
            ],
          ),
          SizedBox(height: isTabletLayout ? 10 : 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openEventAiAssistant,
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF161616),
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withOpacity(0.34)),
                minimumSize: Size.fromHeight(isTabletLayout ? 50 : 37),
                padding: EdgeInsets.symmetric(
                  horizontal: isTabletLayout ? 12 : 10,
                  vertical: isTabletLayout ? 10 : 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(
                Icons.auto_awesome_rounded,
                size: isTabletLayout ? 20 : 16,
              ),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _t(
                    nl: 'Vraag Fluxidi AI',
                    en: 'Ask Fluxidi AI',
                    fr: 'Demander à Fluxidi AI',
                    es: 'Preguntar a Fluxidi AI',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isTabletLayout ? 14.8 : 12.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFilterButton({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    required bool isTabletLayout,
  }) {
    return Material(
      color: const Color(0xFF161616),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isTabletLayout ? 10 : 8,
            isTabletLayout ? 10 : 7,
            isTabletLayout ? 10 : 8,
            isTabletLayout ? 10 : 7,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: isTabletLayout ? 18 : 13,
                color: _gold.withOpacity(0.95),
              ),
              SizedBox(width: isTabletLayout ? 7 : 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _softText.withOpacity(0.92),
                        fontSize: isTabletLayout ? 12.4 : 10.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isTabletLayout ? 3 : 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTabletLayout ? 14.4 : 11.4,
                        fontWeight: FontWeight.w700,
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
  }

  Widget _buildRegionSelectorChip({required bool isTabletLayout}) {
    return Material(
      color: const Color(0xFF161616),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _openMarketPicker,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isTabletLayout ? 13 : 10,
            vertical: isTabletLayout ? 9 : 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_rounded,
                size: isTabletLayout ? 17 : 13,
                color: _gold.withOpacity(0.95),
              ),
              SizedBox(width: isTabletLayout ? 6 : 4),
              Text(
                _marketLabel(_selectedMarketKey),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTabletLayout ? 14.2 : 11.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSummaryBar({required bool isTabletLayout}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isTabletLayout ? 12 : 9,
        vertical: isTabletLayout ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.26)),
      ),
      child: Text(
        _activeFilterSummaryText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _gold,
          fontSize: isTabletLayout ? 13.2 : 10.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCategoryTile(
    String categoryKey, {
    required double iconSize,
    required double labelFontSize,
    required int labelMaxLines,
    required double contentInset,
    required double labelSpacing,
  }) {
    final selected = _selectedCategoryKey == categoryKey;
    final icon = categoryKey == 'all'
        ? Icons.grid_view_rounded
        : (eventCategoryMetaByKey(categoryKey)?.icon ?? Icons.event_rounded);
    final imageProvider = _categoryImageProvider(categoryKey);
    final fallbackGradient = _categoryTileGradient(categoryKey);
    return GestureDetector(
      onTap: () async {
        setState(() => _selectedCategoryKey = categoryKey);
        await _openResultsPage(
          title: _categoryFilterLabel(categoryKey),
          categoryKey: categoryKey,
          searchQuery: _searchController.text,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _gold : _gold.withOpacity(0.16),
            width: selected ? 1.3 : 0.9,
          ),
          color: _panelBlack,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: imageProvider,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: fallbackGradient,
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withOpacity(0.08),
                    Colors.black.withOpacity(0.34),
                    Colors.black.withOpacity(0.68),
                  ],
                ),
              ),
            ),
            Positioned(
              left: contentInset,
              right: contentInset,
              bottom: contentInset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: iconSize, color: _gold),
                  SizedBox(height: labelSpacing),
                  Text(
                    _categoryFilterLabel(categoryKey),
                    maxLines: labelMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthFilterOption {
  const _MonthFilterOption({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;
}
