// COMPANY-CUSTOMER-OPS-P0 — shared date/time fields for quote, plan, reschedule.
// Display follows existing Fluxidi local date/time conventions. The form never
// shows a technical ISO timestamp. Picker cancel keeps the previous value.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';

const LocalizedText kCompanyFormDate = LocalizedText(
  nl: 'Datum',
  en: 'Date',
  fr: 'Date',
  es: 'Fecha',
);

const LocalizedText kCompanyFormTime = LocalizedText(
  nl: 'Tijd',
  en: 'Time',
  fr: 'Heure',
  es: 'Hora',
);

Key companyFormDateFieldKey(String id) =>
    ValueKey<String>('company_form_date_$id');

Key companyFormTimeFieldKey(String id) =>
    ValueKey<String>('company_form_time_$id');

Key companyFormDateIconKey(String id) =>
    ValueKey<String>('company_form_date_icon_$id');

Key companyFormTimeIconKey(String id) =>
    ValueKey<String>('company_form_time_icon_$id');

final RegExp _isoDatePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}');
final RegExp _numericDate = RegExp(
  r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$',
);
final RegExp _numericTime = RegExp(r'^(\d{1,2})[:.](\d{2})$');

const Map<AppLanguage, List<String>> kCompanyFormMonthNames =
    <AppLanguage, List<String>>{
      AppLanguage.nl: <String>[
        'januari',
        'februari',
        'maart',
        'april',
        'mei',
        'juni',
        'juli',
        'augustus',
        'september',
        'oktober',
        'november',
        'december',
      ],
      AppLanguage.en: <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ],
      AppLanguage.fr: <String>[
        'janvier',
        'février',
        'mars',
        'avril',
        'mai',
        'juin',
        'juillet',
        'août',
        'septembre',
        'octobre',
        'novembre',
        'décembre',
      ],
      AppLanguage.es: <String>[
        'enero',
        'febrero',
        'marzo',
        'abril',
        'mayo',
        'junio',
        'julio',
        'agosto',
        'septiembre',
        'octubre',
        'noviembre',
        'diciembre',
      ],
    };

bool companyFormLooksLikeIsoTimestamp(String raw) {
  final text = raw.trim();
  if (text.contains('T') && _isoDatePrefix.hasMatch(text)) return true;
  if (text.endsWith('Z') && _isoDatePrefix.hasMatch(text)) return true;
  return false;
}

