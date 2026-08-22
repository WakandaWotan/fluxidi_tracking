/// The buyer billing identity form, and the wording that goes on it.
///
/// Taxi, airport and limousine ask the customer for the same nine billing
/// fields behind the same "I need a company invoice" choice, so the fields and
/// their labels live here instead of being restated per surface. What stays
/// with each surface is its theme and its own language resolution, because
/// those already differ between them.
///
/// This widget is presentation only. It never fetches a quote or a company
/// profile, never reads a payment capability, never calls `POST /book`, and
/// never decides the seller or the price. What the customer typed becomes a
/// [BookingBillingIdentity]; `booking_billing_identity.dart` turns that into
/// the canonical `billing_customer` fragment.
library;

import 'package:flutter/material.dart';

import 'booking_billing_identity.dart';

/// Picks the caller's translation of one string.
///
/// Surfaces differ in how they treat languages they have no copy for, so each
/// one passes its own existing helper rather than inheriting a fallback.
typedef BookingBillingCopyResolver =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

/// Customer-facing label of one billing field, in the wording taxi and airport
/// already use.
String bookingBillingFieldLabel(
  BookingBillingFormField field,
  BookingBillingCopyResolver t,
) {
  switch (field) {
    case BookingBillingFormField.legalName:
      return t(
        nl: 'Bedrijfsnaam',
        en: 'Company name',
        fr: 'Nom de l’entreprise',
        es: 'Nombre de la empresa',
      );
    case BookingBillingFormField.vatNumber:
      return t(
        nl: 'Btw-nummer',
        en: 'VAT number',
        fr: 'Numéro de TVA',
        es: 'Número de IVA',
      );
    case BookingBillingFormField.registrationNumber:
      return t(
        nl: 'Ondernemingsnummer / KBO',
        en: 'Company registration number',
        fr: 'Numéro d’entreprise',
        es: 'Número de registro de empresa',
      );
    case BookingBillingFormField.street:
      return t(
        nl: 'Straat en nummer',
        en: 'Street and number',
        fr: 'Rue et numéro',
        es: 'Calle y número',
      );
    case BookingBillingFormField.postalCode:
      return t(
        nl: 'Postcode',
        en: 'Postal code',
        fr: 'Code postal',
        es: 'Código postal',
      );
    case BookingBillingFormField.city:
      return t(nl: 'Gemeente', en: 'City', fr: 'Ville', es: 'Ciudad');
    case BookingBillingFormField.country:
      return t(
        nl: 'Land (bv. BE)',
        en: 'Country (e.g. BE)',
        fr: 'Pays (ex. BE)',
        es: 'País (p. ej. BE)',
      );
    case BookingBillingFormField.contactEmail:
      return t(
        nl: 'Factuur e-mail',
        en: 'Invoice email',
        fr: 'E-mail de facturation',
        es: 'Correo de factura',
      );
    case BookingBillingFormField.peppolEndpointId:
      return t(
        nl: 'Peppol endpoint-ID (optioneel)',
        en: 'Peppol endpoint ID (optional)',
        fr: 'ID de point d’accès Peppol (optionnel)',
        es: 'ID de endpoint Peppol (opcional)',
      );
    case BookingBillingFormField.peppolScheme:
      return t(
        nl: 'Peppol scheme (optioneel)',
        en: 'Peppol scheme (optional)',
        fr: 'Schéma Peppol (optionnel)',
        es: 'Esquema Peppol (opcional)',
      );
  }
}

/// The fields the form renders.
enum BookingBillingFormField {
  legalName,
  vatNumber,
  registrationNumber,
  street,
  postalCode,
  city,
  country,
  contactEmail,
  peppolEndpointId,
  peppolScheme,
}

