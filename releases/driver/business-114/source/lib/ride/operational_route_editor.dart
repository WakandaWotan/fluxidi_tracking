import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
import 'package:flutter/material.dart';
import '../app_strings.dart';
import '../limousine/limousine_address_field.dart';
import '../limousine/limousine_address_lookup.dart';
import '../limousine/limousine_p2d4c1a_ux.dart';
import 'operational_route.dart';
import 'operational_route_labels.dart';

Future<OperationalRoute?> showOperationalRouteEditor(
  BuildContext context, {
  required OperationalRouteApi api,
  required AppLanguage language,
}) => showDialog<OperationalRoute>(
  context: context,
  barrierDismissible: false,
  builder: (_) => OperationalRouteEditor(api: api, language: language),
);

class OperationalRouteEditor extends StatefulWidget {
  const OperationalRouteEditor({
    super.key,
    required this.api,
    required this.language,
    this.lookup,
    this.now,
  });
  final OperationalRouteApi api;
  final AppLanguage language;
  final LimousinePlaceLookup? lookup;
  final DateTime Function()? now;
  @override
  State<OperationalRouteEditor> createState() => _OperationalRouteEditorState();
}

class _OperationalRouteEditorState extends State<OperationalRouteEditor> {
  late final LimousinePlaceLookup _lookup =
      widget.lookup ?? OfficialAddressLookup(driverSession: true);
  late final LimousineAddressFieldController _address =
      LimousineAddressFieldController(
        lookup: _lookup,
        fieldId: 'operational_destination',
        language: widget.language.name,
      );
  final _minutes = TextEditingController();
  OperationalRideState? _ride;
  Map<String, dynamic>? _pending;
  String? _error;
  bool _loading = true, _saving = false;
  final _stops = <_StopDraft>[];
  int _stopIdentity = 0;
  bool _complete = false;
  bool get _editable => !_saving && _pending == null && _ride != null;
  _StopDraft _newStop([OperationalStop? value]) => _StopDraft(
    _lookup,
    widget.language,
    'operational_stop_${_stopIdentity++}',
    value,
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _address.dispose();
    _minutes.dispose();
    for (final stop in _stops) stop.dispose();
    if (widget.lookup == null) _lookup.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_saving) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _pending = await widget.api.pending();
      final ride = await widget.api.load();
      if (!mounted) return;
      _ride = ride;
      for (final stop in _stops) stop.dispose();
      _stops.clear();
      final route = _pending == null
          ? ride.route
          : OperationalRoute.fromMap(_pending);
      if (route != null) {
        _stops.addAll(route.remainingStops.map(_newStop));
        _complete = route.remainingRouteComplete;
        _address.selectSuggestion(
          LimousinePlaceSuggestion(
            label: route.address,
            lat: route.latitude,
            lon: route.longitude,
          ),
        );
        final remaining = route.expectedEnd
            .difference((widget.now ?? DateTime.now)())
            .inMinutes;
        _minutes.text = remaining.clamp(1, 1440).toString();
      } else {
        _complete = false;
      }
    } on OperationalRouteException catch (error) {
      if (mounted) _error = operationalRouteError(error.code, widget.language);
    } catch (_) {
      if (mounted)
        _error = operationalRouteError('request_failed', widget.language);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _ride == null || _loading) return;
    if (_pending == null) {
      final value = _address.value,
          minutes = int.tryParse(_minutes.text.trim());
      if (!value.isRouteReady ||
          !value.hasCoordinates ||
          value.routeText.isEmpty ||
          minutes == null ||
          minutes < 1 ||
          minutes > 1440) {
        setState(() => _error = kOperationalRouteInvalid.of(widget.language));
        return;
      }
      final stops = _stops.map((stop) => stop.value()).toList();
      final end = (widget.now ?? DateTime.now)().add(
        Duration(minutes: minutes),
      );
      if (stops.any(
            (stop) =>
                stop == null ||
                stop.notBefore != null && stop.notBefore!.isAfter(end),
          ) ||
          stops.whereType<OperationalStop>().fold<int>(
                0,
                (sum, stop) => sum + stop.waitSeconds,
              ) >
              86400 ||
          (_ride!.requiresItinerary || _stops.isNotEmpty) && !_complete) {
        setState(
          () => _error = kOperationalItineraryInvalid.of(widget.language),
        );
        return;
      }
      _pending = widget.api.prepare(
        OperationalRoute(
          address: value.routeText,
          latitude: value.lat!,
          longitude: value.lon!,
          expectedEnd: (widget.now ?? DateTime.now)().add(
            Duration(minutes: minutes),
          ),
          remainingStops: stops.whereType<OperationalStop>().toList(),
          remainingRouteComplete: _complete,
        ),
        _ride!,
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final route = await widget.api.save(_pending!);
      if (mounted) Navigator.of(context).pop(route);
    } on OperationalRouteException catch (error) {
      if (!mounted) return;
      if (!error.uncertain) {
        _pending = null;
        _ride = null;
      }
      _error = error.uncertain
          ? kOperationalRoutePending.of(widget.language)
          : operationalRouteError(error.code, widget.language);
    } catch (_) {
      if (mounted) _error = kOperationalRoutePending.of(widget.language);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _departure(_StopDraft stop) async {
    final now = (widget.now ?? DateTime.now)().toLocal(),
        initial = (stop.notBefore ?? now).toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted || !_editable) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted || !_editable) return;
    setState(
      () => stop.notBefore = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language, theme = Theme.of(context);
    final tokens = LimousineUxTokens.fromSurface(
      background: theme.colorScheme.surface,
      gold: theme.colorScheme.primary,
    );
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(kOperationalRouteEdit.of(lang)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kOperationalRouteExplanation.of(lang)),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (_pending != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(kOperationalRoutePending.of(lang)),
                    ),
                  AbsorbPointer(
                    absorbing: _saving || _pending != null || _ride == null,
                    child: LimousineAddressField(
                      controller: _address,
                      label: kOperationalRouteDestination.of(lang),
                      tokens: tokens,
                      language: lang,
                      inputKey: const Key('operational_route_address'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('operational_route_minutes'),
                    controller: _minutes,
                    enabled: !_saving && _pending == null && _ride != null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: kOperationalRouteMinutes.of(lang),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(kOperationalStops.of(lang)),
                  for (final (index, stop) in _stops.indexed)
                    Padding(
                      key: ValueKey(stop.id),
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AbsorbPointer(
                            absorbing: !_editable,
                            child: LimousineAddressField(
                              controller: stop.address,
                              label:
                                  '${index + 1}. ${kOperationalRouteDestination.of(lang)}',
                              tokens: tokens,
                              language: lang,
                              inputKey: ValueKey('${stop.id}_address'),
                            ),
                          ),
                          TextField(
                            key: ValueKey('${stop.id}_wait'),
                            controller: stop.wait,
                            enabled: _editable,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: kOperationalStopWait.of(lang),
                            ),
                          ),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _editable
                                    ? () => _departure(stop)
                                    : null,
                                child: Text(
                                  '${kOperationalNotBefore.of(lang)}: ${stop.notBefore == null ? '—' : MaterialLocalizations.of(context).formatShortDate(stop.notBefore!.toLocal()) + ' ' + MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(stop.notBefore!.toLocal()), alwaysUse24HourFormat: true)}',
                                ),
                              ),
                              if (stop.notBefore != null)
                                IconButton(
                                  tooltip: MaterialLocalizations.of(
                                    context,
                                  ).deleteButtonTooltip,
                                  onPressed: _editable
                                      ? () => setState(
                                          () => stop.notBefore = null,
                                        )
                                      : null,
                                  icon: const Icon(Icons.close),
                                ),
                              IconButton(
                                tooltip: kOperationalStopEarlier.of(lang),
                                onPressed: _editable && index > 0
                                    ? () => setState(() {
                                        final previous = _stops[index - 1];
                                        _stops[index - 1] = stop;
                                        _stops[index] = previous;
                                      })
                                    : null,
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: kOperationalRemoveStop.of(lang),
                                onPressed: _editable
                                    ? () => setState(() {
                                        _stops.remove(stop);
                                        stop.dispose();
                                      })
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    key: const Key('operational_add_stop'),
                    onPressed: _editable && _stops.length < 8
                        ? () => setState(() => _stops.add(_newStop()))
                        : null,
                    icon: const Icon(Icons.add),
                    label: Text(kOperationalAddStop.of(lang)),
                  ),
                  if (_ride?.requiresItinerary == true ||
                      _stops.isNotEmpty ||
                      _complete)
                    CheckboxListTile(
                      key: const Key('operational_itinerary_complete'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(kOperationalComplete.of(lang)),
                      value: _complete,
                      onChanged: _editable
                          ? (value) => setState(() => _complete = value == true)
                          : null,
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      key: const Key('operational_route_error'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
          FilledButton(
            key: const Key('operational_route_save'),
            onPressed: _loading || _saving
                ? null
                : _ride == null
                ? _load
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    (_pending != null || _ride == null
                            ? kOperationalRouteRetry
                            : kOperationalRouteSave)
                        .of(lang),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StopDraft {
  _StopDraft(
    LimousinePlaceLookup lookup,
    AppLanguage language,
    this.id,
    OperationalStop? value,
  ) : address = LimousineAddressFieldController(
        lookup: lookup,
        fieldId: id,
        language: language.name,
      ),
      wait = TextEditingController(text: '${(value?.waitSeconds ?? 0) ~/ 60}'),
      notBefore = value?.notBefore {
    if (value != null)
      address.selectSuggestion(
        LimousinePlaceSuggestion(
          label: value.address,
          lat: value.latitude,
          lon: value.longitude,
        ),
      );
  }
  final String id;
  final LimousineAddressFieldController address;
  final TextEditingController wait;
  DateTime? notBefore;
  OperationalStop? value() {
    final place = address.value, minutes = int.tryParse(wait.text.trim());
    if (!place.isRouteReady ||
        !place.hasCoordinates ||
        minutes == null ||
        minutes < 0 ||
        minutes > 720)
      return null;
    return OperationalStop(
      address: place.routeText,
      latitude: place.lat!,
      longitude: place.lon!,
      waitSeconds: minutes * 60,
      notBefore: notBefore,
    );
  }

  void dispose() {
    address.dispose();
    wait.dispose();
  }
}
