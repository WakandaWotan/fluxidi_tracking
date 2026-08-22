import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import 'limousine_offers.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';
import 'limousine_quote_presentation.dart';

class LimousineQuoteEditorPage extends StatefulWidget {
  LimousineQuoteEditorPage({
    super.key,
    required this.record,
    this.onSubmit,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final LimousineQuoteRequest record;
  final Future<void> Function(LimousineCompanyQuoteDraft draft)? onSubmit;
  final DateTime Function() clock;

  @override
  State<LimousineQuoteEditorPage> createState() =>
      _LimousineQuoteEditorPageState();
}

class _LimousineQuoteEditorPageState extends State<LimousineQuoteEditorPage> {
  final _total = TextEditingController();
  final _cancelHours = TextEditingController();
  final _cancelPenalty = TextEditingController();
  final _waitingIncluded = TextEditingController();
  final _waitingOverage = TextEditingController();
  final _noShow = TextEditingController();
  final _overtime = TextEditingController();
  final _included = TextEditingController();
  final _mobilisation = TextEditingController();
  final _obligations = TextEditingController();
  final _important = TextEditingController();
  String _vatTreatment = '';
  late DateTime _expiresDate;
  bool _submitting = false;
  LimousineQuoteDraftValidation? _validation;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    final existing = limousineDateFromQuoteExpiresAt(
      widget.record.quote?.expiresAt ?? '',
    );
    _expiresDate =
        existing ?? limousineDefaultQuoteValidUntilDate(widget.clock());
  }

  @override
  void dispose() {
    _total.dispose();
    _cancelHours.dispose();
    _cancelPenalty.dispose();
    _waitingIncluded.dispose();
    _waitingOverage.dispose();
    _noShow.dispose();
    _overtime.dispose();
    _included.dispose();
    _mobilisation.dispose();
    _obligations.dispose();
    _important.dispose();
    super.dispose();
  }

  LimousineCompanyQuoteDraft _rawDraft() {
    final services = <Map<String, dynamic>>[];
    final included = _included.text.trim();
    if (included.isNotEmpty) {
      services.add(<String, dynamic>{
        'item_id': 'included_1',
        'label': <String, String>{'nl': included, 'en': included},
      });
    }
    return LimousineCompanyQuoteDraft(
      totalInclVatCents: limousineMajorUnitsToCents(_total.text),
      currency: kLimousineDefaultQuoteCurrency,
      vatTreatment: _vatTreatment,
      expiresAt: limousineQuoteExpiresAtIsoFromDate(_expiresDate),
      cancellationDeadlineHours: int.tryParse(_cancelHours.text.trim()),
      cancellationPenaltyPercent: int.tryParse(_cancelPenalty.text.trim()),
      waitingTimeIncludedMinutes: int.tryParse(_waitingIncluded.text.trim()),
      waitingTimeOverageCentsPerMinute: limousineMajorUnitsToCents(
        _waitingOverage.text,
      ),
      noShowPenaltyPercent: int.tryParse(_noShow.text.trim()),
      overtimeCentsPerHour: limousineMajorUnitsToCents(_overtime.text),
      includedServices: services,
      mobilisationDisclosure: _mobilisation.text.trim().isEmpty
          ? const <String, String>{}
          : <String, String>{'nl': _mobilisation.text.trim()},
      customerObligations: _obligations.text.trim().isEmpty
          ? const <String, String>{}
          : <String, String>{'nl': _obligations.text.trim()},
      importantInformation: _important.text.trim().isEmpty
          ? const <String, String>{}
          : <String, String>{'nl': _important.text.trim()},
    );
  }

  LimousineCompanyQuoteDraft _completedDraft() {
    return completeLimousineCompanyQuoteDraft(
      _rawDraft(),
      existingTermsRevision: widget.record.quote?.termsRevision ?? 0,
      now: widget.clock(),
    );
  }

  LimousineQuoteDraftValidation _currentValidation() {
    return validateLimousineCompanyQuoteDraft(_completedDraft());
  }

  String? _errorFor(String key) {
    final missing = _validation?.missing ?? _currentValidation().missing;
    if (!missing.contains(key)) return null;
    return limousineQuoteFieldErrorLabel(key, _lang);
  }

  Future<void> _pickExpires() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresDate,
      firstDate: widget.clock(),
      lastDate: widget.clock().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() => _expiresDate = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final draft = _completedDraft();
    final validation = validateLimousineCompanyQuoteDraft(draft);
    setState(() => _validation = validation);
    if (!validation.ok) return;
    setState(() => _submitting = true);
    try {
      final onSubmit = widget.onSubmit;
      if (onSubmit != null) {
        await onSubmit(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(draft);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForBusinessTheme(variant);
        final missing = _validation?.missing ?? _currentValidation().missing;
        final canSubmit = !_submitting && missing.isEmpty;
        return Scaffold(
          key: kLimousineQuoteEditorPageKey,
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.textPrimary,
            title: Text(_t(kLimousineQuoteEditorTitle)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    limousineQuoteDocumentLanguageLabel(
                      widget.record.locale,
                      _lang,
                    ),
                    key: kLimousineQuoteLanguageKey,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (missing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _t(kLimousineQuoteValidationMissing),
                      style: TextStyle(color: palette.danger, height: 1.35),
                    ),
                  ),
                _moneyField(
                  palette,
                  _t(kLimousineQuoteTotal),
                  _total,
                  key: kLimousineQuoteTotalFieldKey,
                  error: _errorFor('total_incl_vat_cents'),
                ),
                _currencyRow(palette),
                _vatPicker(palette),
                _expiresField(palette),
                const SizedBox(height: 8),
                Text(
                  _t(kLimousineQuoteOptionalSection),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                _intField(
                  palette,
                  _t(kLimousineQuoteCancelDeadline),
                  _cancelHours,
                ),
                _intField(
                  palette,
                  _t(kLimousineQuoteCancelPenalty),
                  _cancelPenalty,
                ),
                _intField(
                  palette,
                  _t(kLimousineQuoteWaitingIncluded),
                  _waitingIncluded,
                ),
                _moneyField(
                  palette,
                  _t(kLimousineQuoteWaitingOverage),
                  _waitingOverage,
                ),
                _intField(palette, _t(kLimousineQuoteNoShow), _noShow),
                _moneyField(palette, _t(kLimousineQuoteOvertime), _overtime),
                _field(
                  palette,
                  _t(kLimousineQuoteIncludedServices),
                  _included,
                  maxLines: 2,
                ),
                _field(
                  palette,
                  _t(kLimousineQuoteMobilisation),
                  _mobilisation,
                  maxLines: 2,
                ),
                _field(
                  palette,
                  _t(kLimousineQuoteCustomerObligations),
                  _obligations,
                  maxLines: 2,
                ),
                _field(
                  palette,
                  _t(kLimousineQuoteImportantInfo),
                  _important,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: kLimousineQuoteSubmitKey,
                    onPressed: canSubmit ? _submit : null,
                    child: Text(
                      _submitting
                          ? _t(kLimousineQuoteSubmitting)
                          : _t(kLimousineQuoteSendQuote),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _currencyRow(BusinessThemePalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _t(kLimousineQuoteCurrency),
          labelStyle: TextStyle(color: palette.textMuted),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: palette.border),
          ),
        ),
        child: Text(
          kLimousineDefaultQuoteCurrency,
          key: kLimousineQuoteCurrencyValueKey,
          style: TextStyle(color: palette.textPrimary),
        ),
      ),
    );
  }

  Widget _vatPicker(BusinessThemePalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _t(kLimousineQuoteVatTreatment),
          labelStyle: TextStyle(color: palette.textMuted),
          errorText: _errorFor('vat_treatment'),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: palette.border),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: kLimousineQuoteVatFieldKey,
            value: _vatTreatment.isEmpty ? null : _vatTreatment,
            hint: Text(_t(kLimousineQuoteVatTreatment)),
            dropdownColor: palette.surface,
            items: [
              DropdownMenuItem(
                value: kLimousineQuoteVatIncl,
                child: Text(_t(kLimousineQuoteVatInclLabel)),
              ),
              DropdownMenuItem(
                value: kLimousineQuoteVatExcl,
                child: Text(_t(kLimousineQuoteVatExclLabel)),
              ),
              DropdownMenuItem(
                value: kLimousineQuoteVatNone,
                child: Text(_t(kLimousineQuoteVatNoneLabel)),
              ),
            ],
            onChanged: (value) => setState(() => _vatTreatment = value ?? ''),
          ),
        ),
      ),
    );
  }

  Widget _expiresField(BusinessThemePalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: kLimousineQuoteExpiresFieldKey,
        onTap: _pickExpires,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: _t(kLimousineQuoteExpires),
            labelStyle: TextStyle(color: palette.textMuted),
            errorText: _errorFor('expires_at'),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          child: Text(
            formatLimousineUserDate(
              limousineQuoteExpiresAtIsoFromDate(_expiresDate),
              _lang,
            ),
            style: TextStyle(color: palette.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _moneyField(
    BusinessThemePalette palette,
    String label,
    TextEditingController controller, {
    Key? key,
    String? error,
  }) {
    return _field(
      palette,
      label,
      controller,
      key: key,
      error: error,
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
  }

  Widget _intField(
    BusinessThemePalette palette,
    String label,
    TextEditingController controller,
  ) {
    return _field(
      palette,
      label,
      controller,
      keyboard: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }

  Widget _field(
    BusinessThemePalette palette,
    String label,
    TextEditingController controller, {
    Key? key,
    String? error,
    int maxLines = 1,
    int? max,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: controller,
        maxLines: maxLines,
        maxLength: max,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: palette.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: palette.textMuted),
          errorText: error,
          counterText: '',
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: palette.accent),
          ),
        ),
      ),
    );
  }
}

