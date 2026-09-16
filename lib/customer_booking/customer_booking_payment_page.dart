import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/payment/booking_payment_method_tile.dart';
import 'package:fluxidi_tracking/payment/booking_payment_options.dart';
import 'package:fluxidi_tracking/payment/payment_booking_selection.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

Future<BookingPaymentSelection?> openCustomerBookingPaymentOptions(
  BuildContext context, {
  required AppLanguage language,
  required CustomerThemePalette palette,
  required BookingPaymentCapability capability,
  String countryCode = 'BE',
  String? quoteSummary,
  String? billingWarning,
  bool loadFailed = false,
}) {
  return Navigator.of(context).push<BookingPaymentSelection>(
    MaterialPageRoute<BookingPaymentSelection>(
      builder: (_) => CustomerBookingPaymentOptionsPage(
        language: language,
        palette: palette,
        capability: capability,
        countryCode: countryCode,
        quoteSummary: quoteSummary,
        billingWarning: billingWarning,
        loadFailed: loadFailed,
      ),
    ),
  );
}

class CustomerBookingPaymentOptionsPage extends StatefulWidget {
  const CustomerBookingPaymentOptionsPage({
    super.key,
    required this.language,
    required this.palette,
    required this.capability,
    this.countryCode = 'BE',
    this.quoteSummary,
    this.billingWarning,
    this.loadFailed = false,
  });

  final AppLanguage language;
  final CustomerThemePalette palette;
  final BookingPaymentCapability capability;
  final String countryCode;
  final String? quoteSummary;
  final String? billingWarning;

  /// The company profile request failed, so nothing is known about payments.
  final bool loadFailed;

  @override
  State<CustomerBookingPaymentOptionsPage> createState() =>
      _CustomerBookingPaymentOptionsPageState();
}

class _CustomerBookingPaymentOptionsPageState
    extends State<CustomerBookingPaymentOptionsPage> {
  late String _selectedId;

  AppLanguage get _language => widget.language;

  String _t(LocalizedText text) => text.of(_language);

  String _copy({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
      case AppLanguage.de:
        return nl;
    }
  }

  BookingPaymentOptions get _options {
    return BookingPaymentOptions(
      capability: widget.capability,
      countryCode: paymentMarketCountryCode(widget.countryCode),
      languageCode: _language.name,
      isApplePlatform:
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS,
    );
  }

  List<String> get _methodIds {
    final ids = _options.visibleMethodIds;
    if (ids.isNotEmpty) return ids;
    return const <String>[PaymentMethodIds.inVehicleCard];
  }

  /// Why the list is shorter than the customer expects. A failed request and a
  /// company that published nothing are different problems and must not both
  /// silently collapse to "only pay in the vehicle".
  String? get _unavailabilityReason {
    if (widget.loadFailed ||
        widget.capability.projectionStatus ==
            BookingPaymentCapabilityStatus.loadFailed) {
      return _copy(
        nl: 'De betaalinstellingen van dit bedrijf konden niet worden geladen. '
            'Probeer het opnieuw.',
        en: 'This company’s payment settings could not be loaded. Try again.',
        fr: 'Les réglages de paiement de cette société n’ont pas pu être '
            'chargés. Réessayez.',
        es: 'No se pudieron cargar los ajustes de pago de esta empresa. '
            'Inténtalo de nuevo.',
      );
    }
    if (!widget.capability.capabilityProjectionPresent) {
      return _copy(
        nl: 'De online betaalinformatie van dit bedrijf is hier niet '
            'beschikbaar. Alleen de hieronder getoonde methoden zijn mogelijk.',
        en: 'Online payment information for this company is not available here. '
            'Only the methods shown below are possible.',
        fr: 'Les informations de paiement en ligne de cette société ne sont '
            'pas disponibles ici. Seules les méthodes ci-dessous sont possibles.',
        es: 'La información de pago en línea de esta empresa no está '
            'disponible aquí. Solo son posibles los métodos que se muestran.',
      );
    }
    return _options.onlinePaymentsBlockedMessage;
  }

  @override
  void initState() {
    super.initState();
    final ids = _methodIds;
    _selectedId = ids.contains(PaymentMethodIds.inVehicleCard)
        ? PaymentMethodIds.inVehicleCard
        : ids.first;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = BookingPaymentTileStyle(
      animationDuration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      selectedBackground: palette.surface,
      unselectedBackground: palette.background,
      selectedBorderColor: palette.gold,
      unselectedBorderColor: palette.border,
      accentColor: palette.gold,
      labelColor: palette.textPrimary,
      mutedColor: palette.textMuted,
      descriptionColor: palette.textMuted,
      unselectedLogoColor: palette.textPrimary,
    );
    return Scaffold(
      key: kCustomerBookingPaymentPageKey,
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(_t(kCustomerBookingPaymentTitle)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    _t(kCustomerBookingPaymentHint),
                    style: TextStyle(color: palette.textMuted),
                  ),
                  if ((widget.quoteSummary ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.quoteSummary!.trim(),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if ((widget.billingWarning ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.billingWarning!,
                      style: TextStyle(color: palette.danger),
                    ),
                  ],
                  if (_unavailabilityReason != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _unavailabilityReason!,
                      key: kCustomerBookingPaymentUnavailableKey,
                      style: TextStyle(color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: 16),
                  for (final methodId in _methodIds) ...[
                    BookingPaymentMethodTile(
                      key: customerBookingPaymentMethodKey(methodId),
                      methodId: methodId,
                      label: paymentMethodDisplayLabel(methodId, _copy),
                      description: paymentMethodShortDescription(
                        methodId,
                        _copy,
                        qrPaymentConfigured: _options.qrPaymentConfigured,
                        qrDetailsUnknown: _options.qrPaymentDetailsUnknown,
                      ),
                      selected: _selectedId == methodId,
                      displayOnly: _options.isDisplayOnly(methodId),
                      style: style,
                      onSelect: _options.isDisplayOnly(methodId)
                          ? null
                          : () => setState(() => _selectedId = methodId),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  key: kCustomerBookingPaymentConfirmKey,
                  onPressed: _options.isDisplayOnly(_selectedId)
                      ? null
                      : () {
                          Navigator.of(context).pop(
                            BookingPaymentSelection.fromMethodId(_selectedId),
                          );
                        },
                  child: Text(_t(kCustomerBookingPaymentConfirm)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
