// COMPANY-CUSTOMER-OPS-P0A

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_form_page.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

const Key kCompanyCustomersPageKey = Key('company_customers_page');
const Key kCompanyCustomersSearchFieldKey = Key('company_customers_search');
const Key kCompanyCustomersAddButtonKey = Key('company_customers_add');
const Key kCompanyCustomersLoadMoreKey = Key('company_customers_load_more');
const Key kCompanyCustomersListKey = Key('company_customers_list');
const Key kCompanyCustomersDetailPaneKey = Key('company_customers_detail_pane');
const Key kCompanyCustomersArchiveButtonKey = Key('company_customers_archive');
const Key kCompanyCustomersRestoreButtonKey = Key('company_customers_restore');
const Key kCompanyCustomersActiveFilterKey = Key(
  'company_customers_filter_active',
);
const Key kCompanyCustomersArchivedFilterKey = Key(
  'company_customers_filter_archived',
);
const Key kCompanyCustomersEditButtonKey = Key('company_customers_edit');

const double kCompanyCustomersSplitBreakpoint = 720;

class CompanyCustomersPage extends StatefulWidget {
  const CompanyCustomersPage({
    super.key,
    this.repository,
    this.language,
  });

  final CompanyCustomersRepository? repository;
  final AppLanguage? language;

  @override
  State<CompanyCustomersPage> createState() => CompanyCustomersPageState();
}

