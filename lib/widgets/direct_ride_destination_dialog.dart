import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

class _DirectRideDestinationTheme {
  const _DirectRideDestinationTheme({
    required this.dialogBg,
    required this.fieldFill,
    required this.fieldBorder,
    required this.fieldFocusedBorder,
    required this.panelBg,
    required this.panelBorder,
    required this.divider,
    required this.primaryText,
    required this.mutedText,
    required this.accent,
    required this.buttonForeground,
  });

  final Color dialogBg;
  final Color fieldFill;
  final Color fieldBorder;
  final Color fieldFocusedBorder;
  final Color panelBg;
  final Color panelBorder;
  final Color divider;
  final Color primaryText;
  final Color mutedText;
  final Color accent;
  final Color buttonForeground;
}

_DirectRideDestinationTheme _themeForDriverVariant(DriverThemeVariant variant) {
  if (variant == DriverThemeVariant.midnightBlue) {
    return const _DirectRideDestinationTheme(
      dialogBg: Color(0xFF0A1222),
      fieldFill: Color(0xFF0E1A2D),
      fieldBorder: Color(0x665A9DD9),
      fieldFocusedBorder: Color(0xFF4DA3FF),
      panelBg: Color(0xFF0E1A2E),
      panelBorder: Color(0x665A9DD9),
      divider: Color(0x3378B5E5),
      primaryText: Color(0xFFEAF6FF),
      mutedText: Color(0xFFAFCBEA),
      accent: Color(0xFF4DA3FF),
      buttonForeground: Color(0xFF041729),
    );
  }
  if (variant == DriverThemeVariant.highContrast) {
    return const _DirectRideDestinationTheme(
      dialogBg: Color(0xFF1E1409),
      fieldFill: Color(0xFF2A1B0D),
      fieldBorder: Color(0x66E0BE79),
      fieldFocusedBorder: Color(0xFFE8C57E),
      panelBg: Color(0xFF24170A),
      panelBorder: Color(0x66E8C57E),
      divider: Color(0x33E8C57E),
      primaryText: Color(0xFFFFF0D0),
      mutedText: Color(0xFFE1CCA0),
      accent: Color(0xFFFFDFA3),
      buttonForeground: Color(0xFF3C2405),
    );
  }
  if (variant == DriverThemeVariant.lightEmerald) {
    return const _DirectRideDestinationTheme(
      dialogBg: Color(0xFFF4FAF7),
      fieldFill: Color(0xFFFFFFFF),
      fieldBorder: Color(0x66B7CEC4),
      fieldFocusedBorder: Color(0xFF1F8A65),
      panelBg: Color(0xFFE4F1EB),
      panelBorder: Color(0x66B7CEC4),
      divider: Color(0x331F8A65),
      primaryText: Color(0xFF143028),
      mutedText: Color(0xFF4A665C),
      accent: Color(0xFF1F8A65),
      buttonForeground: Color(0xFFFFFFFF),
    );
  }
  return const _DirectRideDestinationTheme(
    dialogBg: Color(0xFF121212),
    fieldFill: Color(0xFF121212),
    fieldBorder: Color(0x55E5B641),
    fieldFocusedBorder: Color(0xFFE5B641),
    panelBg: Color(0xFF0B0F1C),
    panelBorder: Color(0x44FFD54A),
    divider: Color(0x22FFFFFF),
    primaryText: Colors.white,
    mutedText: Color(0xFFB6B6B6),
    accent: Color(0xFFE5B641),
    buttonForeground: Colors.black,
  );
}

typedef DirectRideTranslate =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

class DirectRideSuggestion {
  final String label;
  final double? lon;
  final double? lat;

  const DirectRideSuggestion({required this.label, this.lon, this.lat});
}

class DirectRideDestinationResult {
  final String label;
  final double? lon;
  final double? lat;

  const DirectRideDestinationResult({required this.label, this.lon, this.lat});
}

class DirectRideDestinationDialog extends StatefulWidget {
  final String initialText;
  final Future<List<DirectRideSuggestion>> Function(String query) search;
  final DirectRideTranslate tr;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DirectRideDestinationDialog({
    super.key,
    required this.initialText,
    required this.search,
    required this.tr,
    this.themeListenable,
  });

  @override
  State<DirectRideDestinationDialog> createState() =>
      _DirectRideDestinationDialogState();
}

class _DirectRideDestinationDialogState
    extends State<DirectRideDestinationDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<DirectRideSuggestion> _suggestions = <DirectRideSuggestion>[];
  DirectRideSuggestion? _selected;
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _selected = null;
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() {
        _loading = false;
        _searched = false;
        _suggestions = <DirectRideSuggestion>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _searched = true;
      });
      final results = await widget.search(q);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _suggestions = results;
      });
    });
  }

  void _pick(DirectRideSuggestion suggestion) {
    setState(() {
      _selected = suggestion;
      _controller.text = suggestion.label;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _suggestions = <DirectRideSuggestion>[];
      _searched = false;
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final selected = _selected;
    Navigator.of(context).pop(
      DirectRideDestinationResult(
        label: selected?.label ?? text,
        lon: selected?.lon,
        lat: selected?.lat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: widget.themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final theme = _themeForDriverVariant(variant);
        return AlertDialog(
          backgroundColor: theme.dialogBg,
          title: Text(
            widget.tr(
              nl: 'Straatrit',
              en: 'Direct ride',
              fr: 'Course directe',
              es: 'Viaje directo',
            ),
            style: TextStyle(color: theme.primaryText),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(color: theme.primaryText),
                  decoration: InputDecoration(
                    labelText: widget.tr(
                      nl: 'Bestemming',
                      en: 'Destination',
                      fr: 'Destination',
                      es: 'Destino',
                    ),
                    labelStyle: TextStyle(color: theme.mutedText),
                    hintText: widget.tr(
                      nl: 'Typ minstens 3 tekens',
                      en: 'Type at least 3 characters',
                      fr: 'Tapez au moins 3 caracteres',
                      es: 'Escribe al menos 3 caracteres',
                    ),
                    hintStyle: TextStyle(color: theme.mutedText),
                    filled: true,
                    fillColor: theme.fieldFill,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.fieldFocusedBorder),
                    ),
                    suffixIcon: _loading
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.accent,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: theme.panelBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.panelBorder),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: theme.divider),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            suggestion.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: theme.primaryText),
                          ),
                          onTap: () => _pick(suggestion),
                        );
                      },
                    ),
                  )
                else if (_searched && !_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.tr(
                          nl: 'Geen adres gevonden',
                          en: 'No address found',
                          fr: 'Aucune adresse trouvee',
                          es: 'No se encontro direccion',
                        ),
                        style: TextStyle(color: theme.mutedText, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: theme.mutedText),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                widget.tr(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.buttonForeground,
              ),
              onPressed: _submit,
              child: Text(
                widget.tr(
                  nl: 'Doorgaan',
                  en: 'Continue',
                  fr: 'Continuer',
                  es: 'Continuar',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
