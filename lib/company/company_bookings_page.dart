// COMPANY-CUSTOMER-OPS-P0 — existing company bookings list on Windows.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_booking_list_item.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanyBookingsPageKey = Key('company_bookings_page');
const Key kCompanyBookingsFilterOpenKey = Key('company_bookings_filter_open');
const Key kCompanyBookingsLoadMoreKey = Key('company_bookings_load_more');

class CompanyBookingsPage extends StatefulWidget {
  const CompanyBookingsPage({
    super.key,
    this.language,
    this.pageLoader,
    this.detailLoader,
  });

  final AppLanguage? language;
  final Future<BookingListPageResult> Function({
    String cursor,
    bool forceRefresh,
  })?
  pageLoader;
  final Future<Map<String, dynamic>> Function(String bookingId)? detailLoader;

  @override
  State<CompanyBookingsPage> createState() => _CompanyBookingsPageState();
}

class _CompanyBookingsPageState extends State<CompanyBookingsPage> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _nextCursor;
  bool _hasMore = false;
  CompanyBookingListBucket _filter = CompanyBookingListBucket.open;
  List<CompanyBookingListItem> _all = const <CompanyBookingListItem>[];

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String cursor = '', bool forceRefresh = false}) async {
    setState(() {
      if (cursor.isEmpty) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await (widget.pageLoader ?? fetchCompanyOpsBookingPage)(
        cursor: cursor,
        forceRefresh: forceRefresh,
      );
      final parsed = sortCompanyBookingListItems(
        page.items.map(CompanyBookingListItem.fromMap),
      );
      if (!mounted) return;
      setState(() {
        _all = cursor.isEmpty
            ? parsed
            : sortCompanyBookingListItems(<CompanyBookingListItem>[
                ..._all,
                ...parsed,
              ]);
        _hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Boekingen laden is mislukt.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  List<CompanyBookingListItem> get _visible =>
      _all.where((item) => item.bucket == _filter).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyBookingsPageKey,
        appBar: AppBar(
          title: const Text('Boekingen'),
          actions: [
            IconButton(
              onPressed: _loading
                  ? null
                  : () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  for (final bucket in CompanyBookingListBucket.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        key: bucket == CompanyBookingListBucket.open
                            ? kCompanyBookingsFilterOpenKey
                            : Key('company_bookings_filter_${bucket.name}'),
                        selected: _filter == bucket,
                        label: Text(_filterLabel(bucket)),
                        onSelected: (_) => setState(() => _filter = bucket),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _visible.isEmpty
                  ? Center(child: Text(_emptyLabel(_filter)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _visible.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index >= _visible.length) {
                          return TextButton(
                            key: kCompanyBookingsLoadMoreKey,
                            onPressed: _loadingMore || (_nextCursor ?? '').isEmpty
                                ? null
                                : () => _load(cursor: _nextCursor ?? ''),
                            child: Text(
                              _loadingMore ? 'Laden…' : 'Meer laden',
                            ),
                          );
                        }
                        final item = _visible[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.routeLabel),
                            subtitle: Text(
                              [
                                if (item.customerName.isNotEmpty)
                                  item.customerName,
                                if (item.pickupIso.isNotEmpty) item.pickupIso,
                                if (item.quoteId.isNotEmpty)
                                  'Offerte: ${item.quoteId}',
                                'Status: ${item.statusText.isEmpty ? '—' : item.statusText}',
                                if (item.assignedDriverText.isEmpty)
                                  kCompanyCustomerQuoteAssignmentPendingHint,
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            onTap: () => openCompanyBookingDetail(
                              context,
                              bookingId: item.bookingId,
                              language: _lang,
                              loader: widget.detailLoader,
                              openedFrom:
                                  CompanyBookingOpenedFrom.bookingsList,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Toewijzen van chauffeur/voertuig is een placeholder op de Worker. '
                'Annuleren, credit en Mollie-terugbetaling blijven op de bestaande native boekingenpagina. '
                'Dit is geen tweede planner.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _filterLabel(CompanyBookingListBucket bucket) {
    switch (bucket) {
      case CompanyBookingListBucket.open:
        return 'Open';
      case CompanyBookingListBucket.completed:
        return 'Afgerond';
      case CompanyBookingListBucket.cancelled:
        return 'Geannuleerd';
      case CompanyBookingListBucket.toCredit:
        return 'Te crediteren';
      case CompanyBookingListBucket.refundPending:
        return 'Terugbetaling';
      case CompanyBookingListBucket.refunded:
        return 'Terugbetaald';
      case CompanyBookingListBucket.refundFailed:
        return 'Terugbetaling mislukt';
    }
  }

  String _emptyLabel(CompanyBookingListBucket bucket) {
    if (bucket == CompanyBookingListBucket.open) {
      return 'Geen open boekingen voor dit bedrijf.';
    }
    return 'Geen boekingen in dit filter.';
  }
}

const String kCompanyCustomerQuoteAssignmentPendingHint =
    'Chauffeur en voertuig moeten nog toegewezen worden.';