String formatCompanyFormDate(DateTime local, AppLanguage language) {
  final months = kCompanyFormMonthNames[language] ?? kCompanyFormMonthNames[AppLanguage.nl]!;
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

String formatCompanyFormTime(DateTime local) {
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String formatCompanyFormDateTime(DateTime local, AppLanguage language) {
  return '${formatCompanyFormDate(local, language)} · ${formatCompanyFormTime(local)}';
}

DateTime? companyFormDateTimeFromIso(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

String companyFormIsoFromLocal(DateTime local) {
  return local.toUtc().toIso8601String();
}

DateTime? parseCompanyFormDate(String raw, AppLanguage language) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (companyFormLooksLikeIsoTimestamp(text) || _isoDatePrefix.hasMatch(text)) {
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      final local = parsed.toLocal();
      return DateTime(local.year, local.month, local.day);
    }
  }
  final numeric = _numericDate.firstMatch(text);
  if (numeric != null) {
    final day = int.parse(numeric.group(1)!);
    final month = int.parse(numeric.group(2)!);
    final year = int.parse(numeric.group(3)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(year, month, day);
    }
    return null;
  }
  final lower = text.toLowerCase();
  for (final months in kCompanyFormMonthNames.values) {
    for (var i = 0; i < months.length; i += 1) {
      final monthName = months[i].toLowerCase();
      final match = RegExp(
        r'^(\d{1,2})\s+' + RegExp.escape(monthName) + r'\s+(\d{4})$',
        caseSensitive: false,
      ).firstMatch(lower);
      if (match != null) {
        return DateTime(int.parse(match.group(2)!), i + 1, int.parse(match.group(1)!));
      }
    }
  }
  return null;
}

TimeOfDay? parseCompanyFormTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final match = _numericTime.firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

DateTime combineCompanyFormDateTime(DateTime date, TimeOfDay time) {
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class CompanyDateTimeFields extends StatefulWidget {
  const CompanyDateTimeFields({
    super.key,
    required this.fieldId,
    required this.language,
    required this.value,
    required this.onChanged,
    this.includeTime = true,
    this.enabled = true,
    this.dateLabel,
    this.timeLabel,
    this.scrollPadding = const EdgeInsets.fromLTRB(20, 20, 20, 160),
  });

  final String fieldId;
  final AppLanguage language;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool includeTime;
  final bool enabled;
  final String? dateLabel;
  final String? timeLabel;
  final EdgeInsets scrollPadding;

  @override
  State<CompanyDateTimeFields> createState() => _CompanyDateTimeFieldsState();
}

class _CompanyDateTimeFieldsState extends State<CompanyDateTimeFields> {
  late final TextEditingController _dateCtrl;
  late final TextEditingController _timeCtrl;

  DateTime? get _value => widget.value;

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: _dateText(_value));
    _timeCtrl = TextEditingController(text: _timeText(_value));
  }

  @override
  void didUpdateWidget(covariant CompanyDateTimeFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.language != widget.language) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  String _dateText(DateTime? value) {
    if (value == null) return '';
    return formatCompanyFormDate(value.toLocal(), widget.language);
  }

  String _timeText(DateTime? value) {
    if (value == null) return '';
    return formatCompanyFormTime(value.toLocal());
  }

  void _syncControllers() {
    final date = _dateText(_value);
    final time = _timeText(_value);
    if (_dateCtrl.text != date) _dateCtrl.text = date;
    if (_timeCtrl.text != time) _timeCtrl.text = time;
  }

  DateTime _anchor() => _value?.toLocal() ?? DateTime.now();

  void _commit(DateTime? next) {
    widget.onChanged(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncControllers();
    });
  }

  Future<void> _pickDate() async {
    if (!widget.enabled) return;
    final current = _anchor();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 2),
      helpText: kCompanyAgendaPickDate.of(widget.language),
      locale: Localizations.maybeLocaleOf(context),
    );
    if (!mounted || picked == null) return;
    final time = TimeOfDay.fromDateTime(_value?.toLocal() ?? current);
    _commit(combineCompanyFormDateTime(picked, time));
  }

  Future<void> _pickTime() async {
    if (!widget.enabled) return;
    final current = _anchor();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: kCompanyAgendaPickTime.of(widget.language),
    );
    if (!mounted || picked == null) return;
    _commit(combineCompanyFormDateTime(current, picked));
  }

  void _applyTypedDate() {
    final parsed = parseCompanyFormDate(_dateCtrl.text, widget.language);
    if (parsed == null) {
      _syncControllers();
      return;
    }
    final time = TimeOfDay.fromDateTime(_anchor());
    _commit(combineCompanyFormDateTime(parsed, time));
  }

  void _applyTypedTime() {
    final parsed = parseCompanyFormTime(_timeCtrl.text);
    if (parsed == null) {
      _syncControllers();
      return;
    }
    _commit(combineCompanyFormDateTime(_anchor(), parsed));
  }

  @override
  Widget build(BuildContext context) {
    final dateField = TextField(
      key: companyFormDateFieldKey(widget.fieldId),
      controller: _dateCtrl,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      scrollPadding: widget.scrollPadding,
      onTap: widget.enabled ? _pickDate : null,
      onEditingComplete: _applyTypedDate,
      onSubmitted: (_) => _applyTypedDate(),
      decoration: InputDecoration(
        labelText: widget.dateLabel ?? kCompanyFormDate.of(widget.language),
        suffixIcon: IconButton(
          key: companyFormDateIconKey(widget.fieldId),
          tooltip: kCompanyAgendaPickDate.of(widget.language),
          onPressed: widget.enabled ? _pickDate : null,
          icon: const Icon(Icons.calendar_today_outlined),
        ),
      ),
    );
    if (!widget.includeTime) return dateField;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: dateField),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            key: companyFormTimeFieldKey(widget.fieldId),
            controller: _timeCtrl,
            enabled: widget.enabled,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.next,
            scrollPadding: widget.scrollPadding,
            onTap: widget.enabled ? _pickTime : null,
            onEditingComplete: _applyTypedTime,
            onSubmitted: (_) => _applyTypedTime(),
            decoration: InputDecoration(
              labelText: widget.timeLabel ?? kCompanyFormTime.of(widget.language),
              suffixIcon: IconButton(
                key: companyFormTimeIconKey(widget.fieldId),
                tooltip: kCompanyAgendaPickTime.of(widget.language),
                onPressed: widget.enabled ? _pickTime : null,
                icon: const Icon(Icons.schedule_outlined),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<DateTime?> showCompanyDateTimeEditor({
  required BuildContext context,
  required AppLanguage language,
  required DateTime initial,
  String? title,
}) async {
  var current = initial.toLocal();
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title ?? kCompanyAgendaReschedule.of(language)),
        content: SingleChildScrollView(
          child: CompanyDateTimeFields(
            fieldId: 'reschedule',
            language: language,
            value: current,
            onChanged: (next) {
              if (next != null) current = next;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(kCompanyAgendaCancel.of(language)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, current),
            child: Text(kCompanyAgendaReschedule.of(language)),
          ),
        ],
      );
    },
  );
}