/// What the customer still has to supply before a business invoice can be
/// issued, phrased for the customer rather than as a Worker error code.
String bookingBillingIdentityMissingFieldMessage(
  BookingBillingIdentityField field,
  BookingBillingCopyResolver t,
) {
  switch (field) {
    case BookingBillingIdentityField.legalName:
      return t(
        nl: 'Vul de bedrijfsnaam in voor de factuur.',
        en: 'Enter the company name for the invoice.',
        fr: 'Indiquez le nom de l’entreprise pour la facture.',
        es: 'Introduce el nombre de la empresa para la factura.',
      );
    case BookingBillingIdentityField.legalIdentityNumber:
      return t(
        nl: 'Vul een btw-nummer of ondernemingsnummer in.',
        en: 'Enter a VAT number or company registration number.',
        fr: 'Indiquez un numéro de TVA ou d’entreprise.',
        es: 'Introduce un número de IVA o de registro de empresa.',
      );
    case BookingBillingIdentityField.address:
      return t(
        nl: 'Vul het volledige factuuradres in: straat, postcode, gemeente en land.',
        en: 'Enter the full billing address: street, postal code, city and country.',
        fr: 'Indiquez l’adresse de facturation complète : rue, code postal, ville et pays.',
        es: 'Introduce la dirección de facturación completa: calle, código postal, ciudad y país.',
      );
  }
}

/// The nine text controllers the form binds to, plus the invoice email.
///
/// Owned by the calling surface so prefill and disposal stay where they always
/// were.
class BookingBillingIdentityControllers {
  BookingBillingIdentityControllers();

  final TextEditingController legalName = TextEditingController();
  final TextEditingController vatNumber = TextEditingController();
  final TextEditingController registrationNumber = TextEditingController();
  final TextEditingController street = TextEditingController();
  final TextEditingController postalCode = TextEditingController();
  final TextEditingController city = TextEditingController();
  final TextEditingController country = TextEditingController();
  final TextEditingController contactEmail = TextEditingController();
  final TextEditingController peppolEndpointId = TextEditingController();
  final TextEditingController peppolScheme = TextEditingController();

  BookingBillingIdentity get identity => BookingBillingIdentity(
    legalName: legalName.text,
    vatNumber: vatNumber.text,
    registrationNumber: registrationNumber.text,
    street: street.text,
    postalCode: postalCode.text,
    city: city.text,
    country: country.text,
    contactEmail: contactEmail.text,
    peppolEndpointId: peppolEndpointId.text,
    peppolScheme: peppolScheme.text,
  );

  TextEditingController controllerFor(BookingBillingFormField field) {
    switch (field) {
      case BookingBillingFormField.legalName:
        return legalName;
      case BookingBillingFormField.vatNumber:
        return vatNumber;
      case BookingBillingFormField.registrationNumber:
        return registrationNumber;
      case BookingBillingFormField.street:
        return street;
      case BookingBillingFormField.postalCode:
        return postalCode;
      case BookingBillingFormField.city:
        return city;
      case BookingBillingFormField.country:
        return country;
      case BookingBillingFormField.contactEmail:
        return contactEmail;
      case BookingBillingFormField.peppolEndpointId:
        return peppolEndpointId;
      case BookingBillingFormField.peppolScheme:
        return peppolScheme;
    }
  }

  void dispose() {
    legalName.dispose();
    vatNumber.dispose();
    registrationNumber.dispose();
    street.dispose();
    postalCode.dispose();
    city.dispose();
    country.dispose();
    contactEmail.dispose();
    peppolEndpointId.dispose();
    peppolScheme.dispose();
  }
}

/// Theme values one surface uses to draw its billing form.
class BookingBillingFormStyle {
  const BookingBillingFormStyle({
    required this.accentColor,
    required this.labelColor,
    required this.mutedColor,
    required this.fieldBackground,
    required this.fieldBorderColor,
    required this.warningColor,
  });

  /// Colour of the toggle and of a focused field.
  final Color accentColor;

  final Color labelColor;
  final Color mutedColor;
  final Color fieldBackground;
  final Color fieldBorderColor;

  /// Colour of the incomplete-identity message.
  final Color warningColor;
}

const ValueKey<String> kBookingBillingToggleKey = ValueKey<String>(
  'booking_billing_identity_toggle',
);

ValueKey<String> bookingBillingFieldKey(BookingBillingFormField field) =>
    ValueKey<String>('booking_billing_identity_field_${field.name}');

const ValueKey<String> kBookingBillingWarningKey = ValueKey<String>(
  'booking_billing_identity_warning',
);

