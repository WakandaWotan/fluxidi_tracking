// COMPANY-CUSTOMER-OPS-P0

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/company_session_store.dart';

const Key kCompanyCustomerQuotePageKey = Key('company_customer_quote_page');
const Key kCompanyCustomerQuoteSaveKey = Key('company_customer_quote_save');
const Key kCompanyCustomerQuoteReviewKey = Key('company_customer_quote_review');
const Key kCompanyCustomerQuoteSendKey = Key('company_customer_quote_send');
const Key kCompanyCustomerQuotePriceKey = Key('company_customer_quote_price');
const Key kCompanyCustomerQuoteEmailKey = Key('company_customer_quote_email');

class CompanyCustomerQuotePage extends StatefulWidget {
  const CompanyCustomerQuotePage({
    super.key,
    required this.repository,
    required this.customer,
    this.existing,
    this.language,
    this.issuerName,
  });

  final CompanyCustomersRepository repository;
  final CompanyCustomer customer;
  final CompanyCustomerQuote? existing;
  final AppLanguage? language;
  final String? issuerName;

  @override
  State<CompanyCustomerQuotePage> createState() =>
      _CompanyCustomerQuotePageState();
}

class _CompanyCustomerQuotePageState extends State<CompanyCustomerQuotePage> {
  late final TextEditingController _pickup;
  late final TextEditingController _dropoff;
  late final TextEditingController _startAt;
  late final TextEditingController _passengers;
  late final TextEditingController _description;
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _price;
  late final TextEditingController _validUntil;
  CompanyCustomerQuote? _quote;
  bool _review = false;
  bool _busy = false;
  String? _error;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  String get _issuer {
    final explicit = widget.issuerName?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final profile = companyProfileNotifier.value?.companyName.trim() ?? '';
    if (profile.isNotEmpty) return profile;
    return widget.customer.companyId;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _quote = existing;
    _pickup = TextEditingController(text: existing?.pickup ?? '');
    _dropoff = TextEditingController(text: existing?.dropoff ?? '');
    _startAt = TextEditingController(text: existing?.startAt ?? '');
    _passengers = TextEditingController(
      text: '${existing?.passengers ?? 1}',
    );
    _description = TextEditingController(text: existing?.description ?? '');
    _name = TextEditingController(
      text: existing?.passengerName.isNotEmpty == true
          ? existing!.passengerName
          : widget.customer.displayName,
    );
    _email = TextEditingController(
      text: existing?.passengerEmail.isNotEmpty == true
          ? existing!.passengerEmail
          : widget.customer.email,
    );
    _phone = TextEditingController(
      text: existing?.passengerPhone.isNotEmpty == true
          ? existing!.passengerPhone
          : widget.customer.phone,
    );
    _price = TextEditingController(
      text: existing?.enteredAmountCents != null
          ? (existing!.enteredAmountCents! / 100).toStringAsFixed(2)
          : '80.00',
    );
    _validUntil = TextEditingController(text: existing?.validUntil ?? '');
  }

  @override
  void dispose() {
    _pickup.dispose();
    _dropoff.dispose();
    _startAt.dispose();
    _passengers.dispose();
    _description.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _price.dispose();
    _validUntil.dispose();
    super.dispose();
  }

  CompanyCustomerQuoteWrite _write() {
    return CompanyCustomerQuoteWrite(
      pickup: _pickup.text,
      dropoff: _dropoff.text,
      startAt: _startAt.text,
      passengers: int.tryParse(_passengers.text.trim()) ?? 1,
      description: _description.text,
      passengerName: _name.text,
      passengerEmail: _email.text,
      passengerPhone: _phone.text,
      enteredAmountCents: parseEuroToCents(_price.text),
      validUntil: _validUntil.text,
      issuerName: _issuer,
    );
  }

