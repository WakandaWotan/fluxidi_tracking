import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

import 'event_models.dart';
import 'events_detail_page.dart';

class SavedEventsPage extends StatefulWidget {
  const SavedEventsPage({this.onBookEvent, super.key});

  final EventBookCallback? onBookEvent;

  @override
  State<SavedEventsPage> createState() => _SavedEventsPageState();
}

class _SavedEventsPageState extends State<SavedEventsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  final EventLocalSavedStore _savedStore = const EventLocalSavedStore();
  Map<String, SavedEventRecord> _savedByKey =
      const <String, SavedEventRecord>{};
  String _activeFilter = 'all';

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
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final items = await _savedStore.loadAll();
    if (!mounted) return;
    setState(() => _savedByKey = items);
  }

  List<SavedEventRecord> get _visibleRecords {
    final all = _savedByKey.values
        .where((record) {
          if (_activeFilter == 'favorites') return record.favorite;
          return true;
        })
        .toList(growable: false);
    all.sort((a, b) {
      final aSaved = DateTime.tryParse(a.savedAtUtc);
      final bSaved = DateTime.tryParse(b.savedAtUtc);
      if (aSaved == null && bSaved == null) return a.title.compareTo(b.title);
      if (aSaved == null) return 1;
      if (bSaved == null) return -1;
      return bSaved.compareTo(aSaved);
    });
    return all;
  }

  String _cardImageUrl(SavedEventRecord record) {
    return (record.thumbnailUrl.isNotEmpty
            ? record.thumbnailUrl
            : (record.imageUrl.isNotEmpty
                  ? record.imageUrl
                  : record.heroImageUrl))
        .trim();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleFavorite(SavedEventRecord record) async {
    final nextFavorite = !record.favorite;
    final optimistic = Map<String, SavedEventRecord>.from(_savedByKey);
    final existing = optimistic[record.storageKey];
    if (existing != null) {
      optimistic[record.storageKey] = existing.copyWith(favorite: nextFavorite);
      setState(() => _savedByKey = optimistic);
    }
    _showSnackBar(
      nextFavorite
          ? _t(
              nl: 'Toegevoegd aan favorieten',
              en: 'Added to favorites',
              fr: 'Ajoute aux favoris',
              es: 'Anadido a favoritos',
            )
          : _t(
              nl: 'Verwijderd uit favorieten',
              en: 'Removed from favorites',
              fr: 'Retire des favoris',
              es: 'Eliminado de favoritos',
            ),
    );
    final updated = await _savedStore.updateFavoriteByKey(
      storageKey: record.storageKey,
      favorite: nextFavorite,
    );
    if (!mounted) return;
    setState(() => _savedByKey = updated);
  }

  Future<void> _removeSaved(SavedEventRecord record) async {
    final updated = await _savedStore.removeByKey(record.storageKey);
    if (!mounted) return;
    setState(() => _savedByKey = updated);
    _showSnackBar(
      _t(
        nl: 'Event verwijderd uit opgeslagen lijst',
        en: 'Event removed from saved list',
        fr: 'Evenement retire de la liste enregistree',
        es: 'Evento eliminado de la lista guardada',
      ),
    );
  }

  Future<void> _openDetails(SavedEventRecord record) async {
    final event = record.toEventDetailData();
    await Navigator.of(context).push(
      MaterialPageRoute<EventDetailPage>(
        builder: (_) =>
            EventDetailPage(event: event, onBookEvent: widget.onBookEvent),
      ),
    );
    if (!mounted) return;
    _loadSaved();
  }

  void _bookSavedEvent(SavedEventRecord record) {
    final event = record.toEventDetailData();
    if (widget.onBookEvent != null) {
      widget.onBookEvent!.call(event);
      return;
    }
    _showSnackBar(
      _t(
        nl: 'Boekingsflow voor dit event is binnenkort beschikbaar.',
        en: 'Booking flow for this event is coming soon.',
        fr: 'Le flux de réservation pour cet événement arrive bientôt.',
        es: 'El flujo de reserva para este evento estará disponible pronto.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _visibleRecords;
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                children: [
                  _buildFilterChips(),
                  const SizedBox(height: 12),
                  if (records.isEmpty)
                    _buildEmptyState()
                  else
                    _buildSavedList(records),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: _gold,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _panelBlack.withOpacity(0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withOpacity(0.2)),
              ),
              child: Text(
                _t(
                  nl: 'Opgeslagen events',
                  en: 'Saved events',
                  fr: 'Evenements enregistres',
                  es: 'Eventos guardados',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = <(String, String)>[
      ('all', _t(nl: 'Alles', en: 'All', fr: 'Tout', es: 'Todo')),
      (
        'favorites',
        _t(nl: 'Favorieten', en: 'Favorites', fr: 'Favoris', es: 'Favoritos'),
      ),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = filters[index].$1;
          final selected = key == _activeFilter;
          return ChoiceChip(
            label: Text(
              filters[index].$2,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            selected: selected,
            onSelected: (_) => setState(() => _activeFilter = key),
            selectedColor: _gold,
            backgroundColor: _panelBlack,
            shape: StadiumBorder(
              side: BorderSide(color: _gold.withOpacity(selected ? 0.1 : 0.32)),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 11),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          );
        },
      ),
    );
  }

  Widget _buildSavedList(List<SavedEventRecord> records) {
    return Column(
      children: [
        for (var i = 0; i < records.length; i++) ...[
          _buildSavedCard(records[i]),
          if (i != records.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSavedCard(SavedEventRecord record) {
    final imageUrl = _cardImageUrl(record);
    final event = record.toEventDetailData();
    return Container(
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openDetails(record),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: event.gradient,
                  ),
                ),
                child: Stack(
                  children: [
                    if (imageUrl.isNotEmpty)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 1024,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    if (imageUrl.isNotEmpty)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.black.withOpacity(0.22),
                                Colors.black.withOpacity(0.56),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      top: 10,
                      child: _chip(
                        label: event.category,
                        icon:
                            eventCategoryMetaByKey(
                              event.resolvedCategoryKey,
                            )?.icon ??
                            Icons.event_rounded,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 6,
                      child: IconButton(
                        onPressed: () => _toggleFavorite(record),
                        icon: Icon(
                          record.favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                        iconSize: 18,
                        color: record.favorite
                            ? _gold
                            : Colors.white.withOpacity(0.92),
                        tooltip: _t(
                          nl: 'Favoriet',
                          en: 'Favorite',
                          fr: 'Favori',
                          es: 'Favorito',
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -2,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Text(
                        record.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.4,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaRow(Icons.calendar_today_outlined, event.dateTimeLabel),
                const SizedBox(height: 6),
                _metaRow(
                  Icons.location_on_outlined,
                  '${record.locationName}, ${record.city}',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _bookSavedEvent(record),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFF171209),
                          foregroundColor: _gold,
                          side: BorderSide(color: _gold.withOpacity(0.55)),
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.local_taxi_rounded, size: 16),
                        label: Text(
                          _t(
                            nl: 'Taxi boeken',
                            en: 'Book taxi',
                            fr: 'Reserver taxi',
                            es: 'Reservar taxi',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _removeSaved(record),
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: _gold.withOpacity(0.95),
                      tooltip: _t(
                        nl: 'Verwijderen',
                        en: 'Remove',
                        fr: 'Supprimer',
                        es: 'Eliminar',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        children: [
          Text(
            _t(
              nl: 'Nog geen opgeslagen events',
              en: 'No saved events yet',
              fr: 'Aucun evenement enregistre',
              es: 'Aun no hay eventos guardados',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              nl: 'Opgeslagen en favoriete events verschijnen hier.',
              en: 'Saved and favorite events will appear here.',
              fr: 'Les evenements enregistres et favoris apparaitront ici.',
              es: 'Los eventos guardados y favoritos apareceran aqui.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _softText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _gold.withOpacity(0.95)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _softText, fontSize: 11.9),
          ),
        ),
      ],
    );
  }

  Widget _chip({required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _gold, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: _gold,
              fontSize: 10.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
