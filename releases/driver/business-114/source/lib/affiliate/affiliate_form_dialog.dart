import 'dart:async';
import 'package:flutter/material.dart';
import '../app_strings.dart';
import 'affiliate_labels.dart';
import 'affiliate_repository.dart';

class AffiliateField {
  const AffiliateField(
    this.name,
    this.label, {
    this.initial = '',
    this.optional = false,
    this.options = const {},
    this.checkbox = false,
    this.numeric = false,
    this.dateTime = false,
    this.maxLength = 200,
    this.preserveWhitespace = false,
  });
  final String name, label, initial;
  final bool optional, checkbox, numeric, dateTime;
  final int maxLength;
  final bool preserveWhitespace;
  final Map<String, String> options;
}

Future<Map<String, String>?> showAffiliateForm(
  BuildContext context, {
  required AffiliateRepository repository,
  required AffiliateOwner owner,
  required String title,
  required List<AffiliateField> fields,
  String? description,
}) async {
  if (!repository.owns(owner)) return null;
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _AffiliateForm(
      repository: repository,
      owner: owner,
      title: title,
      fields: fields,
      description: description,
    ),
  );
  return repository.owns(owner) ? result : null;
}

class _AffiliateForm extends StatefulWidget {
  const _AffiliateForm({
    required this.repository,
    required this.owner,
    required this.title,
    required this.fields,
    this.description,
  });
  final AffiliateRepository repository;
  final AffiliateOwner owner;
  final String title;
  final String? description;
  final List<AffiliateField> fields;
  @override
  State<_AffiliateForm> createState() => _AffiliateFormState();
}

class _AffiliateFormState extends State<_AffiliateForm> {
  final _key = GlobalKey<FormState>();
  final _text = <String, TextEditingController>{};
  final _values = <String, String>{};
  Timer? _expiry;
  bool _closing = false;
  ModalRoute<dynamic>? _route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      if (field.options.isNotEmpty || field.checkbox)
        _values[field.name] = field.initial;
      else
        _text[field.name] = TextEditingController(text: field.initial);
    }
    widget.repository.revision.addListener(_identityChanged);
    final expiry = DateTime.tryParse(widget.owner.session.expiresAt);
    if (expiry != null)
      _expiry = Timer(
        expiry.toUtc().difference(DateTime.now().toUtc()),
        _identityChanged,
      );
  }

  void _identityChanged() {
    if (!mounted || _closing || widget.repository.owns(widget.owner)) return;
    _closing = true;
    for (final controller in _text.values) {
      controller.clear();
    }
    _values.clear();
    final route = _route;
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent)
      navigator.pop();
    else
      navigator.removeRoute(route);
  }

  Future<void> _pickDateTime(AffiliateField field) async {
    if (!widget.repository.owns(widget.owner)) return;
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (!mounted || day == null || !widget.repository.owns(widget.owner))
      return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted || time == null || !widget.repository.owns(widget.owner))
      return;
    final local = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    _values[field.name] = local.toUtc().toIso8601String();
    _text[field.name]!.text =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    widget.repository.revision.removeListener(_identityChanged);
    _expiry?.cancel();
    for (final controller in _text.values) {
      controller.dispose();
    }
    _values.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: appLanguageNotifier,
    builder: (context, language, _) {
      String t(String key) => affiliateLabel(key, language);
      return AlertDialog(
        title: Text(t(widget.title)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.description != null) Text(t(widget.description!)),
                  for (final field in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: field.checkbox
                          ? CheckboxListTile(
                              key: Key('affiliate_form_${field.name}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(t(field.label)),
                              value: _values[field.name] == 'true',
                              onChanged: (value) => setState(
                                () => _values[field.name] = '$value',
                              ),
                            )
                          : field.options.isNotEmpty
                          ? DropdownButtonFormField<String>(
                              key: Key('affiliate_form_${field.name}'),
                              initialValue:
                                  field.options.containsKey(_values[field.name])
                                  ? _values[field.name]
                                  : null,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t(field.label),
                              ),
                              items: field.options.entries
                                  .map(
                                    (entry) => DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(t(entry.value)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  _values[field.name] = value ?? '',
                              validator: (value) =>
                                  value == null ? t('required') : null,
                            )
                          : TextFormField(
                              key: Key('affiliate_form_${field.name}'),
                              controller: _text[field.name],
                              readOnly: field.dateTime,
                              onTap: field.dateTime
                                  ? () => _pickDateTime(field)
                                  : null,
                              maxLength: field.maxLength,
                              keyboardType: field.numeric
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : null,
                              decoration: InputDecoration(
                                labelText: t(field.label),
                              ),
                              validator: (value) =>
                                  !field.optional &&
                                      (value ?? '').trim().isEmpty
                                  ? t('required')
                                  : null,
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('cancel')),
          ),
          FilledButton(
            key: const Key('affiliate_form_submit'),
            onPressed: () {
              if (!widget.repository.owns(widget.owner)) {
                _identityChanged();
                return;
              }
              if (!_key.currentState!.validate() ||
                  widget.fields.any(
                    (field) =>
                        field.checkbox &&
                        !field.optional &&
                        _values[field.name] != 'true',
                  ))
                return;
              Navigator.of(context).pop(<String, String>{
                ..._values,
                for (final entry in _text.entries)
                  entry.key:
                      widget.fields.any(
                        (field) => field.name == entry.key && field.dateTime,
                      )
                      ? _values[entry.key] ?? ''
                      : widget.fields.any(
                          (field) =>
                              field.name == entry.key &&
                              field.preserveWhitespace,
                        )
                      ? entry.value.text
                      : entry.value.text.trim(),
              });
            },
            child: Text(t('confirm')),
          ),
        ],
      );
    },
  );
}

int? affiliateCentsInput(String value) {
  if (!RegExp(r'^\d{1,12}([.,]\d{1,2})?$').hasMatch(value.trim())) return null;
  final parts = value.trim().replaceAll(',', '.').split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}
