import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_strings.dart';
import 'affiliate_labels.dart';
import 'affiliate_models.dart';
import 'affiliate_repository.dart';
import 'affiliate_form_dialog.dart';
import 'affiliate_admin_repository.dart';
import 'affiliate_admin_page.dart';

class AffiliatePage extends StatefulWidget {
  const AffiliatePage({
    super.key,
    required this.repository,
    this.onSignIn,
    this.disposeRepository = false,
  });
  final AffiliateRepository repository;
  final Future<void> Function(BuildContext)? onSignIn;
  final bool disposeRepository;
  @override
  State<AffiliatePage> createState() => _AffiliatePageState();
}

class _AffiliatePageState extends State<AffiliatePage> {
  final _name = TextEditingController();
  final _legalName = TextEditingController(),
      _address = TextEditingController(),
      _country = TextEditingController();
  final _registrationNumber = TextEditingController(),
      _vatNumber = TextEditingController();
  String _applicantType = 'person';
  List<AffiliateReferral> _referrals = const [];
  String? _referralsCursor;
  bool _referralsLoaded = false,
      _referralsLoading = false,
      _referralsFailed = false;
  OwnedAffiliateOverview? _overview;
  List<AffiliatePayout> _payouts = const [];
  List<AffiliateEntry> _entries = const [];
  String? _entriesCursor;
  bool _entriesLoading = false, _entriesFailed = false, _entriesLoaded = false;
  String? _cursor;
  AffiliateFailure? _failure;
  bool _loading = true, _applying = false, _accepted = false;
  bool _historyLoading = false, _historyFailed = false, _historyLoaded = false;
  int _generation = 0;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    widget.repository.revision.addListener(_identityChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    widget.repository.revision.removeListener(_identityChanged);
    _name.dispose();
    _legalName.dispose();
    _address.dispose();
    _country.dispose();
    _registrationNumber.dispose();
    _vatNumber.dispose();
    if (widget.disposeRepository) widget.repository.dispose();
    super.dispose();
  }

  void _evict() {
    _expiry?.cancel();
    _overview = null;
    _payouts = const [];
    _entries = const [];
    _entriesCursor = null;
    _entriesLoading = _entriesFailed = _entriesLoaded = false;
    _cursor = null;
    _historyLoaded = _historyLoading = _historyFailed = false;
    _applying = _accepted = false;
    _name.clear();
    _legalName.clear();
    _address.clear();
    _country.clear();
    _registrationNumber.clear();
    _vatNumber.clear();
    _applicantType = 'person';
    _referrals = const [];
    _referralsCursor = null;
    _referralsLoaded = _referralsLoading = _referralsFailed = false;
  }

  void _identityChanged() {
    // A first disk load can publish the initial identity. The repository still
    // verifies that request's owner. An existing private view is evicted now.
    if (!mounted || _overview == null) return;
    _generation++;
    setState(() {
      _evict();
      _loading = false;
      _failure = AffiliateFailure.sessionChanged;
    });
  }

  bool _current(int generation, AffiliateOwner owner) =>
      mounted && generation == _generation && widget.repository.owns(owner);