/// The "I need a company invoice" choice and, once it is on, the buyer fields.
class BookingBillingIdentityForm extends StatefulWidget {
  const BookingBillingIdentityForm({
    super.key,
    required this.enabled,
    required this.controllers,
    required this.style,
    required this.t,
    required this.onEnabledChanged,
    this.onChanged,
    this.warning,
    this.showPeppolFields = true,
  });

  /// Whether the customer asked for a company invoice.
  final bool enabled;

  final BookingBillingIdentityControllers controllers;
  final BookingBillingFormStyle style;
  final BookingBillingCopyResolver t;

  /// Null while the surface is busy, which disables the choice and the fields.
  final ValueChanged<bool>? onEnabledChanged;

  /// Called after any field edit so the surface can re-evaluate completeness.
  final VoidCallback? onChanged;

  /// Shown under the fields when the identity is still incomplete.
  final String? warning;

  final bool showPeppolFields;

  @override
  State<BookingBillingIdentityForm> createState() =>
      _BookingBillingIdentityFormState();
}

class _BookingBillingIdentityFormState
    extends State<BookingBillingIdentityForm> {
  bool _peppolExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final style = widget.style;
    final interactive = widget.onEnabledChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile.adaptive(
          key: kBookingBillingToggleKey,
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: widget.enabled,
          onChanged: widget.onEnabledChanged,
          activeColor: style.accentColor,
          title: Text(
            t(
              nl: 'Ik heb een bedrijfsfactuur nodig',
              en: 'I need a company invoice',
              fr: 'J’ai besoin d’une facture d’entreprise',
              es: 'Necesito una factura de empresa',
            ),
            style: TextStyle(
              color: style.labelColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        if (widget.enabled) ...<Widget>[
          const SizedBox(height: 4),
          _field(BookingBillingFormField.legalName, Icons.business_outlined),
          const SizedBox(height: 8),
          _field(
            BookingBillingFormField.vatNumber,
            Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 8),
          _field(
            BookingBillingFormField.registrationNumber,
            Icons.badge_outlined,
          ),
          const SizedBox(height: 8),
          _field(BookingBillingFormField.street, Icons.location_on_outlined),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _field(
                  BookingBillingFormField.postalCode,
                  Icons.markunread_mailbox_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  BookingBillingFormField.city,
                  Icons.location_city_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _field(BookingBillingFormField.country, Icons.public_outlined),
          const SizedBox(height: 8),
          _field(
            BookingBillingFormField.contactEmail,
            Icons.alternate_email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          if (widget.showPeppolFields) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: interactive
                    ? () => setState(() => _peppolExpanded = !_peppolExpanded)
                    : null,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: style.accentColor,
                ),
                child: Text(
                  _peppolExpanded
                      ? t(
                          nl: 'Peppol-gegevens verbergen',
                          en: 'Hide Peppol details',
                          fr: 'Masquer les données Peppol',
                          es: 'Ocultar datos Peppol',
                        )
                      : t(
                          nl: 'Peppol-gegevens toevoegen',
                          en: 'Add Peppol details',
                          fr: 'Ajouter des données Peppol',
                          es: 'Añadir datos Peppol',
                        ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_peppolExpanded) ...<Widget>[
              _field(
                BookingBillingFormField.peppolEndpointId,
                Icons.hub_outlined,
              ),
              const SizedBox(height: 8),
              _field(BookingBillingFormField.peppolScheme, Icons.tag_outlined),
            ],
          ],
          if ((widget.warning ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              widget.warning!,
              key: kBookingBillingWarningKey,
              style: TextStyle(
                color: style.warningColor,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _field(
    BookingBillingFormField field,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    final style = widget.style;
    final enabled = widget.onEnabledChanged != null;
    return TextField(
      key: bookingBillingFieldKey(field),
      controller: widget.controllers.controllerFor(field),
      enabled: enabled,
      keyboardType: keyboardType,
      onChanged: (_) => widget.onChanged?.call(),
      style: TextStyle(color: style.labelColor, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: style.fieldBackground,
        labelText: bookingBillingFieldLabel(field, widget.t),
        labelStyle: TextStyle(color: style.mutedColor, fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: style.mutedColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.fieldBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.accentColor),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.fieldBorderColor),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.fieldBorderColor),
        ),
      ),
    );
  }
}
