// COMPANY-CUSTOMER-OPS-P0B

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_import_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customer_import_parse.dart';
import 'package:fluxidi_tracking/company/company_customer_import_session.dart';
import 'package:fluxidi_tracking/company/company_customer_import_xlsx.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

const Key kCompanyCustomerImportPageKey = Key('company_customer_import_page');
const Key kCompanyCustomerImportChooseFileKey = Key(
  'company_customer_import_choose_file',
);
const Key kCompanyCustomerImportNextKey = Key('company_customer_import_next');
const Key kCompanyCustomerImportBackKey = Key('company_customer_import_back');
const Key kCompanyCustomerImportConfirmPartialKey = Key(
  'company_customer_import_confirm_partial',
);
const Key kCompanyCustomerImportStartKey = Key('company_customer_import_start');
const Key kCompanyCustomerImportStopKey = Key('company_customer_import_stop');
const Key kCompanyCustomerImportResultKey = Key(
  'company_customer_import_result',
);
const Key kCompanyCustomerImportResumeKey = Key(
  'company_customer_import_resume',
);
const Key kCompanyCustomerImportCountryKey = Key(
  'company_customer_import_country',
);
const Key kCompanyCustomerImportRepickKey = Key(
  'company_customer_import_repick',
);

typedef CompanyCustomerImportPicker =
    Future<CompanyCustomerImportPickedFile?> Function();

enum CompanyCustomerImportStep { pick, sheet, map, review, progress, result }

class CompanyCustomerImportPage extends StatefulWidget {
  const CompanyCustomerImportPage({
    super.key,
    required this.repository,
    this.language,
    this.initialFile,
    this.picker,
    this.sessionStore,
    this.importIdFactory,
  });

  final CompanyCustomersRepository repository;
  final AppLanguage? language;
  final CompanyCustomerImportPickedFile? initialFile;
  final CompanyCustomerImportPicker? picker;
  final CompanyCustomerImportSessionStore? sessionStore;
  final String Function()? importIdFactory;

  @override
  State<CompanyCustomerImportPage> createState() =>
      CompanyCustomerImportPageState();
}