  Future<void> _saveDraft() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final write = _write();
      final current = _quote;
      final saved = current == null
          ? await widget.repository.createQuote(
              widget.customer.customerId,
              write,
            )
          : await widget.repository.updateQuote(
              current.quoteId,
              write,
              revision: current.revision,
            );
      if (!mounted) return;
      setState(() {
        _quote = saved;
        _busy = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'invalid_quote'
            ? kCompanyCustomersSaveFailed.of(_lang)
            : error.offline
                ? kCompanyCustomersOffline.of(_lang)
                : kCompanyCustomersSaveFailed.of(_lang);
      });
    }
  }

  Future<void> _send() async {
    if (!isUsableCompanyCustomerEmail(_email.text)) {
      setState(() => _error = kCompanyCustomerQuoteEmailRequired.of(_lang));
      return;
    }
    await _saveDraft();
    final current = _quote;
    if (current == null) return;
    setState(() => _busy = true);
    try {
      final sent = await widget.repository.sendQuote(current.quoteId);
      if (!mounted) return;
      setState(() {
        _quote = sent;
        _busy = false;
        _review = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'invalid_quote'
            ? kCompanyCustomerQuoteEmailRequired.of(_lang)
            : kCompanyCustomersSaveFailed.of(_lang);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      key: kCompanyCustomerQuotePageKey,
      appBar: AppBar(title: Text(kCompanyCustomerQuoteTitle.of(_lang))),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottom),
          children: [
            Text('${kCompanyCustomerQuoteIssuer.of(_lang)}: $_issuer'),
            if (_quote != null) Text(_quote!.state),
            if (_quote?.isAccepted == true)
              Text(kCompanyCustomerQuoteAccepted.of(_lang)),
            if (_quote?.state == 'sent' || _quote?.state == 'viewed')
              Text(kCompanyCustomerQuoteSent.of(_lang)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: kCompanyCustomersDisplayName.of(_lang),
              ),
            ),
            TextFormField(
              key: kCompanyCustomerQuoteEmailKey,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: kCompanyCustomersEmail.of(_lang),
                helperText: kCompanyCustomerQuoteEmailRequired.of(_lang),
              ),
            ),
            TextFormField(
              controller: _pickup,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuotePickup.of(_lang),
              ),
            ),
            TextFormField(
              controller: _dropoff,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteDropoff.of(_lang),
              ),
            ),
            TextFormField(
              controller: _startAt,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteStart.of(_lang),
              ),
            ),
            TextFormField(
              controller: _passengers,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuotePassengers.of(_lang),
              ),
            ),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteDescription.of(_lang),
              ),
            ),
            TextFormField(
              key: kCompanyCustomerQuotePriceKey,
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuotePrice.of(_lang),
                helperText: formatQuoteEuros(parseEuroToCents(_price.text)),
              ),
            ),
            TextFormField(
              controller: _validUntil,
              decoration: InputDecoration(
                labelText: kCompanyCustomerQuoteValidUntil.of(_lang),
              ),
            ),
            if (_review) ...[
              const SizedBox(height: 16),
              Text(kCompanyCustomerQuoteReview.of(_lang)),
              Text('${_pickup.text} → ${_dropoff.text}'),
              Text(formatQuoteEuros(parseEuroToCents(_price.text))),
              Text(_issuer),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: kCompanyCustomerQuoteSaveKey,
                  onPressed: _busy ? null : _saveDraft,
                  child: Text(kCompanyCustomerQuoteSaveDraft.of(_lang)),
                ),
                OutlinedButton(
                  key: kCompanyCustomerQuoteReviewKey,
                  onPressed: _busy ? null : () => setState(() => _review = true),
                  child: Text(kCompanyCustomerQuoteReview.of(_lang)),
                ),
                FilledButton.tonal(
                  key: kCompanyCustomerQuoteSendKey,
                  onPressed: _busy ? null : _send,
                  child: Text(kCompanyCustomerQuoteSend.of(_lang)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
