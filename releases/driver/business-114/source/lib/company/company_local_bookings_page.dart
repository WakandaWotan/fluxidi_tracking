// COMPANY-CUSTOMER-OPS-P0 — local demo surface for GET /bookings.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanyLocalBookingsPageKey = Key('company_local_bookings_page');
const Key kCompanyLocalBookingDetailKey = Key('company_local_booking_detail');
const Key kCompanyLocalBookingsNavKey = Key('company_local_bookings_nav');

class CompanyLocalBookingsPage extends StatefulWidget {
  const CompanyLocalBookingsPage({super.key, this.language});

  final AppLanguage? language;

  @override
  State<CompanyLocalBookingsPage> createState() =>
      _CompanyLocalBookingsPageState();
}

class _CompanyLocalBookingsPageState extends State<CompanyLocalBookingsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await fetchCompanyLocalBookings();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = kCompanyCustomersLoadFailedNl;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
      key: kCompanyLocalBookingsPageKey,
      appBar: AppBar(
        title: const Text('Boekingen'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Nog geen boekingen'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final bookingId =
                            item['booking_id']?.toString().trim() ?? '';
                        return Card(
                          child: ListTile(
                            title: Text(_routeLabel(item)),
                            subtitle: Text(_subtitle(item, _lang)),
                            isThreeLine: true,
                            onTap: bookingId.isEmpty
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            CompanyLocalBookingDetailPage(
                                          bookingId: bookingId,
                                          language: _lang,
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        );
                      },
                    ),
    ),
    );
  }
}

class CompanyLocalBookingDetailPage extends CompanyBookingDetailPage {
  const CompanyLocalBookingDetailPage({
    super.key,
    required super.bookingId,
    super.language,
  }) : super(openedFrom: CompanyBookingOpenedFrom.bookingsList);
}

const String kCompanyCustomersLoadFailedNl = 'Boekingen laden mislukt';

String _routeLabel(Map<String, dynamic> item) {
  final from = item['from']?.toString().trim() ?? '';
  final to = item['to']?.toString().trim() ?? '';
  if (from.isEmpty && to.isEmpty) {
    return item['booking_id']?.toString() ?? 'Boeking';
  }
  return '$from → $to';
}

String _subtitle(Map<String, dynamic> item, AppLanguage lang) {
  final customer = item['customer_name']?.toString().trim() ?? '';
  final pickup = item['pickup_iso']?.toString().trim() ?? '';
  final pax = item['pax'];
  final price = item['price'];
  final currency = item['currency']?.toString().trim().isNotEmpty == true
      ? item['currency'].toString()
      : 'EUR';
  final quoteId = item['quote_id']?.toString().trim() ??
      item['planning_reference']?.toString().trim() ??
      '';
  return [
    if (customer.isNotEmpty) customer,
    if (pickup.isNotEmpty) pickup,
    if (pax != null) 'Passagiers: $pax',
    if (price != null) '$currency $price',
    if (quoteId.isNotEmpty) 'Offerte: $quoteId',
    kCompanyCustomerQuoteAssignmentPending.of(lang),
  ].join('\n');
}
