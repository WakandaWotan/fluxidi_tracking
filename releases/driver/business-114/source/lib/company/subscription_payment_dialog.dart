import 'dart:async';
import 'package:flutter/material.dart';
import '../company_session_store.dart';
import 'subscription_payment_confirmation.dart';

/// Retires permanently on logout, account switch or token replacement, including
/// logout/relogin to the same company while a dialog/network request is pending.
class SubscriptionPaymentOwner extends ChangeNotifier {
  SubscriptionPaymentOwner(this.companyId) {
    _token = activeCompanySessionNotifier.value?.companySessionToken ?? '';
    activeCompanySessionNotifier.addListener(_check);
    _check();
  }
  final String companyId;
  late final String _token;
  bool _retired = false;
  bool _disposed = false;
  bool get isCurrent {
    if (_retired || _disposed || _token.trim().isEmpty) return false;
    final current = activeCompanySessionNotifier.value;
    final expiry = current?.sessionExpiresAtUtc;
    return current?.companyId == companyId &&
        current?.companySessionToken == _token &&
        expiry != null &&
        DateTime.now().toUtc().isBefore(expiry);
  }

  void _check() {
    if (!isCurrent && !_retired) {
      _retired = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    activeCompanySessionNotifier.removeListener(_check);
    super.dispose();
  }
}

String subscriptionPaymentText(String language, String key) {
  const translations = {
    'title': [
      'Betaling bevestigen',
      'Confirm payment',
      'Confirmer le paiement',
      'Confirmar pago',
    ],
    'net': ['Excl. btw', 'Excl. VAT', 'Hors TVA', 'Sin IVA'],
    'vat': ['Btw', 'VAT', 'TVA', 'IVA'],
    'total': [
      'Te betalen totaal',
      'Amount due',
      'Total à payer',
      'Total a pagar',
    ],
    'taxable': ['Btw berekend', 'VAT applied', 'TVA appliquée', 'IVA aplicado'],
    'reverse': [
      'Btw verlegd',
      'Reverse charge',
      'Autoliquidation',
      'Inversión del sujeto pasivo',
    ],
    'zero': [
      'Gecontroleerd nultarief',
      'Reviewed zero rate',
      'Taux zéro vérifié',
      'Tipo cero verificado',
    ],
    'cancel': ['Annuleren', 'Cancel', 'Annuler', 'Cancelar'],
    'pay': [
      'Doorgaan naar betaling',
      'Continue to payment',
      'Continuer vers le paiement',
      'Continuar al pago',
    ],
    'pending': [
      'Er staat al een betaling in behandeling. Die wordt eerst gecontroleerd; er wordt geen tweede betaling gestart. Neem contact op met Fluxidi als dit blijft staan.',
      'A payment is already being processed. It must be checked first; no second payment will be started. Contact Fluxidi if this persists.',
      'Un paiement est déjà en cours. Il doit être vérifié avant tout nouveau paiement. Contactez Fluxidi si cela persiste.',
      'Ya hay un pago en curso. Debe comprobarse antes de iniciar otro pago. Contacta con Fluxidi si el mensaje persiste.',
    ],
    'blocked': [
      'Het betaalbedrag en de btw zijn nog niet bevestigd. Vernieuw de gegevens of neem contact op met Fluxidi.',
      'The payment amount and VAT are not confirmed yet. Refresh the details or contact Fluxidi.',
      'Le montant et la TVA ne sont pas encore confirmés. Actualisez les données ou contactez Fluxidi.',
      'El importe y el IVA aún no están confirmados. Actualiza los datos o contacta con Fluxidi.',
    ],
  };
  final index = const ['nl', 'en', 'fr', 'es'].indexOf(language);
  return translations[key]![index < 0 ? 0 : index];
}

Future<bool> confirmSubscriptionPayment({
  required BuildContext context,
  required SubscriptionPaymentConfirmation? confirmation,
  required SubscriptionPaymentOwner owner,
  required String productCode,
  required String languageCode,
  required bool Function() stillMounted,
}) async {
  bool valid() =>
      stillMounted() &&
      owner.isCurrent &&
      confirmation?.validFor(
            companyId: owner.companyId,
            productCode: productCode,
          ) ==
          true;
  if (!valid()) {
    if (stillMounted() && owner.isCurrent)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(subscriptionPaymentText(languageCode, 'blocked')),
        ),
      );
    return false;
  }
  final accepted = await showDialog<bool>(
    context: context,
    builder: (_) => _PaymentDialog(
      confirmation: confirmation!,
      owner: owner,
      language: languageCode,
      valid: valid,
    ),
  );
  return accepted == true && valid();
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.confirmation,
    required this.owner,
    required this.language,
    required this.valid,
  });
  final SubscriptionPaymentConfirmation confirmation;
  final SubscriptionPaymentOwner owner;
  final String language;
  final bool Function() valid;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  Timer? _timer;
  bool _closed = false;
  @override
  void initState() {
    super.initState();
    widget.owner.addListener(_check);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  void _close(bool result) {
    if (!mounted || _closed) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop(result);
    } else {
      navigator.removeRoute(route, result);
    }
  }

  void _check() {
    if (!widget.valid()) _close(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.owner.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.confirmation;
    String t(String key) => subscriptionPaymentText(widget.language, key);
    String money(int cents) =>
        '${amount.currency} ${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
    return AlertDialog(
      title: Text(t('title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t('net')}: ${money(amount.netCents)}',
              key: const Key('payment-net'),
            ),
            const SizedBox(height: 8),
            Text(
              '${t('vat')}: ${money(amount.vatCents)}',
              key: const Key('payment-vat'),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                amount.treatment == 'eu_b2b_reverse_charge'
                    ? 'reverse'
                    : amount.treatment == 'reviewed_zero_rate'
                    ? 'zero'
                    : 'taxable',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${t('total')}: ${money(amount.grossCents)}',
              key: const Key('payment-gross'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(false), child: Text(t('cancel'))),
        FilledButton(
          key: const Key('payment-accept'),
          onPressed: () => _close(widget.valid()),
          child: Text(t('pay')),
        ),
      ],
    );
  }
}
