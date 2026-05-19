import 'dart:async';

import 'package:flutter/material.dart';

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

  const DirectRideDestinationDialog({
    super.key,
    required this.initialText,
    required this.search,
    required this.tr,
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
    return AlertDialog(
      title: Text(
        widget.tr(
          nl: 'Straatrit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        ),
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
              decoration: InputDecoration(
                labelText: widget.tr(
                  nl: 'Bestemming',
                  en: 'Destination',
                  fr: 'Destination',
                  es: 'Destino',
                ),
                hintText: widget.tr(
                  nl: 'Typ minstens 3 tekens',
                  en: 'Type at least 3 characters',
                  fr: 'Tapez au moins 3 caracteres',
                  es: 'Escribe al menos 3 caracteres',
                ),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                  color: const Color(0xFF0B0F1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x44FFD54A)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0x22FFFFFF)),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        suggestion.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
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
  }
}
