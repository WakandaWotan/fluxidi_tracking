// COMPANY-CUSTOMER-OPS-P0 — existing GET /bookings/:id detail.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanyBookingDetailPageKey = Key('company_booking_detail_page');

enum CompanyBookingOpenedFrom { quote, bookingsList }

class CompanyBookingDetailPage extends StatefulWidget {
  const CompanyBookingDetailPage({
    super.key,
    required this.bookingId,
    this.language,
    this.loader,
    this.openedFrom = CompanyBookingOpenedFrom.bookingsList,
  });

  final String bookingId;
  final AppLanguage? language;
  final Future<Map<String, dynamic>> Function(String bookingId)? loader;
  final CompanyBookingOpenedFrom openedFrom;

  @override
  State<CompanyBookingDetailPage> createState() =>
      _CompanyBookingDetailPageState();
}

class _CompanyBookingDetailPageState extends State<CompanyBookingDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _row = const <String, dynamic>{};

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await (widget.loader ?? fetchCompanyOpsBookingDetail)(
        widget.bookingId,
      );
      if (!mounted) return;
      setState(() {
        _row = body;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Boeking laden mislukt';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _row['record'] is Map
        ? Map<String, dynamic>.from(_row['record'] as Map)
        : _row;
    final booking = record['booking'] is Map
        ? Map<String, dynamic>.from(record['booking'] as Map)
        : const <String, dynamic>{};
    final quoteId = (record['quote_id'] ?? booking['quote_id'] ?? '').toString();
    final customer = (booking['customer_name'] ??
            record['customer_name'] ??
            '')
        .toString();
    final from = (booking['from'] ?? record['from'] ?? record['pickup'] ?? '')
        .toString();
    final to = (booking['to'] ?? record['to'] ?? record['dropoff'] ?? '')
        .toString();
    final pickup = (booking['pickup_iso'] ??
            record['pickup_iso'] ??
            record['start_at'] ??
            '')
        .toString();
    final pax = booking['pax'] ?? record['pax'] ?? record['passengers'];
    final amount = booking['price_incl_vat'] ?? record['price'];
    final currency = (booking['currency'] ?? record['currency'] ?? 'EUR')
        .toString();
    final status = (_row['status'] ?? record['status'] ?? '').toString();
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyBookingDetailPageKey,
        appBar: AppBar(title: Text(kCompanyCustomerQuoteViewBooking.of(_lang))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Klant: ${customer.isEmpty ? '—' : customer}'),
                  Text('$from → $to'),
                  Text('Datum en tijd: $pickup'),
                  Text('Passagiers: ${pax ?? '—'}'),
                  Text('Bedrag: $currency ${amount ?? '—'}'),
                  if (quoteId.isNotEmpty) Text('Offerte: $quoteId'),
                  Text('Status: $status'),
                  Text(kCompanyCustomerQuoteAssignmentPending.of(_lang)),
                  Text('Boeking: ${widget.bookingId}'),
                  const SizedBox(height: 16),
                  Text(
                    widget.openedFrom == CompanyBookingOpenedFrom.quote
                        ? 'Terug gaat naar de offerte van deze klant.'
                        : 'Terug gaat naar de boekingenlijst.',
                  ),
                ],
              ),
      ),
    );
  }
}

void openCompanyBookingDetail(
  BuildContext context, {
  required String bookingId,
  AppLanguage? language,
  Future<Map<String, dynamic>> Function(String bookingId)? loader,
  CompanyBookingOpenedFrom openedFrom = CompanyBookingOpenedFrom.bookingsList,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CompanyBookingDetailPage(
        bookingId: bookingId,
        language: language,
        loader: loader,
        openedFrom: openedFrom,
      ),
    ),
  );
}