class CompanyCustomersPageState extends State<CompanyCustomersPage> {
  late final CompanyCustomersRepository _repository;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _loading = true;
  bool _loadingMore = false;
  bool _acting = false;
  String _status = 'active';
  String _query = '';
  String? _error;
  bool _offline = false;
  final List<CompanyCustomerListItem> _items = <CompanyCustomerListItem>[];
  String? _nextCursor;
  bool _hasMore = false;
  int? _totalCount;
  String? _selectedId;
  CompanyCustomer? _selected;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? CompanyCustomersRepository();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CompanyCustomersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repository != oldWidget.repository && widget.repository != null) {
      _repository = widget.repository!;
      _reload();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
      _items.clear();
      _nextCursor = null;
      _hasMore = false;
      _totalCount = null;
    });
    try {
      final page = await _repository.list(status: _status, query: _query);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _totalCount = page.totalCount;
        _loading = false;
      });
      if (_selectedId != null) {
        await _loadSelected(_selectedId!);
      }
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = error.offline;
        _error = error.code == 'missing_tenant_scope'
            ? kCompanyCustomersMissingScope.of(_lang)
            : error.offline
            ? kCompanyCustomersOffline.of(_lang)
            : kCompanyCustomersError.of(_lang);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = kCompanyCustomersError.of(_lang);
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = (_nextCursor ?? '').trim();
    if (_loadingMore || !_hasMore || cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.list(
        status: _status,
        query: _query,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error.offline
            ? kCompanyCustomersOffline.of(_lang)
            : kCompanyCustomersError.of(_lang);
      });
    }
  }

  Future<void> _loadSelected(String customerId) async {
    try {
      final detail = await _repository.getById(customerId);
      if (!mounted) return;
      setState(() {
        _selectedId = detail.customerId;
        _selected = detail;
      });
    } on CompanyCustomerException {
      if (!mounted) return;
      setState(() {
        _selected = null;
      });
    }
  }

  Future<void> _openSelected(
    CompanyCustomerListItem item, {
    required bool split,
  }) async {
    setState(() => _selectedId = item.customerId);
    await _loadSelected(item.customerId);
    if (!mounted || split) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CompanyCustomerDetailScaffold(
          language: _lang,
          customer: _selected,
          onEdit: () => _editCurrent(),
          onArchive: () => _archiveCurrent(),
          onRestore: () => _restoreCurrent(),
          acting: _acting,
        ),
      ),
    );
  }

  Future<void> _addCustomer() async {
    if (_acting) return;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CompanyCustomerFormPage(
          repository: _repository,
          language: _lang,
        ),
      ),
    );
    if (!mounted) return;
    if (result is CompanyCustomerMutationResult) {
      setState(() => _selectedId = result.customer.customerId);
      if (result.duplicateMatches.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(kCompanyCustomersDuplicateWarning.of(_lang))),
        );
      }
      await _reload();
    }
  }

  Future<void> _editCurrent() async {
    final current = _selected;
    if (current == null || _acting) return;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CompanyCustomerFormPage(
          repository: _repository,
          existing: current,
          language: _lang,
        ),
      ),
    );
    if (!mounted) return;
    if (result is CompanyCustomer) {
      setState(() => _selected = result);
      await _reload();
    }
  }

  Future<void> _archiveCurrent() async {
    final current = _selected;
    if (current == null || _acting) return;
    setState(() => _acting = true);
    try {
      final updated = await _repository.archive(current.customerId);
      if (!mounted) return;
      setState(() {
        _selected = updated;
        _acting = false;
      });
      await _reload();
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _error = error.offline
            ? kCompanyCustomersOffline.of(_lang)
            : kCompanyCustomersSaveFailed.of(_lang);
      });
    }
  }

  Future<void> _restoreCurrent() async {
    final current = _selected;
    if (current == null || _acting) return;
    setState(() => _acting = true);
    try {
      final updated = await _repository.restore(current.customerId);
      if (!mounted) return;
      setState(() {
        _selected = updated;
        _acting = false;
      });
      await _reload();
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _error = error.offline
            ? kCompanyCustomersOffline.of(_lang)
            : kCompanyCustomersSaveFailed.of(_lang);
      });
    }
  }

  void _applySearch(String value) {
    final next = value.trim();
    if (next == _query) return;
    _query = next;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: kCompanyCustomersPageKey,
      appBar: AppBar(title: Text(kCompanyCustomersTitle.of(_lang))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= kCompanyCustomersSplitBreakpoint;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    key: kCompanyCustomersSearchFieldKey,
                    controller: _search,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: kCompanyCustomersSearchHint.of(_lang),
                    ),
                    onSubmitted: _applySearch,
                    onChanged: _applySearch,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        key: kCompanyCustomersActiveFilterKey,
                        selected: _status == 'active',
                        label: Text(kCompanyCustomersActiveFilter.of(_lang)),
                        onSelected: (_) {
                          if (_status == 'active') return;
                          setState(() => _status = 'active');
                          _reload();
                        },
                      ),
                      FilterChip(
                        key: kCompanyCustomersArchivedFilterKey,
                        selected: _status == 'archived',
                        label: Text(kCompanyCustomersArchivedFilter.of(_lang)),
                        onSelected: (_) {
                          if (_status == 'archived') return;
                          setState(() => _status = 'archived');
                          _reload();
                        },
                      ),
                      if (_totalCount != null)
                        Text('$_totalCount', overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: split
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth < 1100
                                  ? 320
                                  : 380,
                              child: _buildList(split: true),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: _buildDetailPane()),
                          ],
                        )
                      : _buildList(split: false),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: kCompanyCustomersAddButtonKey,
                      onPressed: _addCustomer,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(kCompanyCustomersAddLabel.of(_lang)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList({required bool split}) {
    if (_loading) {
      return Center(child: Text(kCompanyCustomersLoading.of(_lang)));
    }
    if (_error != null && _items.isEmpty) {
      return _MessageState(
        message: _error!,
        onRetry: _reload,
        language: _lang,
      );
    }
    if (_items.isEmpty) {
      final empty = _query.isNotEmpty
          ? kCompanyCustomersEmptySearch
          : _status == 'archived'
          ? kCompanyCustomersEmptyArchived
          : kCompanyCustomersEmptyActive;
      return _MessageState(message: empty.of(_lang), language: _lang);
    }
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        Expanded(
          child: ListView.builder(
            key: kCompanyCustomersListKey,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _items.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: OutlinedButton(
                    key: kCompanyCustomersLoadMoreKey,
                    onPressed: _loadingMore ? null : _loadMore,
                    child: Text(kCompanyCustomersLoadMore.of(_lang)),
                  ),
                );
              }
              final item = _items[index];
              final selected = split && item.customerId == _selectedId;
              return Card(
                key: Key('company_customer_row_${item.customerId}'),
                color: selected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : null,
                child: InkWell(
                  autofocus: index == 0,
                  onTap: () => _openSelected(item, split: split),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (item.companyName.isNotEmpty)
                          Text(
                            item.companyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          [
                            if (item.emailMasked.isNotEmpty) item.emailMasked,
                            if (item.phoneMasked.isNotEmpty) item.phoneMasked,
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPane() {
    return ColoredBox(
      key: kCompanyCustomersDetailPaneKey,
      color: Theme.of(context).colorScheme.surface,
      child: _selected == null
          ? Center(child: Text(kCompanyCustomersSelectHint.of(_lang)))
          : _CompanyCustomerDetailBody(
              language: _lang,
              customer: _selected!,
              onEdit: _editCurrent,
              onArchive: _archiveCurrent,
              onRestore: _restoreCurrent,
              acting: _acting,
            ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.message,
    required this.language,
    this.onRetry,
  });

  final String message;
  final AppLanguage language;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(kCompanyCustomersRetry.of(language)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompanyCustomerDetailScaffold extends StatelessWidget {
  const _CompanyCustomerDetailScaffold({
    required this.language,
    required this.customer,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.acting,
  });

  final AppLanguage language;
  final CompanyCustomer? customer;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final bool acting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(kCompanyCustomersTitle.of(language))),
      body: customer == null
          ? Center(child: Text(kCompanyCustomersError.of(language)))
          : _CompanyCustomerDetailBody(
              language: language,
              customer: customer!,
              onEdit: onEdit,
              onArchive: onArchive,
              onRestore: onRestore,
              acting: acting,
            ),
    );
  }
}

class _CompanyCustomerDetailBody extends StatelessWidget {
  const _CompanyCustomerDetailBody({
    required this.language,
    required this.customer,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    required this.acting,
  });

  final AppLanguage language;
  final CompanyCustomer customer;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final bool acting;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          customer.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (customer.companyName.isNotEmpty) Text(customer.companyName),
        const SizedBox(height: 12),
        if (customer.email.isNotEmpty) Text(customer.email),
        if (customer.phone.isNotEmpty) Text(customer.phone),
        if (customer.locale.isNotEmpty) Text(customer.locale),
        if (customer.vatNumber.isNotEmpty) Text(customer.vatNumber),
        const SizedBox(height: 16),
        Text(kCompanyCustomersAddresses.of(language)),
        for (final address in customer.addresses)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                address.type,
                address.line1,
                address.city,
                address.postalCode,
                address.countryCode,
              ].where((part) => part.trim().isNotEmpty).join(' · '),
            ),
          ),
        const SizedBox(height: 16),
        Text(kCompanyCustomersInternalNotes.of(language)),
        const SizedBox(height: 4),
        Text(
          customer.internalNotes.isEmpty ? '—' : customer.internalNotes,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: kCompanyCustomersEditButtonKey,
              onPressed: acting ? null : onEdit,
              child: Text(kCompanyCustomersEdit.of(language)),
            ),
            if (customer.isArchived)
              OutlinedButton(
                key: kCompanyCustomersRestoreButtonKey,
                onPressed: acting ? null : onRestore,
                child: Text(kCompanyCustomersRestore.of(language)),
              )
            else
              OutlinedButton(
                key: kCompanyCustomersArchiveButtonKey,
                onPressed: acting ? null : onArchive,
                child: Text(kCompanyCustomersArchive.of(language)),
              ),
          ],
        ),
      ],
    );
  }
}
