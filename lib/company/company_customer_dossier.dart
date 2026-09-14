// COMPANY-CUSTOMER-OPS-P0 — readable customer dossier shared by list and workspace.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_list.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';

const Key kCompanyCustomerDossierKey = Key('company_customer_dossier');
const Key kCompanyCustomerQuotesSectionKey = Key(
  'company_customer_quotes_section',
);

Key companyCustomerQuoteRowKey(String quoteId) =>
    Key('company_customer_quote_row_$quoteId');

Key companyCustomerPlannedBookingRowKey(String bookingId) =>
    Key('company_customer_planned_booking_$bookingId');

String companyCustomerPlannedBookingSubtitle(CompanyAgendaRide ride) {
  final start = ride.pickupUtc?.toLocal();
  final when = start == null
      ? ''
      : '${start.day.toString().padLeft(2, '0')}-'
            '${start.month.toString().padLeft(2, '0')} '
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}';
  final route = '${ride.fromAddress} → ${ride.toAddress}';
  final status = ride.status.trim();
  return <String>[
    if (when.isNotEmpty) when,
    route,
    if (status.isNotEmpty) status,
  ].join(' · ');
}

String companyCustomerPlannedBookingTitle(
  CompanyAgendaRide ride,
  AppLanguage language,
) {
  return companyAgendaRideDisplayTitle(ride, language);
}

class CompanyCustomerDossier extends StatelessWidget {
  const CompanyCustomerDossier({
    super.key,
    required this.customer,
    required this.language,
    required this.repository,
    this.issuerName,
    this.onOpenBooking,
    this.onEdit,
    this.reloadToken = 0,
    this.plannedRides = const <CompanyAgendaRide>[],
    this.actions = const <Widget>[],
  });

  final CompanyCustomer customer;
  final AppLanguage language;
  final CompanyCustomersRepository repository;
  final String? issuerName;
  final void Function(String bookingId)? onOpenBooking;
  final VoidCallback? onEdit;
  final int reloadToken;
  final List<CompanyAgendaRide> plannedRides;
  final List<Widget> actions;