Future<LimousineDeclineDraft?> showLimousineDeclineDialog({
  required BuildContext context,
  required AppLanguage language,
}) {
  final reason = TextEditingController();
  return showDialog<LimousineDeclineDraft>(
    context: context,
    builder: (ctx) {
      final palette = paletteForBusinessTheme(businessThemeNotifier.value);
      return AlertDialog(
        key: kLimousineQuoteDeclineDialogKey,
        backgroundColor: palette.surface,
        title: Text(
          kLimousineQuoteDeclineConfirmTitle.of(language),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kLimousineQuoteDeclineConfirmBody.of(language),
              style: TextStyle(color: palette.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 600,
              maxLines: 3,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: kLimousineQuoteDeclineReasonHint.of(language),
                hintStyle: TextStyle(color: palette.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(kLimousineQuoteCancel.of(language)),
          ),
          FilledButton(
            key: kLimousineQuoteDeclineKey,
            onPressed: () {
              final text = reason.text.trim();
              Navigator.of(ctx).pop(
                LimousineDeclineDraft(
                  publicText: text.isEmpty
                      ? const <String, String>{}
                      : <String, String>{'nl': text, 'en': text},
                ),
              );
            },
            child: Text(kLimousineQuoteDeclineConfirmAction.of(language)),
          ),
        ],
      );
    },
  ).whenComplete(reason.dispose);
}

String? limousineQuoteFieldLabelOrNull(String key, AppLanguage language) {
  return kLimousineQuoteFieldLabels[key]?.of(language);
}

bool limousineQuoteDraftUsesIntegerCents(LimousineCompanyQuoteDraft draft) {
  return draft.totalInclVatCents == null ||
      draft.totalInclVatCents == draft.totalInclVatCents!.truncate();
}

String limousineQuoteIsoCurrencyOrEmpty(String raw) => limousineCurrencyOf(raw);
