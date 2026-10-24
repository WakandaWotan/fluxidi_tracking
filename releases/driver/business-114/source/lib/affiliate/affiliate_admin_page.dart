import 'dart:async';
import 'package:flutter/material.dart';
import '../app_strings.dart';
import 'affiliate_admin_models.dart';
import 'affiliate_admin_repository.dart';
import 'affiliate_form_dialog.dart';
import 'affiliate_labels.dart';
import 'affiliate_repository.dart';

enum _Section { applications, receipts, batches, registrations }

class AffiliateAdminPage extends StatefulWidget {
  const AffiliateAdminPage({super.key, required this.repository});
  final AffiliateAdminRepository repository;
  @override
  State<AffiliateAdminPage> createState() => _AffiliateAdminPageState();
}

class _AffiliateAdminPageState extends State<AffiliateAdminPage> {
  _Section _section = _Section.applications;
  List<AffiliateApplication> _applications = const [];
  List<AffiliateReceiptReview> _receipts = const [];
  List<AffiliateBatch> _batches = const [];
  List<AffiliateRegistrationReview> _registrations = const [];
  final _selection = <String>{};
  String? _cursor;
  AffiliateManifest? _manifest;
  AffiliateFailure? _failure;
  bool _loading = true, _busy = false, _denied = false;
  int _generation = 0;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    widget.repository.repository.revision.addListener(_identityChanged);
    final expires = DateTime.tryParse(
      widget.repository.overview.owner.session.expiresAt,
    );
    if (expires != null)
      _expiry = Timer(
        expires.toUtc().difference(DateTime.now().toUtc()),
        _identityChanged,
      );
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    widget.repository.repository.revision.removeListener(_identityChanged);
    _clear();
    super.dispose();
  }

  void _clear() {
    _applications = const [];
    _receipts = const [];
    _batches = const [];
    _registrations = const [];
    _manifest = null;
    _selection.clear();
    _cursor = null;
  }

  void _identityChanged() {
    if (!mounted || widget.repository.owns) return;
    _generation++;
    setState(() {
      _clear();
      _loading = _busy = false;
      _denied = true;
      _failure = AffiliateFailure.sessionChanged;
    });
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      widget.repository.owns &&
      !_denied;
  void _failed(AffiliateFailure failure) {
    _failure = failure;
    _loading = _busy = false;
    if (failure == AffiliateFailure.signInRequired ||
        failure == AffiliateFailure.sessionChanged) {
      _clear();
      _denied = true;
    }
  }

  Future<void> _load({bool more = false}) async {
    if (!widget.repository.owns || _denied) {
      _identityChanged();
      return;
    }
    final generation = ++_generation;
    final cursor = more ? _cursor : null;
    setState(() {
      _loading = true;
      _failure = null;
      if (!more) _cursor = null;
    });
    try {
      switch (_section) {
        case _Section.registrations:
          final page = await widget.repository.registrations(cursor: cursor);
          if (!_current(generation)) return;
          setState(() {
            _registrations = more
                ? [..._registrations, ...page.items]
                : page.items;
            _cursor = page.cursor;
          });
        case _Section.applications:
          final page = await widget.repository.applications(cursor: cursor);
          if (!_current(generation)) return;
          setState(() {
            _applications = more
                ? [..._applications, ...page.items]
                : page.items;
            _cursor = page.cursor;
          });
        case _Section.receipts:
          final page = await widget.repository.receipts(cursor: cursor);
          if (!_current(generation)) return;
          setState(() {
            _receipts = more ? [..._receipts, ...page.items] : page.items;
            _cursor = page.cursor;
          });
        case _Section.batches:
          final page = await widget.repository.batches(cursor: cursor);
          if (!_current(generation)) return;
          setState(() {
            _batches = more ? [..._batches, ...page.items] : page.items;
            _cursor = page.cursor;
          });
      }
      if (_current(generation)) setState(() => _loading = false);
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed(error.failure));
    }
  }

  Future<Map<String, String>?> _form(
    String title,
    List<AffiliateField> fields, {
    String? description,
  }) async {
    if (_busy || !widget.repository.owns || _denied) return null;
    final generation = _generation;
    final result = await showAffiliateForm(
      context,
      repository: widget.repository.repository,
      owner: widget.repository.overview.owner,
      title: title,
      description: description,
      fields: [
        ...fields,
        const AffiliateField('checked', 'confirmEvidence', checkbox: true),
      ],
    );
    return _current(generation) ? result : null;
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy || _loading || _denied || !widget.repository.owns) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
      if (!_current(generation)) return;
      setState(() => _busy = false);
      await _load();
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed(error.failure));
    }
  }

  Future<void> _completeRegistration(AffiliateRegistrationReview row) async {
    final form = await _form('completeRegistration', const [
      AffiliateField('reference', 'reviewReference'),
    ]);
    if (form == null) return;
    await _mutate(
      () => widget.repository.completeRegistration(row, form['reference']!),
    );
  }

  Future<void> _review(AffiliateApplication row) async {
    final form = await _form('review', [
      const AffiliateField(
        'decision',
        'decision',
        options: {
          'active': 'approve',
          'rejected': 'reject',
          'suspended': 'suspend',
        },
      ),
      const AffiliateField('reference', 'reviewReference'),
    ]);
    if (form == null) return;
    await _mutate(
      () => widget.repository.reviewApplication(
        row,
        form['decision']!,
        form['reference']!,
      ),
    );
  }

  Future<void> _verifyBank(AffiliateApplication row) async {
    final form = await _form('bankVerify', const [
      AffiliateField('reference', 'evidence'),
    ], description: 'bankInfo');
    if (form == null) return;
    await _mutate(() => widget.repository.verifyBank(row, form['reference']!));
  }

  Future<void> _basis(AffiliateReceiptReview row) async {
    final form = await _form('basis', [
      const AffiliateField('reference', 'reviewReference'),
      const AffiliateField('net', 'net', numeric: true),
      const AffiliateField('vat', 'vat', numeric: true),
      AffiliateField(
        'refundNet',
        'refundNet',
        numeric: true,
        initial: row.refunded == 0 ? '0' : '',
      ),
      AffiliateField(
        'refundVat',
        'refundVat',
        numeric: true,
        initial: row.refunded == 0 ? '0' : '',
      ),
      if (row.refunded > 0) ...const [
        AffiliateField('credit', 'credit'),
        AffiliateField('correction', 'correctionApproved', checkbox: true),
      ],
    ]);
    if (form == null) return;
    final net = affiliateCentsInput(form['net']!),
        vat = affiliateCentsInput(form['vat']!),
        refundNet = affiliateCentsInput(form['refundNet']!),
        refundVat = affiliateCentsInput(form['refundVat']!);
    if (net == null || vat == null || refundNet == null || refundVat == null) {
      setState(() => _failure = AffiliateFailure.termsChanged);
      return;
    }
    await _mutate(
      () => widget.repository.reviewBasis(
        row,
        reference: form['reference']!,
        net: net,
        vat: vat,
        refundedNet: refundNet,
        refundedVat: refundVat,
        creditReference: form['credit'] ?? '',
        correctionApproved: form['correction'] == 'true',
      ),
    );
  }

  Future<void> _recover() async {
    final form = await _form('recover', const [
      AffiliateField('payment', 'paymentId'),
      AffiliateField('tenant', 'tenant'),
      AffiliateField('company', 'company'),
    ]);
    if (form == null) return;
    await _mutate(
      () => widget.repository.recoverReceipt(
        paymentId: form['payment']!,
        tenant: form['tenant']!,
        company: form['company']!,
      ),
    );
  }

  Future<void> _ownerReview() async {
    final form = await _form('ownerReview', const [
      AffiliateField('tenant', 'tenant'),
      AffiliateField('company', 'company'),
      AffiliateField('person', 'personReference'),
      AffiliateField('reference', 'evidence'),
    ]);
    if (form == null) return;
    await _mutate(
      () => widget.repository.reviewOwner(
        tenant: form['tenant']!,
        company: form['company']!,
        personId: form['person']!,
        reference: form['reference']!,
      ),
    );
  }

  Future<void> _createBatch() async {
    final selected = _applications
        .where((row) => _selection.contains(row.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final form = await _form('createBatch', const [
      AffiliateField('id', 'batchId'),
      AffiliateField('period', 'period', maxLength: 7),
      AffiliateField('currency', 'currency', maxLength: 3),
    ]);
    if (form == null) return;
    await _mutate(() async {
      final result = await widget.repository.createBatch(
        id: form['id']!,
        period: form['period']!,
        currency: form['currency']!.toUpperCase(),
        affiliates: selected,
      );
      if (!mounted || !widget.repository.owns) return;
      _manifest = result;
    });
  }

  Future<void> _export(AffiliateBatch batch) async {
    final form = await _form('export', const [], description: 'manifestInfo');
    if (form == null) return;
    await _mutate(() async {
      final result = await widget.repository.exportBatch(batch);
      if (!mounted || !widget.repository.owns) return;
      _manifest = result;
    });
  }

  Future<void> _cancelBatch(AffiliateBatch batch) async {
    final form = await _form('cancelBatch', const [
      AffiliateField('reference', 'reviewReference'),
    ], description: 'cancelBatchInfo');
    if (form == null) return;
    await _mutate(() async {
      await widget.repository.cancelBatch(batch, form['reference']!);
      if (mounted && widget.repository.owns && _manifest?.batchId == batch.id)
        _manifest = null;
    });
  }

  Future<void> _reconcile(
    AffiliateManifest manifest,
    AffiliateManifestItem item,
  ) async {
    final form = await _form('reconcile', const [
      AffiliateField(
        'status',
        'decision',
        options: {'paid': 'paid', 'failed': 'failed'},
      ),
      AffiliateField('reference', 'executionReference'),
      AffiliateField('evidence', 'evidence'),
      AffiliateField('executedAt', 'executedAt', dateTime: true, maxLength: 40),
    ], description: 'reconcileInfo');
    if (form == null) return;
    await _mutate(() async {
      await widget.repository.reconcile(
        manifest,
        item,
        reference: form['reference']!,
        evidence: form['evidence']!,
        executedAt: form['executedAt']!,
        status: form['status']!,
      );
      if (mounted && widget.repository.owns) _manifest = null;
    });
  }

  String _money(int value, String currency, AppLanguage language) {
    final text = (value / 100).toStringAsFixed(2);
    return '$currency ${language == AppLanguage.en ? text : text.replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: appLanguageNotifier,
    builder: (context, language, _) {
      String t(String key) => affiliateLabel(key, language);
      final locked = _loading || _busy || _denied;
      final manifest = _manifest;
      final rowsEmpty = switch (_section) {
        _Section.registrations => _registrations.isEmpty,
        _Section.applications => _applications.isEmpty,
        _Section.receipts => _receipts.isEmpty,
        _Section.batches => _batches.isEmpty,
      };
      return Scaffold(
        appBar: AppBar(
          title: Text(t('admin')),
          actions: [
            IconButton(
              key: const Key('affiliate_admin_refresh'),
              onPressed: locked ? null : _load,
              tooltip: t('refresh'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final section in _Section.values)
                      ChoiceChip(
                        key: Key('affiliate_admin_${section.name}'),
                        label: Text(t(section.name)),
                        selected: _section == section,
                        onSelected: locked
                            ? null
                            : (_) {
                                _section = section;
                                _cursor = null;
                                _manifest = null;
                                unawaited(_load());
                              },
                      ),
                  ],
                ),
                if (_loading || _busy)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_failure != null)
                  Text(
                    t(
                      _denied
                          ? 'noAccess'
                          : _failure == AffiliateFailure.unavailable
                          ? 'unavailable'
                          : 'reviewError',
                    ),
                    key: const Key('affiliate_admin_error'),
                  ),
                if (!_denied) ...[
                  if (_section == _Section.registrations)
                    for (final row in _registrations)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${t('company')}: ${row.company}'),
                              Text('${t('personReference')}: ${row.personId}'),
                              OutlinedButton(
                                onPressed: locked
                                    ? null
                                    : () => _completeRegistration(row),
                                child: Text(t('completeRegistration')),
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (!_loading && _failure == null && rowsEmpty)
                    Text(t('empty')),
                  if (_section == _Section.applications) ...[
                    Text(t('selectAffiliates')),
                    for (final row in _applications)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(t(row.status)),
                              Text('${t('personReference')}: ${row.id}'),
                              Text(
                                t(
                                  row.applicantType == 'business'
                                      ? 'business'
                                      : 'person',
                                ),
                              ),
                              if (row.legalName.isNotEmpty) Text(row.legalName),
                              if (row.address.isNotEmpty) Text(row.address),
                              if (row.country.isNotEmpty) Text(row.country),
                              if (row.applicantType == 'business') ...[
                                Text(
                                  '${t('companyRegistrationNumber')}: ${row.companyRegistrationNumber.isEmpty ? t('identifierUnknown') : row.companyRegistrationNumber}',
                                ),
                                Text(
                                  '${t('vatNumber')}: ${row.vatNumber.isEmpty ? t('identifierUnknown') : row.vatNumber}',
                                ),
                              ],
                              Text(
                                t(
                                  row.bankVerified
                                      ? 'bankVerified'
                                      : 'bankPending',
                                ),
                              ),
                              if (row.status == 'active' && row.bankVerified)
                                CheckboxListTile(
                                  key: Key('affiliate_select_${row.id}'),
                                  title: Text(t('createBatch')),
                                  value: _selection.contains(row.id),
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: locked
                                      ? null
                                      : (value) => setState(() {
                                          if (value == true)
                                            _selection.add(row.id);
                                          else
                                            _selection.remove(row.id);
                                        }),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    key: Key('affiliate_review_${row.id}'),
                                    onPressed: locked
                                        ? null
                                        : () => _review(row),
                                    child: Text(t('review')),
                                  ),
                                  if (row.bankRevision > 0 && !row.bankVerified)
                                    OutlinedButton(
                                      key: Key(
                                        'affiliate_bank_verify_${row.id}',
                                      ),
                                      onPressed: locked
                                          ? null
                                          : () => _verifyBank(row),
                                      child: Text(t('bankVerify')),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_selection.isNotEmpty)
                      FilledButton(
                        key: const Key('affiliate_create_batch'),
                        onPressed: locked ? null : _createBatch,
                        child: Text(t('createBatch')),
                      ),
                  ],
                  if (_section == _Section.receipts) ...[
                    OutlinedButton(
                      onPressed: locked ? null : _ownerReview,
                      child: Text(t('ownerReview')),
                    ),
                    OutlinedButton(
                      onPressed: locked ? null : _recover,
                      child: Text(t('recover')),
                    ),
                    for (final row in _receipts)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.paymentId),
                              Text(
                                '${t('gross')}: ${_money(row.gross, row.currency, language)}',
                              ),
                              Text(
                                '${t('refund')}: ${_money(row.refunded, row.currency, language)}',
                              ),
                              Text(t(affiliateReceiptReasonKey(row.reason))),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (row.mayReviewBasis)
                                    OutlinedButton(
                                      key: Key(
                                        'affiliate_basis_${row.paymentId}',
                                      ),
                                      onPressed: locked
                                          ? null
                                          : () => _basis(row),
                                      child: Text(t('basis')),
                                    ),
                                  TextButton(
                                    onPressed: locked
                                        ? null
                                        : () => _mutate(
                                            () => widget.repository
                                                .retryReceipt(row),
                                          ),
                                    child: Text(t('retry')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (_section == _Section.batches)
                    for (final batch in _batches)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${batch.period} · ${batch.currency}'),
                              Text(batch.id),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    key: Key('affiliate_export_${batch.id}'),
                                    onPressed: locked
                                        ? null
                                        : () => _export(batch),
                                    child: Text(t('export')),
                                  ),
                                  TextButton(
                                    onPressed: locked
                                        ? null
                                        : () => _cancelBatch(batch),
                                    child: Text(t('cancelBatch')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (_cursor != null && !locked)
                    TextButton(
                      onPressed: () => _load(more: true),
                      child: Text(t('more')),
                    ),
                  if (manifest != null) ...[
                    const Divider(),
                    Text(t('manifestInfo')),
                    Text(manifest.batchId),
                    for (final item in manifest.items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_money(item.cents, item.currency, language)),
                              if (item.accountHolder != null)
                                Text(item.accountHolder!),
                              if (item.iban != null) SelectableText(item.iban!),
                              if (manifest.exported)
                                OutlinedButton(
                                  key: Key(
                                    'affiliate_reconcile_${item.payoutId}',
                                  ),
                                  onPressed: locked
                                      ? null
                                      : () => _reconcile(manifest, item),
                                  child: Text(t('reconcile')),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