  String _value(String raw) {
    final text = raw.trim();
    return text.isEmpty ? kCompanyCustomersNotFilled.of(language) : text;
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: ${_value(value)}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactPerson = [
      customer.firstName,
      customer.lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    return ListView(
      key: kCompanyCustomerDossierKey,
      padding: const EdgeInsets.all(16),
      children: [
        _section(kCompanyCustomersIdentityGroup.of(language), [
          _line(kCompanyCustomersDisplayName.of(language), customer.displayName),
          _line(kCompanyCustomersFirstName.of(language), customer.firstName),
          _line(kCompanyCustomersLastName.of(language), customer.lastName),
          if (customer.companyName.isNotEmpty)
            _line(kCompanyCustomersContactPerson.of(language), contactPerson),
        ]),
        _section(kCompanyCustomersContactGroup.of(language), [
          _line(kCompanyCustomersEmail.of(language), customer.email),
          _line(kCompanyCustomersPhone.of(language), customer.phone),
          _line(
            kCompanyCustomersCallingCode.of(language),
            customer.countryCallingCode,
          ),
          _line(kCompanyCustomersLocale.of(language), customer.locale),
          if (customer.preferences.preferredLocale.trim().isNotEmpty &&
              customer.preferences.preferredLocale.trim() !=
                  customer.locale.trim())
            _line(
              kCompanyCustomersLocale.of(language),
              customer.preferences.preferredLocale,
            ),
        ]),
        _section(kCompanyCustomersCompanyGroup.of(language), [
          _line(kCompanyCustomersCompanyName.of(language), customer.companyName),
          _line(kCompanyCustomersVat.of(language), customer.vatNumber),
        ]),
        _section(kCompanyCustomersAddresses.of(language), [
          if (customer.addresses.isEmpty)
            Text(kCompanyCustomersNotFilled.of(language))
          else
            for (final address in customer.addresses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  [
                    companyCustomerAddressTypeLabel(address.type, language),
                    if (address.label.trim().isNotEmpty) address.label,
                    if (address.line1.trim().isNotEmpty) address.line1,
                    if (address.line2.trim().isNotEmpty) address.line2,
                    if (address.postalCode.trim().isNotEmpty) address.postalCode,
                    if (address.city.trim().isNotEmpty) address.city,
                    if (address.countryCode.trim().isNotEmpty)
                      address.countryCode,
                    if (address.notes.trim().isNotEmpty) address.notes,
                  ].join(' · '),
                ),
              ),
        ]),
        _section(kCompanyCustomersInternalNotes.of(language), [
          Text(_value(customer.internalNotes)),
        ]),
        _CompanyCustomerLinkedRecords(
          key: ValueKey<String>(
            '${customer.customerId}-$reloadToken',
          ),
          repository: repository,
          customer: customer,
          language: language,
          issuerName: issuerName,
          reloadToken: reloadToken,
          plannedRides: plannedRides,
          onOpenBooking: onOpenBooking,
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

class _CompanyCustomerLinkedRecords extends StatefulWidget {
  const _CompanyCustomerLinkedRecords({
    super.key,
    required this.repository,
    required this.customer,
    required this.language,
    this.issuerName,
    this.reloadToken = 0,
    this.plannedRides = const <CompanyAgendaRide>[],
    this.onOpenBooking,
  });

  final CompanyCustomersRepository repository;
  final CompanyCustomer customer;
  final AppLanguage language;
  final String? issuerName;
  final int reloadToken;
  final List<CompanyAgendaRide> plannedRides;
  final void Function(String bookingId)? onOpenBooking;

  @override
  State<_CompanyCustomerLinkedRecords> createState() =>
      _CompanyCustomerLinkedRecordsState();
}

class _CompanyCustomerLinkedRecordsState
    extends State<_CompanyCustomerLinkedRecords> {
  List<CompanyCustomerQuote> _quotes = const <CompanyCustomerQuote>[];
  String? _quotesError;
  bool _loadingQuotes = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CompanyCustomerLinkedRecords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.customerId != widget.customer.customerId ||
        oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loadingQuotes = true;
      _quotesError = null;
    });
    try {
      final items = await widget.repository.listQuotes(
        widget.customer.customerId,
      );
      if (!mounted) return;
      setState(() {
        _quotes = items;
        _loadingQuotes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quotesError = kCompanyCustomersQuotesError.of(widget.language);
        _loadingQuotes = false;
      });
    }
  }

  Future<void> _openQuote(CompanyCustomerQuote? existing) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanyCustomerQuotePage(
          repository: widget.repository,
          customer: widget.customer,
          existing: existing,
          language: widget.language,
          issuerName: widget.issuerName,
          onOpenBooking: widget.onOpenBooking,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final quoteBookings = _quotes
        .where((quote) => quote.bookingId.trim().isNotEmpty)
        .toList();
    final quoteBookingIds = <String>{
      for (final quote in quoteBookings) quote.bookingId.trim(),
    };
    final planned = widget.plannedRides
        .where(
          (ride) =>
              ride.customerId == widget.customer.customerId &&
              ride.bookingId.trim().isNotEmpty &&
              !quoteBookingIds.contains(ride.bookingId.trim()),
        )
        .toList();
    final hasBookings = quoteBookings.isNotEmpty || planned.isNotEmpty;
    return Column(
      key: kCompanyCustomerQuotesSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kCompanyCustomerQuotesTitle.of(widget.language),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (_quotesError != null)
          TextButton(
            onPressed: _load,
            child: Text(_quotesError!),
          )
        else if (_loadingQuotes && _quotes.isEmpty)
          Text(kCompanyCustomersLoading.of(widget.language))
        else if (_quotes.isEmpty)
          Text(kCompanyCustomersNoQuotes.of(widget.language))
        else
          for (final quote in _quotes)
            ListTile(
              key: companyCustomerQuoteRowKey(quote.quoteId),
              contentPadding: EdgeInsets.zero,
              title: Text(
                companyCustomerQuoteListTitle(
                  quote: quote,
                  language: widget.language,
                ),
              ),
              subtitle: Text(
                companyCustomerQuoteListSubtitle(quote),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _openQuote(quote),
            ),
        const SizedBox(height: 16),
        Text(
          kCompanyCustomersBookingsGroup.of(widget.language),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (!hasBookings)
          Text(kCompanyCustomersNoBookings.of(widget.language))
        else ...[
          for (final quote in quoteBookings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(quote.bookingId),
              subtitle: Text('${quote.pickup} → ${quote.dropoff}'),
              onTap: widget.onOpenBooking == null
                  ? null
                  : () => widget.onOpenBooking!(quote.bookingId),
            ),
          for (final ride in planned)
            ListTile(
              key: companyCustomerPlannedBookingRowKey(ride.collectionId),
              contentPadding: EdgeInsets.zero,
              title: Text(
                companyCustomerPlannedBookingTitle(ride, widget.language),
              ),
              subtitle: Text(companyCustomerPlannedBookingSubtitle(ride)),
              onTap: widget.onOpenBooking == null
                  ? null
                  : () => widget.onOpenBooking!(ride.collectionId),
            ),
        ],
      ],
    );
  }
}
