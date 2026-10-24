import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_pdf_preview_page.dart';

class CompanyMonthlyInvoicePage extends StatefulWidget {
  const CompanyMonthlyInvoicePage({
    super.key,
    required this.customerId,
    required this.repository,
    required this.language,
  });
  final String customerId;
  final CompanyCustomersRepository repository;
  final AppLanguage language;
  @override
  State<CompanyMonthlyInvoicePage> createState() =>
      _CompanyMonthlyInvoicePageState();
}

class _CompanyMonthlyInvoicePageState extends State<CompanyMonthlyInvoicePage> {
  late final Map<String, String> _scope;
  late final TextEditingController _month;
  Map<String, dynamic>? _data;
  final List<Map> _history = [];
  String? _historyCursor;
  bool _historyLoaded = false;
  bool _busy = false;
  String? _error;
  String _text(String nl, String en, String fr, String es) =>
      LocalizedText(nl: nl, en: en, fr: fr, es: es).of(widget.language);
  String _money(int cents, String currency) =>
      '${(cents / 100).toStringAsFixed(2)} $currency';
  String _errorText(String code) {
    if (code == 'invoice_scope_changed' || code == 'invoice_scope_mismatch') {
      return _text(
        'Het bedrijf is gewijzigd. Open het klantdossier opnieuw.',
        'The company changed. Reopen the customer record.',
        'L’entreprise a changé. Rouvrez la fiche client.',
        'La empresa cambió. Abra de nuevo la ficha del cliente.',
      );
    }
    if (code == 'invoice_sources_changed' ||
        code == 'monthly_invoice_preview_changed' ||
        code == 'monthly_invoice_batch_changed') {
      return _text(
        'De ritgegevens zijn gewijzigd. Bekijk de maand opnieuw vóór uitgifte.',
        'Ride details changed. Reload the month before issuing.',
        'Les trajets ont changé. Rechargez le mois avant émission.',
        'Los viajes cambiaron. Recargue el mes antes de emitir.',
      );
    }
    if (code == 'invoice_email_delivery_needs_review' ||
        code == 'invoice_email_delivery_pending') {
      return _text(
        'De verzending is nog niet bevestigd. Controleer de verzendstatus vóór je opnieuw verstuurt.',
        'Sending is not confirmed yet. Check delivery before sending again.',
        'L’envoi n’est pas confirmé. Vérifiez son état avant de renvoyer.',
        'El envío no está confirmado. Compruebe su estado antes de reenviar.',
      );
    }
    if (code == 'invoice_buyer_snapshot_missing') {
      return _text(
        'Het vastgelegde factuuradres is onvolledig. Neem contact op met de beheerder.',
        'The saved billing address is incomplete. Contact the administrator.',
        'L’adresse de facturation enregistrée est incomplète. Contactez l’administrateur.',
        'La dirección guardada está incompleta. Contacte al administrador.',
      );
    }
    if (code == 'monthly_invoicing_disabled' ||
        code == 'monthly_invoice_email_disabled') {
      return _text(
        'Deze functie is nog niet ingeschakeld voor dit bedrijf.',
        'This feature is not enabled for this company yet.',
        'Cette fonction n’est pas encore activée pour cette entreprise.',
        'Esta función aún no está habilitada para esta empresa.',
      );
    }
    return _text(
      'De actie is niet voltooid. Bekijk de maand opnieuw en probeer het nog eens.',
      'The action was not completed. Reload the month and try again.',
      'L’action n’a pas abouti. Rechargez le mois et réessayez.',
      'La acción no se completó. Recargue el mes e inténtelo de nuevo.',
    );
  }

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.monthlyInvoiceScope;
    final last = DateTime(DateTime.now().year, DateTime.now().month - 1);
    _month = TextEditingController(
      text: '${last.year}-${last.month.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _month.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(
    String action, {
    Map<String, dynamic> body = const {},
  }) => widget.repository.monthlyInvoice(
    widget.customerId,
    action,
    month: _month.text.trim(),
    body: body,
    expectedScope: _scope,
  );
  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error is CompanyCustomerException
              ? error.code
              : 'transport_failed';
          if (_error == 'invoice_scope_changed' ||
              _error == 'invoice_scope_mismatch') {
            _data = null;
            _history.clear();
            _historyLoaded = false;
            _historyCursor = null;
          }
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
        });
    }
  }

  Future<void> _load() => _run(() async {
    Map<String, dynamic> result;
    try {
      result = await _request('detail');
    } on CompanyCustomerException catch (error) {
      if (error.code != 'monthly_invoice_not_issued') rethrow;
      result = await _request('preview');
    }
    if (mounted)
      setState(() {
        _data = result;
      });
  });
  Future<void> _loadHistory({bool next = false}) => _run(() async {
    final result = await _request(
      'list',
      body: {'cursor': next ? _historyCursor : ''},
    );
    if (!mounted) return;
    setState(() {
      if (!next) _history.clear();
      _history.addAll((result['items'] as List).cast<Map>());
      _historyCursor = result['next_cursor'] as String?;
      _historyLoaded = true;
    });
  });
  String _deliveryText(Map item) => item['state'] == 'preparing'
      ? _text(
          'Uitgifte nog niet voltooid',
          'Issuance not completed',
          'Émission non terminée',
          'Emisión incompleta',
        )
      : item['delivery_state'] == 'sent'
      ? _text('Verzonden', 'Sent', 'Envoyée', 'Enviada')
      : item['delivery_state'] == 'pending'
      ? _text(
          'Verzending nog niet bevestigd',
          'Sending not yet confirmed',
          'Envoi non confirmé',
          'Envío no confirmado',
        )
      : _text(
          'Nog niet verzonden',
          'Not sent yet',
          'Pas encore envoyée',
          'Aún no enviada',
        );
  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_text('Annuleren', 'Cancel', 'Annuler', 'Cancelar')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                _text('Bevestigen', 'Confirm', 'Confirmer', 'Confirmar'),
              ),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _issue() => _run(() async {
    if (!await _confirm(
      _text(
        'Deze maandfactuur definitief uitgeven? Dit verstuurt nog geen e-mail.',
        'Issue this invoice? No email is sent yet.',
        'Émettre cette facture ? Aucun e-mail ne sera envoyé.',
        '¿Emitir esta factura? Aún no se envía ningún correo.',
      ),
    ))
      return;
    final result = await _request(
      'issue',
      body: {'expected_content_hash': _data?['content_hash']},
    );
    if (mounted)
      setState(() {
        _data = result;
      });
  });
  Future<void> _pdf() => _run(() async {
    final result = await _request('prepare');
    final bytes = base64Decode(result['pdf_base64'] as String);
    if (mounted)
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FluxidiPdfPreviewPage(
            title: result['filename'] as String,
            bytes: bytes,
          ),
        ),
      );
  });
  Future<void> _resume() => _run(() async {
    final hash = _data?['document']?['monthly_content_hash'];
    for (var page = 0; page < 105; page++) {
      final result = await _request(
        'issue',
        body: {'expected_content_hash': hash},
      );
      if (!mounted) return;
      setState(() {
        _data = result;
      });
      if (result['projection_pending'] != true) return;
    }
    throw const CompanyCustomerException('invoice_projection_pending');
  });
  Future<void> _send() => _run(() async {
    if (!await _confirm(
      _text(
        'Maandfactuur versturen naar het vastgelegde e-mailadres van de klant?',
        'Send to the customer’s saved invoice email?',
        'Envoyer à l’adresse e-mail enregistrée du client ?',
        '¿Enviar al correo guardado del cliente?',
      ),
    ))
      return;
    await _request('send');
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Verzending bevestigd',
              'Sending confirmed',
              'Envoi confirmé',
              'Envío confirmado',
            ),
          ),
        ),
      );
  });
  @override
  Widget build(BuildContext context) {
    final document = _data?['document'] as Map?;
    final invoice =
        document?['immutable_snapshot']?['monthly_invoice'] ??
        _data?['invoice'];
    final lines = invoice?['lines'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _text(
            'Maandfacturen',
            'Monthly invoices',
            'Factures mensuelles',
            'Facturas mensuales',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _month,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: _text(
                'Maand (jaar-maand)',
                'Month (year-month)',
                'Mois (année-mois)',
                'Mes (año-mes)',
              ),
              hintText: '2026-09',
            ),
            onChanged: (_) => setState(() {
              _data = null;
              _error = null;
            }),
          ),
          FilledButton(
            onPressed: _busy ? null : _load,
            child: Text(
              _text('Maand bekijken', 'View month', 'Voir le mois', 'Ver mes'),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_errorText(_error!), key: const Key('monthly_invoice_error')),
          if (_data?['empty'] == true)
            Text(
              _text(
                'Geen factureerbare ritten voor deze maand.',
                'No billable rides for this month.',
                'Aucun trajet facturable ce mois-ci.',
                'No hay viajes facturables este mes.',
              ),
            ),
          OutlinedButton(
            onPressed: _busy ? null : () => _loadHistory(),
            child: Text(
              _text(
                'Factuurgeschiedenis',
                'Invoice history',
                'Historique des factures',
                'Historial de facturas',
              ),
            ),
          ),
          if (_historyLoaded && _history.isEmpty)
            Text(
              _text(
                'Nog geen maandfacturen.',
                'No monthly invoices yet.',
                'Aucune facture mensuelle.',
                'Aún no hay facturas mensuales.',
              ),
            ),
          for (final item in _history)
            ListTile(
              title: Text('${item['month']} ${item['document_number'] ?? ''}'),
              subtitle: Text(_deliveryText(item)),
              trailing: item['gross_cents'] is int
                  ? Text(
                      _money(
                        item['gross_cents'] as int,
                        item['currency'] as String,
                      ),
                    )
                  : null,
              onTap: _busy
                  ? null
                  : () {
                      setState(() {
                        _month.text = item['month'] as String;
                        _data = null;
                      });
                      _load();
                    },
            ),
          if (_historyCursor != null)
            TextButton(
              onPressed: _busy ? null : () => _loadHistory(next: true),
              child: Text(
                _text(
                  'Meer facturen',
                  'More invoices',
                  'Plus de factures',
                  'Más facturas',
                ),
              ),
            ),
          if (document != null)
            Text(document['document_number']?.toString() ?? ''),
          if (invoice != null) ...[
            Text(
              _money(
                invoice['totals']['gross_cents'] as int,
                invoice['currency'] as String,
              ),
            ),
            for (final line in lines)
              ListTile(
                title: Text(
                  line['from'] != null || line['to'] != null
                      ? '${line['from'] ?? ''} → ${line['to'] ?? ''}'
                      : '${line['booking_id']} ${line['leg_id'] ?? ''}',
                ),
                subtitle: Text(line['completed_at'].toString()),
                trailing: Text(
                  _money(
                    line['gross_cents'] as int,
                    line['currency'] as String,
                  ),
                ),
              ),
            if (document == null)
              FilledButton(
                onPressed: _busy ? null : _issue,
                child: Text(
                  _text(
                    'Factuur uitgeven',
                    'Issue invoice',
                    'Émettre la facture',
                    'Emitir factura',
                  ),
                ),
              ),
            if (document != null) ...[
              if (_data?['projection_pending'] == true)
                OutlinedButton(
                  onPressed: _busy ? null : _resume,
                  child: Text(
                    _text(
                      'Ritverwijzingen afwerken',
                      'Complete ride links',
                      'Finaliser les liens des trajets',
                      'Completar enlaces de viajes',
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: _busy ? null : _pdf,
                child: const Text('PDF'),
              ),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(
                  _text(
                    'Versturen naar klant',
                    'Send to customer',
                    'Envoyer au client',
                    'Enviar al cliente',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