  void _show(OwnedAffiliateOverview value) {
    _overview = value;
    _failure = null;
    _expiry?.cancel();
    final expiry = DateTime.parse(value.owner.session.expiresAt).toUtc();
    _expiry = Timer(expiry.difference(DateTime.now().toUtc()), () {
      if (!mounted || _overview?.owner != value.owner) return;
      _generation++;
      setState(() {
        _evict();
        _loading = false;
        _failure = AffiliateFailure.signInRequired;
      });
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _evict();
      _loading = true;
      _failure = null;
    });
    try {
      final value = await widget.repository.loadOverview();
      if (!_current(generation, value.owner)) return;
      setState(() {
        _show(value);
        _loading = false;
      });
      if (value.data.status != 'not_enrolled') {
        unawaited(_history());
        unawaited(_balanceHistory());
      }
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failure = error.failure;
      });
    }
  }

  Future<void> _apply() async {
    final overview = _overview;
    if (overview == null ||
        _applying ||
        !_accepted ||
        _name.text.trim().isEmpty ||
        !widget.repository.owns(overview.owner))
      return;
    final generation = _generation;
    setState(() {
      _applying = true;
      _failure = null;
    });
    try {
      final value = await widget.repository.apply(
        overview,
        displayName: _name.text,
        accepted: _accepted,
        applicantType: _applicantType,
        legalName: _legalName.text,
        address: _address.text,
        country: _country.text,
        companyRegistrationNumber: _applicantType == 'business'
            ? _registrationNumber.text
            : '',
        vatNumber: _applicantType == 'business' ? _vatNumber.text : '',
      );
      if (!_current(generation, value.owner)) return;
      setState(() {
        _show(value);
        _applying = false;
        _accepted = false;
        _name.clear();
      });
      unawaited(_history());
      unawaited(_balanceHistory());
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _applying = false;
        _failure = error.failure;
        if (error.failure == AffiliateFailure.signInRequired ||
            error.failure == AffiliateFailure.sessionChanged)
          _evict();
      });
    }
  }

  Future<void> _history({bool more = false}) async {
    final overview = _overview;
    if (overview == null ||
        _historyLoading ||
        !widget.repository.owns(overview.owner))
      return;
    final generation = _generation;
    final cursor = more ? _cursor : null;
    setState(() {
      _historyLoading = true;
      _historyFailed = false;
    });
    try {
      final page = await widget.repository.loadPayouts(
        overview.owner,
        cursor: cursor,
      );
      if (!_current(generation, overview.owner)) return;
      setState(() {
        _payouts = List.unmodifiable(
          more ? [..._payouts, ...page.items] : page.items,
        );
        _cursor = page.nextCursor;
        _historyLoaded = true;
        _historyLoading = false;
      });
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _historyLoading = false;
        if (error.failure == AffiliateFailure.signInRequired ||
            error.failure == AffiliateFailure.sessionChanged) {
          _evict();
          _failure = error.failure;
        } else {
          _historyFailed = true;
        }
      });
    }
  }

  Future<void> _signIn() async {
    final signIn = widget.onSignIn;
    if (signIn == null || _loading) return;
    final generation = ++_generation;
    setState(() {
      _evict();
      _loading = true;
    });
    try {
      await signIn(context);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failure = AffiliateFailure.unavailable;
      });
      return;
    }
    if (!mounted || generation != _generation) return;
    await _load();
  }

  Future<void> _balanceHistory({bool more = false}) async {
    final overview = _overview;
    if (overview == null ||
        _entriesLoading ||
        !widget.repository.owns(overview.owner))
      return;
    final generation = _generation;
    setState(() {
      _entriesLoading = true;
      _entriesFailed = false;
    });
    try {
      final page = await widget.repository.loadEntries(
        overview.owner,
        cursor: more ? _entriesCursor : null,
      );
      if (!_current(generation, overview.owner)) return;
      setState(() {
        _entries = List.unmodifiable(
          more ? [..._entries, ...page.items] : page.items,
        );
        _entriesCursor = page.nextCursor;
        _entriesLoaded = true;
        _entriesLoading = false;
      });
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _entriesLoading = false;
        if (error.failure == AffiliateFailure.signInRequired ||
            error.failure == AffiliateFailure.sessionChanged) {
          _evict();
          _failure = error.failure;
        } else {
          _entriesFailed = true;
        }
      });
    }
  }

  Future<void> _bank() async {
    final overview = _overview;
    if (overview == null ||
        _applying ||
        !widget.repository.owns(overview.owner))
      return;
    final generation = _generation;
    final fields = await showAffiliateForm(
      context,
      repository: widget.repository,
      owner: overview.owner,
      title: 'bankAdd',
      description: 'bankInfo',
      fields: const [
        AffiliateField('iban', 'iban', maxLength: 80),
        AffiliateField('holder', 'holder'),
      ],
    );
    if (fields == null || !_current(generation, overview.owner)) return;
    setState(() {
      _applying = true;
      _failure = null;
    });
    try {
      final value = await widget.repository.saveBank(
        overview,
        iban: fields['iban']!,
        holder: fields['holder']!,
      );
      if (!_current(generation, value.owner)) return;
      setState(() {
        _show(value);
        _applying = false;
      });
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _applying = false;
        _failure = error.failure;
        if (error.failure == AffiliateFailure.sessionChanged ||
            error.failure == AffiliateFailure.signInRequired)
          _evict();
      });
    }
  }

  Future<void> _editIdentifiers() async {
    final overview = _overview;
    final profile = overview?.data.profile;
    if (overview == null ||
        profile?.applicantType != 'business' ||
        overview.data.status != 'pending' ||
        _applying ||
        !widget.repository.owns(overview.owner))
      return;
    final generation = _generation;
    final fields = await showAffiliateForm(
      context,
      repository: widget.repository,
      owner: overview.owner,
      title: 'editIdentifiers',
      description: 'identifiersInfo',
      fields: [
        AffiliateField(
          'company_registration_number',
          'companyRegistrationNumber',
          initial: profile!.companyRegistrationNumber,
          optional: true,
          maxLength: 64,
          preserveWhitespace: true,
        ),
        AffiliateField(
          'vat_number',
          'vatNumber',
          initial: profile.vatNumber,
          optional: true,
          maxLength: 64,
          preserveWhitespace: true,
        ),
      ],
    );
    if (fields == null || !_current(generation, overview.owner)) return;
    setState(() {
      _applying = true;
      _failure = null;
    });
    try {
      final value = await widget.repository.updateApplicationIdentifiers(
        overview,
        companyRegistrationNumber: fields['company_registration_number']!,
        vatNumber: fields['vat_number']!,
      );
      if (!_current(generation, value.owner)) return;
      setState(() {
        _show(value);
        _applying = false;
      });
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _applying = false;
        _failure = error.failure;
        if (error.failure == AffiliateFailure.sessionChanged ||
            error.failure == AffiliateFailure.signInRequired)
          _evict();
      });
    }
  }

  Future<void> _referralHistory({bool more = false}) async {
    final overview = _overview;
    if (overview == null ||
        _referralsLoading ||
        !widget.repository.owns(overview.owner))
      return;
    final generation = _generation;
    setState(() {
      _referralsLoading = true;
      _referralsFailed = false;
    });
    try {
      final page = await widget.repository.loadReferrals(
        overview.owner,
        cursor: more ? _referralsCursor : null,
      );
      if (!_current(generation, overview.owner)) return;
      setState(() {
        _referrals = List.unmodifiable(
          more ? [..._referrals, ...page.items] : page.items,
        );
        _referralsCursor = page.nextCursor;
        _referralsLoaded = true;
        _referralsLoading = false;
      });
    } on AffiliateException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _referralsLoading = false;
        if (error.failure == AffiliateFailure.sessionChanged ||
            error.failure == AffiliateFailure.signInRequired) {
          _evict();
          _failure = error.failure;
        } else {
          _referralsFailed = true;
        }
      });
    }
  }

  Future<void> _copy() async {
    final overview = _overview;
    if (overview?.data.referralCode == null ||
        !widget.repository.owns(overview!.owner))
      return;
    final generation = _generation;
    await Clipboard.setData(ClipboardData(text: overview.data.referralCode!));
    if (!mounted || !_current(generation, overview.owner)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(affiliateLabel('copied', appLanguageNotifier.value)),
      ),
    );
  }

  String _money(int cents, String currency, AppLanguage language) {
    final amount = (cents / 100).toStringAsFixed(2);
    return '$currency ${language == AppLanguage.en ? amount : amount.replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: appLanguageNotifier,
    builder: (context, language, _) {
      String t(String key) => affiliateLabel(key, language);
      final data = _overview?.data;
      final failure = _failure;
      return Scaffold(
        appBar: AppBar(
          title: Text(t('title')),
          actions: [
            IconButton(
              key: const Key('affiliate_refresh'),
              tooltip: t('refresh'),
              onPressed: _loading || _applying ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        t('intro'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      if (failure != null) ...[
                        Text(
                          t(switch (failure) {
                            AffiliateFailure.signInRequired => 'personal',
                            AffiliateFailure.sessionChanged => 'changed',
                            AffiliateFailure.termsChanged => 'termsChanged',
                            AffiliateFailure.identifiersInvalid =>
                              'identifiersInvalid',
                            AffiliateFailure.unavailable => 'unavailable',
                          }),
                          key: const Key('affiliate_error'),
                        ),
                        const SizedBox(height: 12),
                        if (failure == AffiliateFailure.signInRequired &&
                            widget.onSignIn != null)
                          FilledButton(
                            key: const Key('affiliate_signin'),
                            onPressed: _signIn,
                            child: Text(t('login')),
                          )
                        else
                          OutlinedButton(
                            key: const Key('affiliate_retry'),
                            onPressed: _load,
                            child: Text(t('retry')),
                          ),
                      ],
                      if (data != null) ...[
                        if (data.canAdminister)
                          OutlinedButton.icon(
                            key: const Key('affiliate_admin'),
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                            label: Text(t('admin')),
                            onPressed: () {
                              final overview = _overview;
                              if (overview == null ||
                                  !widget.repository.owns(overview.owner))
                                return;
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => AffiliateAdminPage(
                                    repository: AffiliateAdminRepository(
                                      widget.repository,
                                      overview,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        Text(
                          t(data.status),
                          key: const Key('affiliate_status'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (data.referralCode != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t('code')),
                                  SelectableText(
                                    data.referralCode!,
                                    key: const Key('affiliate_code'),
                                  ),
                                  TextButton(
                                    onPressed: _copy,
                                    child: Text(t('copy')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (data.status == 'not_enrolled' && data.mayApply) ...[
                          Text(
                            t('terms'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SelectableText(
                            data.termsText,
                            key: const Key('affiliate_terms'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('affiliate_name'),
                            controller: _name,
                            maxLength: 200,
                            enabled: !_applying,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(labelText: t('name')),
                          ),
                          DropdownButtonFormField<String>(
                            key: const Key('affiliate_applicant_type'),
                            initialValue: _applicantType,
                            decoration: InputDecoration(
                              labelText: t('applicantType'),
                            ),
                            items: ['person', 'business']
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(t(type)),
                                  ),
                                )
                                .toList(),
                            onChanged: _applying
                                ? null
                                : (value) => setState(() {
                                    _applicantType = value ?? 'person';
                                    if (_applicantType != 'business') {
                                      _registrationNumber.clear();
                                      _vatNumber.clear();
                                    }
                                  }),
                          ),
                          if (_applicantType == 'business') ...[
                            TextField(
                              key: const Key('affiliate_legal_name'),
                              controller: _legalName,
                              enabled: !_applying,
                              maxLength: 160,
                              decoration: InputDecoration(
                                labelText: t('legalName'),
                              ),
                            ),
                            TextField(
                              key: const Key('affiliate_address'),
                              controller: _address,
                              enabled: !_applying,
                              maxLength: 320,
                              decoration: InputDecoration(
                                labelText: t('address'),
                              ),
                            ),
                            TextField(
                              key: const Key('affiliate_country'),
                              controller: _country,
                              enabled: !_applying,
                              maxLength: 2,
                              decoration: InputDecoration(
                                labelText: t('country'),
                              ),
                            ),
                            Text(t('identifiersInfo')),
                            TextField(
                              key: const Key(
                                'affiliate_company_registration_number',
                              ),
                              controller: _registrationNumber,
                              enabled: !_applying,
                              maxLength: 64,
                              decoration: InputDecoration(
                                labelText: t('companyRegistrationNumber'),
                              ),
                            ),
                            TextField(
                              key: const Key('affiliate_vat_number'),
                              controller: _vatNumber,
                              enabled: !_applying,
                              maxLength: 64,
                              decoration: InputDecoration(
                                labelText: t('vatNumber'),
                              ),
                            ),
                          ],
                          CheckboxListTile(
                            key: const Key('affiliate_accept'),
                            contentPadding: EdgeInsets.zero,
                            value: _accepted,
                            title: Text(t('accept')),
                            onChanged: _applying
                                ? null
                                : (value) =>
                                      setState(() => _accepted = value == true),
                          ),
                          FilledButton(
                            key: const Key('affiliate_apply'),
                            onPressed:
                                _applying ||
                                    !_accepted ||
                                    _name.text.trim().isEmpty ||
                                    failure == AffiliateFailure.termsChanged
                                ? null
                                : _apply,
                            child: _applying
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(t('apply')),
                          ),
                        ],
                        if (data.status != 'not_enrolled') ...[
                          if (data.profile?.applicantType == 'business') ...[
                            Text(
                              '${t('companyRegistrationNumber')}: ${data.profile!.companyRegistrationNumber.isEmpty ? t('identifierUnknown') : data.profile!.companyRegistrationNumber}',
                              key: const Key(
                                'affiliate_own_registration_number',
                              ),
                            ),
                            Text(
                              '${t('vatNumber')}: ${data.profile!.vatNumber.isEmpty ? t('identifierUnknown') : data.profile!.vatNumber}',
                              key: const Key('affiliate_own_vat_number'),
                            ),
                            if (data.status == 'pending')
                              TextButton.icon(
                                key: const Key('affiliate_edit_identifiers'),
                                onPressed: _applying ? null : _editIdentifiers,
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(t('editIdentifiers')),
                              ),
                          ],
                          Text(
                            t(
                              data.bankVerified
                                  ? 'bankVerified'
                                  : 'bankPending',
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('affiliate_bank'),
                            onPressed: _applying ? null : _bank,
                            icon: const Icon(Icons.account_balance_outlined),
                            label: Text(t('bankAdd')),
                          ),
                          Text('${t('referred')}: ${data.referredCompanies}'),
                          TextButton(
                            key: const Key('affiliate_referrals'),
                            onPressed: _referralsLoading
                                ? null
                                : _referralHistory,
                            child: Text(t('referrals')),
                          ),
                          if (_referralsLoading)
                            const Center(child: CircularProgressIndicator()),
                          if (_referralsFailed) Text(t('unavailable')),
                          if (_referralsLoaded &&
                              !_referralsFailed &&
                              _referrals.isEmpty)
                            Text(t('empty')),
                          for (final row in _referrals)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(t(row.state)),
                              subtitle: Text(
                                row.createdAt.substring(
                                  0,
                                  row.createdAt.length < 10
                                      ? row.createdAt.length
                                      : 10,
                                ),
                              ),
                            ),
                          if (_referralsCursor != null &&
                              !_referralsLoading &&
                              !_referralsFailed)
                            TextButton(
                              onPressed: () => _referralHistory(more: true),
                              child: Text(t('more')),
                            ),
                          if (data.balances.isEmpty) Text(t('noBalance')),
                          for (final balance in data.balances)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${t('balance')}: ${_money(balance.balanceCents, balance.currency, language)}',
                                    ),
                                    Text(
                                      '${t('reserved')}: ${_money(balance.reservedCents, balance.currency, language)}',
                                    ),
                                    Text(
                                      '${t('available')}: ${_money(balance.availableCents, balance.currency, language)}',
                                    ),
                                    Text(
                                      '${t('paid')}: ${_money(balance.paidCents, balance.currency, language)}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (data.heldReceipts > 0) ...[
                            Text(
                              '${t('held')}: ${data.heldReceipts}',
                              key: const Key('affiliate_held'),
                            ),
                            Text(t('heldInfo')),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            t('entries'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_entriesFailed) ...[
                            Text(t('unavailable')),
                            TextButton(
                              key: const Key('affiliate_entries_retry'),
                              onPressed: () =>
                                  _balanceHistory(more: _entriesCursor != null),
                              child: Text(t('retry')),
                            ),
                          ],
                          if (_entriesLoaded &&
                              !_entriesFailed &&
                              _entries.isEmpty)
                            Text(t('noEntries')),
                          for (final entry in _entries)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${entry.period} · ${_money(entry.cents, entry.currency, language)}',
                              ),
                              subtitle: Text(t(entry.kind)),
                            ),
                          if (_entriesLoading)
                            const Center(child: CircularProgressIndicator()),
                          if (_entriesCursor != null &&
                              !_entriesLoading &&
                              !_entriesFailed)
                            TextButton(
                              onPressed: () => _balanceHistory(more: true),
                              child: Text(t('more')),
                            ),
                          const SizedBox(height: 20),
                          Text(
                            t('history'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_historyFailed) ...[
                            Text(t('unavailable')),
                            TextButton(
                              key: const Key('affiliate_history_retry'),
                              onPressed: () => _history(more: _cursor != null),
                              child: Text(t('retry')),
                            ),
                          ],
                          if (_historyLoaded &&
                              !_historyFailed &&
                              _payouts.isEmpty)
                            Text(t('noHistory')),
                          for (final payout in _payouts)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${payout.period} · ${_money(payout.cents, payout.currency, language)}',
                              ),
                              subtitle: Text(t(payout.state)),
                            ),
                          if (_historyLoading)
                            const Center(child: CircularProgressIndicator()),
                          if (_cursor != null &&
                              !_historyLoading &&
                              !_historyFailed)
                            TextButton(
                              onPressed: () => _history(more: true),
                              child: Text(t('more')),
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