class CompanyCustomerImportPageState extends State<CompanyCustomerImportPage> {
  late final CompanyCustomerImportSessionStore _store;
  CompanyCustomerImportStep _step = CompanyCustomerImportStep.pick;
  CompanyCustomerImportPickedFile? _picked;
  CompanyCustomerImportTable? _table;
  List<String> _mappings = const <String>[];
  List<CompanyCustomerImportPreparedRow> _rows =
      <CompanyCustomerImportPreparedRow>[];
  CompanyCustomerImportSession? _session;
  String _defaultCallingCode = '';
  String? _error;
  bool _busy = false;
  bool _stop = false;
  bool _confirmPartial = false;
  String _sheetName = '';
  int _headerRowIndex = 0;
  int _added = 0;
  int _skipped = 0;
  int _failed = 0;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    _store = widget.sessionStore ?? MemoryCompanyCustomerImportSessionStore();
    final file = widget.initialFile;
    if (file != null) {
      try {
        _applyTable(
          parseCompanyCustomerImportBytes(
            bytes: file.bytes,
            fileName: file.name,
            sheetName: _sheetName,
            headerRowIndex: _headerRowIndex,
            xlsxParser: parseCompanyCustomerXlsx,
          ),
          file,
        );
      } catch (error) {
        _error = _errorText(error);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSession();
    });
  }

  void _applyTable(
    CompanyCustomerImportTable table,
    CompanyCustomerImportPickedFile file, {
    bool preferMap = false,
  }) {
    _picked = file;
    _table = table;
    _sheetName = table.selectedSheet;
    _headerRowIndex = table.headerRowIndex;
    _mappings = suggestCompanyCustomerImportMappings(table.headers);
    _step = preferMap
        ? CompanyCustomerImportStep.map
        : table.kind == CompanyCustomerImportKind.xlsx &&
                table.sheetNames.length > 1
            ? CompanyCustomerImportStep.sheet
            : CompanyCustomerImportStep.map;
  }

  Future<void> _restoreSession() async {
    try {
      final companyId = widget.repository.companyScopeId();
      _session = await _store.load(companyId);
    } catch (_) {
      _session = null;
    }
    if (mounted) setState(() {});
  }

  Future<CompanyCustomerImportPickedFile?> _pick() async {
    if (widget.picker != null) return widget.picker!();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['csv', 'xlsx', 'vcf', 'vcard', 'txt'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const CompanyCustomerImportException('unreadable');
    }
    return CompanyCustomerImportPickedFile(name: file.name, bytes: bytes);
  }

  String _errorText(Object error) {
    if (error is CompanyCustomerImportException) {
      switch (error.code) {
        case 'limit_file':
          return kCompanyCustomerImportLimitFile.of(_lang);
        case 'limit_rows':
          return kCompanyCustomerImportLimitRows.of(_lang);
        case 'limit_xlsx':
          return kCompanyCustomerImportLimitXlsx.of(_lang);
        case 'formula':
          return kCompanyCustomerImportFormula.of(_lang);
        case 'unsupported':
          return kCompanyCustomerImportUnsupported.of(_lang);
        case 'file_mismatch':
          return kCompanyCustomerImportFileMismatch.of(_lang);
        case 'mapping_mismatch':
          return kCompanyCustomerImportMappingMismatch.of(_lang);
        default:
          return kCompanyCustomerImportFileUnreadable.of(_lang);
      }
    }
    if (error is CompanyCustomerException) {
      if (error.offline) return kCompanyCustomersOffline.of(_lang);
      if (error.code == 'import_expired') {
        return kCompanyCustomerImportExpired.of(_lang);
      }
      if (error.code == 'import_not_found') {
        return kCompanyCustomerImportUnknown.of(_lang);
      }
    }
    return kCompanyCustomerImportFileUnreadable.of(_lang);
  }

  Future<void> _openFile(
    CompanyCustomerImportPickedFile file, {
    bool preferMap = false,
  }) async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final table = parseCompanyCustomerImportBytes(
        bytes: file.bytes,
        fileName: file.name,
        sheetName: _sheetName,
        headerRowIndex: _headerRowIndex,
        xlsxParser: parseCompanyCustomerXlsx,
      );
      _applyTable(table, file, preferMap: preferMap);
      final session = _session;
      if (session != null && session.needsFileRepick && session.fingerprint != null) {
        if (session.mappings.isNotEmpty) {
          _mappings = List<String>.from(session.mappings);
        }
        final match = matchCompanyCustomerImportFile(
          fingerprint: session.fingerprint!,
          file: file,
          table: table,
          mappings: _mappings,
        );
        if (match == CompanyCustomerImportFileMatch.fileMismatch) {
          throw const CompanyCustomerImportException('file_mismatch');
        }
        if (match == CompanyCustomerImportFileMatch.mappingMismatch) {
          setState(() {
            _busy = false;
            _step = CompanyCustomerImportStep.map;
            _error = kCompanyCustomerImportMappingMismatch.of(_lang);
          });
          return;
        }
        _prepareRows();
        _session = session.copyWith(rows: _rows);
        await _store.save(_session!);
        setState(() {
          _busy = false;
          _step = CompanyCustomerImportStep.pick;
        });
        return;
      }
      setState(() {
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _chooseFile() async {
    try {
      final picked = await _pick();
      if (picked == null) return;
      await _openFile(picked);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    }
  }

  void _prepareRows() {
    final table = _table;
    if (table == null) return;
    _rows = prepareCompanyCustomerImportRows(
      table: table,
      mappings: _mappings,
      defaultCallingCode: _defaultCallingCode,
    );
  }

  Future<void> _loadCompanyMatches() async {
    final importId = widget.importIdFactory?.call() ?? newCompanyCustomerImportId();
    final contacts = <Map<String, String>>[
      for (final row in _rows.where((item) => item.isValid))
        <String, String>{
          'row_key': row.rowKey,
          'email': row.write.email,
          'phone': row.write.phone,
          'country_calling_code': row.write.countryCallingCode,
        },
    ];
    final matches = <CompanyCustomerImportCompanyMatch>[];
    for (var i = 0; i < contacts.length; i += 15) {
      final end = i + 15 > contacts.length ? contacts.length : i + 15;
      matches.addAll(
        await widget.repository.lookupImportContacts(
          importId: importId,
          contacts: contacts.sublist(i, end),
        ),
      );
    }
    final byRow = <String, List<CompanyCustomerImportCompanyMatch>>{};
    for (final match in matches) {
      byRow.putIfAbsent(match.rowKey, () => <CompanyCustomerImportCompanyMatch>[]);
      byRow[match.rowKey]!.add(match);
    }
    for (final row in _rows) {
      row.companyMatches
        ..clear()
        ..addAll(byRow[row.rowKey] ?? const <CompanyCustomerImportCompanyMatch>[]);
    }
    final companyId = widget.repository.companyScopeId();
    final picked = _picked;
    final table = _table;
    _session = CompanyCustomerImportSession(
      importId: importId,
      companyId: companyId,
      expiresAt: DateTime.now().add(kCompanyCustomerImportSessionTtl),
      rows: _rows,
      outcomes: <String, CompanyCustomerImportRowOutcome>{},
      defaultCallingCode: _defaultCallingCode,
      mappings: List<String>.from(_mappings),
      fingerprint: picked != null && table != null
          ? buildCompanyCustomerImportFingerprint(
              file: picked,
              table: table,
              mappings: _mappings,
            )
          : null,
    );
    await _store.save(_session!);
  }

  Future<void> _goNext() async {
    setState(() => _error = null);
    if (_step == CompanyCustomerImportStep.pick) {
      if (_table == null) return;
      setState(() => _step = CompanyCustomerImportStep.map);
      return;
    }
    if (_step == CompanyCustomerImportStep.sheet) {
      final picked = _picked;
      if (picked != null) {
        await _openFile(
          CompanyCustomerImportPickedFile(
            name: picked.name,
            bytes: picked.bytes,
          ),
          preferMap: true,
        );
      }
      if (_error != null) return;
      setState(() => _step = CompanyCustomerImportStep.map);
      return;
    }
    if (_step == CompanyCustomerImportStep.map) {
      _prepareRows();
      setState(() {
        _busy = true;
        _step = CompanyCustomerImportStep.review;
      });
      try {
        await _loadCompanyMatches();
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = _errorText(error));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
  }

  bool get _needsPartialConfirm {
    final validSelected = _rows.where((row) => row.selected && row.isValid).length;
    return validSelected != _rows.length;
  }

  Future<void> _startImport({required bool resume}) async {
    var session = _session;
    if (!resume) {
      if (_needsPartialConfirm && !_confirmPartial) {
        setState(
          () => _error = kCompanyCustomerImportPartialConfirm.of(_lang),
        );
        return;
      }
      if (session == null) {
        _prepareRows();
        await _loadCompanyMatches();
        session = _session;
      }
      session?.confirmedPartial = _confirmPartial;
    }
    if (session == null) return;
    final active = session;
    if (active.needsFileRepick) {
      setState(() => _error = kCompanyCustomerImportRepick.of(_lang));
      return;
    }
    setState(() {
      _step = CompanyCustomerImportStep.progress;
      _stop = false;
      _busy = true;
      _error = null;
      _added = active.outcomes.values.where((row) => row.outcome == 'created').length;
      _skipped = active.outcomes.values.where((row) => row.outcome == 'skipped').length;
      _failed = active.outcomes.values.where((row) => row.outcome == 'failed').length;
    });
    try {
      try {
        if (resume || active.outcomes.isNotEmpty) {
          final status = await widget.repository.getImport(active.importId);
          _mergeStatus(active, status);
        }
      } on CompanyCustomerException catch (error) {
        if (error.code == 'import_expired' ||
            (error.code == 'import_not_found' && active.outcomes.isNotEmpty)) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _step = CompanyCustomerImportStep.result;
            _error = _errorText(error);
          });
          await _store.clear(active.companyId);
          return;
        }
        if (!error.offline) rethrow;
      }
      await _runBatches(active);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = CompanyCustomerImportStep.result;
        });
      }
    }
  }

  Future<void> _runBatches(CompanyCustomerImportSession session) async {
    while (!_stop) {
      final pending = session.pending;
      if (pending.isEmpty) break;
      final batch = pending.take(kCompanyCustomerImportBatchSize).toList();
      final payload = <Map<String, dynamic>>[
        for (final row in batch)
          <String, dynamic>{
            'row_key': row.rowKey,
            'decision': row.decision == CompanyCustomerImportDecision.skip
                ? 'skip'
                : 'create',
            'customer': row.write.toJson(),
          },
      ];
      late final CompanyCustomerImportBatchResult result;
      try {
        result = await widget.repository.importBatch(
          importId: session.importId,
          rows: payload,
        );
      } on CompanyCustomerException catch (error) {
        if (error.offline) {
          try {
            final status = await widget.repository.getImport(session.importId);
            _mergeStatus(session, status);
            result = await widget.repository.importBatch(
              importId: session.importId,
              rows: payload,
            );
          } on CompanyCustomerException catch (retryError) {
            if (!mounted) return;
            setState(() => _error = _errorText(retryError));
            break;
          }
        } else {
          if (!mounted) return;
          setState(() => _error = _errorText(error));
          break;
        }
      }
      for (final row in result.rows) {
        session.outcomes[row.rowKey] = row;
      }
      _added = result.added;
      _skipped = result.skipped;
      _failed = result.failed;
      await _store.save(session);
      if (mounted) setState(() {});
    }
    if (session.pending.isEmpty) {
      await _store.clear(session.companyId);
    }
  }

  void _mergeStatus(
    CompanyCustomerImportSession session,
    CompanyCustomerImportStatus status,
  ) {
    session.outcomes.addAll(status.rows);
    _added = status.added;
    _skipped = status.skipped;
    _failed = status.failed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: kCompanyCustomerImportPageKey,
      appBar: AppBar(
        title: Text(kCompanyCustomerImportTitle.of(_lang)),
        actions: [
          if (_step == CompanyCustomerImportStep.map ||
              _step == CompanyCustomerImportStep.sheet ||
              (_step == CompanyCustomerImportStep.pick && _table != null))
            TextButton(
              key: kCompanyCustomerImportNextKey,
              onPressed: _busy || _table == null ? null : _goNext,
              child: Text(kCompanyCustomerImportNext.of(_lang)),
            ),
          if (_step == CompanyCustomerImportStep.review)
            TextButton(
              key: kCompanyCustomerImportStartKey,
              onPressed: _busy ? null : () => _startImport(resume: false),
              child: Text(kCompanyCustomerImportStart.of(_lang)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, maxLines: 4, overflow: TextOverflow.ellipsis),
                ),
              Expanded(child: _body()),
              _buttons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case CompanyCustomerImportStep.pick:
        return _pickBody();
      case CompanyCustomerImportStep.sheet:
        return _sheetBody();
      case CompanyCustomerImportStep.map:
        return _mapBody();
      case CompanyCustomerImportStep.review:
        return _reviewBody();
      case CompanyCustomerImportStep.progress:
        return _progressBody();
      case CompanyCustomerImportStep.result:
        return _resultBody();
    }
  }

  Widget _pickBody() {
    return ListView(
      children: [
        Text(kCompanyCustomerImportPick.of(_lang)),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: kCompanyCustomerImportChooseFileKey,
          onPressed: _busy ? null : _chooseFile,
          icon: const Icon(Icons.upload_file),
          label: Text(kCompanyCustomerImportChooseFile.of(_lang)),
        ),
        if (_table != null) ...[
          const SizedBox(height: 12),
          Text(_table!.fileName, overflow: TextOverflow.ellipsis),
          Text('${_table!.rows.length}'),
        ],
        if (_session != null &&
            (_session!.pending.isNotEmpty || _session!.needsFileRepick)) ...[
          const SizedBox(height: 24),
          Text(
            _session!.needsFileRepick
                ? kCompanyCustomerImportRepick.of(_lang)
                : kCompanyCustomerImportResumeHint.of(_lang),
          ),
          const SizedBox(height: 8),
          if (_session!.needsFileRepick)
            OutlinedButton(
              key: kCompanyCustomerImportRepickKey,
              onPressed: _busy ? null : _chooseFile,
              child: Text(kCompanyCustomerImportChooseFile.of(_lang)),
            )
          else
            OutlinedButton(
              key: kCompanyCustomerImportResumeKey,
              onPressed: () => _startImport(resume: true),
              child: Text(kCompanyCustomerImportResume.of(_lang)),
            ),
        ],
      ],
    );
  }

  Widget _sheetBody() {
    final table = _table;
    if (table == null) return const SizedBox.shrink();
    return ListView(
      children: [
        Text(kCompanyCustomerImportSheet.of(_lang)),
        DropdownButton<String>(
          value: _sheetName.isEmpty ? table.selectedSheet : _sheetName,
          items: [
            for (final name in table.sheetNames)
              DropdownMenuItem<String>(value: name, child: Text(name)),
          ],
          onChanged: (value) => setState(() => _sheetName = value ?? ''),
        ),
        Text(kCompanyCustomerImportHeaderRow.of(_lang)),
        TextFormField(
          initialValue: '${_headerRowIndex + 1}',
          keyboardType: TextInputType.number,
          onChanged: (value) {
            final parsed = int.tryParse(value.trim());
            if (parsed != null && parsed > 0) {
              _headerRowIndex = parsed - 1;
            }
          },
        ),
      ],
    );
  }

  Widget _mapBody() {
    final table = _table;
    if (table == null) return const SizedBox.shrink();
    return ListView(
      children: [
        Text(kCompanyCustomerImportMap.of(_lang)),
        const SizedBox(height: 12),
        Text(kCompanyCustomerImportDefaultCountry.of(_lang)),
        DropdownButtonFormField<String>(
          key: kCompanyCustomerImportCountryKey,
          isExpanded: true,
          value: _defaultCallingCode,
          items: const [
            DropdownMenuItem<String>(
              value: '',
              child: Text('—'),
            ),
            DropdownMenuItem<String>(value: '31', child: Text('+31')),
            DropdownMenuItem<String>(value: '32', child: Text('+32')),
            DropdownMenuItem<String>(value: '33', child: Text('+33')),
            DropdownMenuItem<String>(value: '34', child: Text('+34')),
            DropdownMenuItem<String>(value: '44', child: Text('+44')),
            DropdownMenuItem<String>(value: '49', child: Text('+49')),
          ],
          onChanged: (value) => setState(() => _defaultCallingCode = value ?? ''),
        ),
        Text(kCompanyCustomerImportNoDefaultCountry.of(_lang)),
        const SizedBox(height: 12),
        for (var i = 0; i < table.headers.length; i += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(table.headers[i], overflow: TextOverflow.ellipsis),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: i < _mappings.length ? _mappings[i] : 'skip',
                  items: [
                    for (final field in kCompanyCustomerImportTargetFields)
                      DropdownMenuItem<String>(
                        value: field,
                        child: Text(
                          field == 'skip'
                              ? kCompanyCustomerImportSkipColumn.of(_lang)
                              : field,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      final next = [..._mappings];
                      if (i >= next.length) return;
                      next[i] = value ?? 'skip';
                      _mappings = next;
                    });
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _reviewBody() {
    final found = _rows.length;
    final valid = _rows.where((row) => row.isValid).length;
    final invalid = found - valid;
    final selected = _rows.where((row) => row.selected && row.isValid).length;
    final missing = _rows.where((row) => row.fieldErrors.containsKey('contact') || row.fieldErrors.containsKey('display_name')).length;
    final inFile = _rows.where((row) => row.inFileDupSources.isNotEmpty).length;
    final company = _rows.where((row) => row.companyMatches.isNotEmpty).length;
    return ListView(
      children: [
        Text(kCompanyCustomerImportReview.of(_lang)),
        Text('$found / $valid / $invalid / $missing / $inFile / $company / $selected'),
        Text(kCompanyCustomerImportDupHint.of(_lang)),
        if (_needsPartialConfirm)
          CheckboxListTile(
            key: kCompanyCustomerImportConfirmPartialKey,
            value: _confirmPartial,
            onChanged: (value) => setState(() => _confirmPartial = value ?? false),
            title: Text(kCompanyCustomerImportPartialConfirm.of(_lang)),
          ),
        for (final row in _rows)
          Card(
            key: Key('company_customer_import_row_${row.rowKey}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.sourceIndex}  ${row.write.displayName.isEmpty ? row.write.firstName : row.write.displayName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (row.write.email.isNotEmpty) Text(row.write.email, overflow: TextOverflow.ellipsis),
                  if (row.write.phone.isNotEmpty) Text(row.write.phone, overflow: TextOverflow.ellipsis),
                  if (row.fieldErrors.isNotEmpty)
                    Text(row.fieldErrors.values.join(', ')),
                  if (row.inFileDupSources.isNotEmpty)
                    Text(row.inFileDupSources.join(', ')),
                  for (final match in row.companyMatches)
                    Text(
                      '${match.displayName} ${match.emailMasked} ${match.phoneMasked}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (row.inFileDupSources.isNotEmpty || row.companyMatches.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => setState(() {
                            row.decision = CompanyCustomerImportDecision.skip;
                            row.selected = false;
                          }),
                          child: Text(kCompanyCustomerImportSkipDup.of(_lang)),
                        ),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            row.decision = CompanyCustomerImportDecision.create;
                            row.selected = row.isValid;
                          }),
                          child: Text(kCompanyCustomerImportKeepSeparate.of(_lang)),
                        ),
                      ],
                    ),
                  CheckboxListTile(
                    value: row.selected && row.isValid,
                    onChanged: row.isValid
                        ? (value) => setState(() => row.selected = value ?? false)
                        : null,
                    title: Text('${row.sourceIndex}'),
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _progressBody() {
    return ListView(
      children: [
        Text('$_added / $_skipped / $_failed'),
        Text(kCompanyCustomerImportStopHint.of(_lang)),
      ],
    );
  }

  Widget _resultBody() {
    return ListView(
      key: kCompanyCustomerImportResultKey,
      children: [
        Text('$_added / $_skipped / $_failed'),
        for (final row in (_session?.outcomes.values ?? const <CompanyCustomerImportRowOutcome>[]))
          if (row.outcome == 'failed' || row.outcome == 'conflict')
            Text('${row.rowKey} ${row.error}'),
      ],
    );
  }

  Widget _buttons() {
    if (_step == CompanyCustomerImportStep.progress) {
      return OutlinedButton(
        key: kCompanyCustomerImportStopKey,
        onPressed: () => setState(() => _stop = true),
        child: Text(kCompanyCustomerImportStop.of(_lang)),
      );
    }
    if (_step == CompanyCustomerImportStep.result) {
      return FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(kCompanyCustomerImportNext.of(_lang)),
      );
    }
    if (_step == CompanyCustomerImportStep.review) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: kCompanyCustomerImportBackKey,
              onPressed: () => setState(() => _step = CompanyCustomerImportStep.map),
              child: Text(kCompanyCustomerImportBack.of(_lang)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _startImport(resume: false),
              child: Text(kCompanyCustomerImportStart.of(_lang)),
            ),
          ),
        ],
      );
    }
    if (_step == CompanyCustomerImportStep.pick) {
      if (_table == null) return const SizedBox.shrink();
      return FilledButton(
        onPressed: _busy ? null : _goNext,
        child: Text(kCompanyCustomerImportNext.of(_lang)),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: kCompanyCustomerImportBackKey,
            onPressed: () => setState(() => _step = CompanyCustomerImportStep.pick),
            child: Text(kCompanyCustomerImportBack.of(_lang)),
          ),
        ),
        const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _busy || _table == null ? null : _goNext,
              child: Text(kCompanyCustomerImportNext.of(_lang)),
            ),
          ),
      ],
    );
  }
}
