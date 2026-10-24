import 'package:flutter/material.dart';

import 'customer_app_header_branding.dart';
import 'customer_app_header_mode.dart';
import 'customer_app_header_preview.dart';
import 'customer_app_header_settings_api.dart';

/// Self-contained “Weergave in eigen klantenapp” block.
///
/// MERGE: insert after the existing public media preview in
/// `lib/business_settings_page.dart`. Do not paste this into a file the
/// tariffs agent is currently editing. This widget saves only the header
/// mode and never publishes the partner profile.
class CustomerAppHeaderSettingsSection extends StatefulWidget {
  const CustomerAppHeaderSettingsSection({
    super.key,
    required this.logoUrl,
    required this.coverUrl,
    required this.companyName,
    required this.gold,
    required this.surface,
    required this.background,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.panelBg,
    required this.t,
    this.tenantId,
    this.companyId,
    this.initialMode,
    this.initialLogoPosition,
    this.initialUseOnDriverApp,
    this.initialUseOnBusinessApp,
    this.load,
    this.save,
    this.onSaved,
  });

  final String logoUrl;
  final String coverUrl;
  final String companyName;
  final Color gold;
  final Color surface;
  final Color background;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color panelBg;
  final String Function({
    required String nl,
    required String en,
    String? fr,
    String? es,
  })
  t;
  final String? tenantId;
  final String? companyId;
  final CustomerAppHeaderMode? initialMode;
  final CustomerAppHeaderLogoPosition? initialLogoPosition;
  final Future<CustomerAppHeaderBranding> Function()? load;
  final bool? initialUseOnDriverApp;
  final bool? initialUseOnBusinessApp;
  final Future<CustomerAppHeaderBranding> Function({
    required CustomerAppHeaderMode mode,
    required CustomerAppHeaderLogoPosition logoPosition,
    bool? useOnDriverApp,
    bool? useOnBusinessApp,
  })?
  save;
  final ValueChanged<CustomerAppHeaderBranding>? onSaved;

  @override
  State<CustomerAppHeaderSettingsSection> createState() =>
      CustomerAppHeaderSettingsSectionState();
}

class CustomerAppHeaderSettingsSectionState
    extends State<CustomerAppHeaderSettingsSection> {
  CustomerAppHeaderMode _mode = CustomerAppHeaderMode.logoOnly;
  CustomerAppHeaderLogoPosition _logoPosition =
      CustomerAppHeaderLogoPosition.topLeft;
  bool _useOnDriverApp = false;
  bool _useOnBusinessApp = false;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? CustomerAppHeaderMode.logoOnly;
    _logoPosition =
        widget.initialLogoPosition ?? CustomerAppHeaderLogoPosition.topLeft;
    _useOnDriverApp = widget.initialUseOnDriverApp ?? false;
    _useOnBusinessApp = widget.initialUseOnBusinessApp ?? false;
    _reload();
  }

  CustomerAppHeaderBranding get _preview => CustomerAppHeaderBranding(
    mode: _mode,
    logoPosition: _logoPosition,
    logoUrl: widget.logoUrl,
    coverUrl: widget.coverUrl,
    companyName: widget.companyName,
    useOnDriverApp: _useOnDriverApp,
    useOnBusinessApp: _useOnBusinessApp,
  );

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded =
          await (widget.load ??
              () => fetchCustomerAppHeaderSettings(
                tenantId: widget.tenantId,
                companyId: widget.companyId,
              ))();
      if (!mounted) return;
      setState(() {
        _mode = loaded.mode;
        _logoPosition = loaded.logoPosition;
        _useOnDriverApp = loaded.useOnDriverApp;
        _useOnBusinessApp = loaded.useOnBusinessApp;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _mode = widget.initialMode ?? CustomerAppHeaderMode.logoOnly;
        _logoPosition =
            widget.initialLogoPosition ?? CustomerAppHeaderLogoPosition.topLeft;
      });
    }
  }

  /// Also used by the page-wide save button while this section is expanded.
  Future<bool> save() async {
    if (_saving || _loading) return false;
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      final saved =
          await (widget.save ??
              ({
                required mode,
                required logoPosition,
                bool? useOnDriverApp,
                bool? useOnBusinessApp,
              }) => saveCustomerAppHeaderSettings(
                mode: mode,
                logoPosition: logoPosition,
                useOnDriverApp: useOnDriverApp,
                useOnBusinessApp: useOnBusinessApp,
                tenantId: widget.tenantId,
                companyId: widget.companyId,
              ))(
            mode: _mode,
            logoPosition: _logoPosition,
            useOnDriverApp: _useOnDriverApp,
            useOnBusinessApp: _useOnBusinessApp,
          );
      if (!mounted) return false;
      widget.onSaved?.call(saved);
      setState(() {
        _mode = saved.mode;
        _logoPosition = saved.logoPosition;
        _useOnDriverApp = saved.useOnDriverApp;
        _useOnBusinessApp = saved.useOnBusinessApp;
        _saving = false;
        _status = widget.t(
          nl: 'Weergave opgeslagen. Het publieke partnerprofiel is niet gewijzigd.',
          en: 'Display saved. The public partner profile was not changed.',
          fr: 'Affichage enregistré. Le profil partenaire public n’a pas été modifié.',
          es: 'Visualización guardada. El perfil público no cambió.',
        );
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('customer_app_header_settings_section'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.t(
                nl: 'Header van je eigen klantenapp',
                en: 'Header of your own customer app',
                fr: 'En-tête de votre application client',
                es: 'Cabecera de tu app de clientes',
              ),
              style: TextStyle(color: widget.gold, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              widget.t(
                nl: 'Bepaalt de bovenkant van je eigen klantenapp.',
                en: 'Sets the top of your own customer app.',
                fr: 'Définit le haut de votre application client.',
                es: 'Define la parte superior de tu app de clientes.',
              ),
              style: TextStyle(color: widget.textSecondary, fontSize: 12.3),
            ),
            const SizedBox(height: 8),
            for (final option in CustomerAppHeaderMode.values)
              RadioListTile<CustomerAppHeaderMode>(
                key: Key('customer_app_header_mode_${option.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: option,
                groupValue: _mode,
                activeColor: widget.gold,
                onChanged: _saving || _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _mode = value);
                      },
                title: Text(
                  _label(option),
                  style: TextStyle(
                    color: widget.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _subtitle(option),
                  style: TextStyle(color: widget.textSecondary, fontSize: 12),
                ),
              ),
            if (_mode == CustomerAppHeaderMode.coverAndLogo) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                widget.t(
                  nl: 'Logopositie',
                  en: 'Logo position',
                  fr: 'Position du logo',
                  es: 'Posición del logo',
                ),
                style: TextStyle(
                  color: widget.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              RadioListTile<CustomerAppHeaderLogoPosition>(
                key: const Key('customer_app_header_logo_pos_topLeft'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: CustomerAppHeaderLogoPosition.topLeft,
                groupValue: _logoPosition,
                activeColor: widget.gold,
                onChanged: _saving || _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _logoPosition = value);
                      },
                title: Text(
                  widget.t(
                    nl: 'Linksonder (standaard)',
                    en: 'Bottom left (default)',
                    fr: 'En bas à gauche (défaut)',
                    es: 'Abajo a la izquierda (predeterminado)',
                  ),
                  style: TextStyle(color: widget.textPrimary),
                ),
              ),
              RadioListTile<CustomerAppHeaderLogoPosition>(
                key: const Key('customer_app_header_logo_pos_topRight'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: CustomerAppHeaderLogoPosition.topRight,
                groupValue: _logoPosition,
                activeColor: widget.gold,
                onChanged: _saving || _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _logoPosition = value);
                      },
                title: Text(
                  widget.t(
                    nl: 'Rechtsonder',
                    en: 'Bottom right',
                    fr: 'En bas à droite',
                    es: 'Abajo a la derecha',
                  ),
                  style: TextStyle(color: widget.textPrimary),
                ),
              ),
            ],
            SwitchListTile(
              key: const Key('driver_app_use_company_header'),
              contentPadding: EdgeInsets.zero,
              value: _useOnDriverApp,
              activeColor: widget.gold,
              onChanged: _saving || _loading
                  ? null
                  : (value) => setState(() => _useOnDriverApp = value),
              title: Text(
                widget.t(
                  nl: 'Ook gebruiken in de chauffeurapp',
                  en: 'Also use in the driver app',
                  fr: 'Utiliser aussi dans l’app chauffeur',
                  es: 'Usar también en la app del conductor',
                ),
                style: TextStyle(
                  color: widget.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                widget.t(
                  nl: 'Zelfde header voor alle gekoppelde chauffeurs. Uit laat hun eigen header staan.',
                  en: 'Same header for every linked driver. Off keeps their own header.',
                  fr: 'Même en-tête pour les chauffeurs liés. Désactivé conserve leur en-tête.',
                  es: 'La misma cabecera para los conductores vinculados. Apagado conserva la suya.',
                ),
                style: TextStyle(color: widget.textSecondary, fontSize: 12),
              ),
            ),
            SwitchListTile(
              key: const Key('business_app_use_company_header'),
              contentPadding: EdgeInsets.zero,
              value: _useOnBusinessApp,
              activeColor: widget.gold,
              onChanged: _saving || _loading
                  ? null
                  : (value) => setState(() => _useOnBusinessApp = value),
              title: Text(
                widget.t(
                  nl: 'Ook gebruiken op de bedrijfspagina',
                  en: 'Also use on the business home',
                  fr: 'Utiliser aussi sur la page entreprise',
                  es: 'Usar también en la página de empresa',
                ),
                style: TextStyle(
                  color: widget.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                widget.t(
                  nl: 'Toon dezelfde cover en hetzelfde logo boven je bedrijfsoverzicht.',
                  en: 'Show the same cover and logo above your business overview.',
                  fr: 'Afficher la même couverture et le même logo sur votre tableau de bord.',
                  es: 'Mostrar la misma portada y el mismo logo en el panel de empresa.',
                ),
                style: TextStyle(color: widget.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            CustomerAppHeaderDevicePreviews(
              branding: _preview,
              gold: widget.gold,
              surface: widget.surface,
              background: widget.background,
              textPrimary: widget.textPrimary,
              border: widget.border,
              phoneLabel: widget.t(
                nl: 'Gsm',
                en: 'Phone',
                fr: 'Téléphone',
                es: 'Móvil',
              ),
              tabletLabel: widget.t(
                nl: 'Tablet',
                en: 'Tablet',
                fr: 'Tablette',
                es: 'Tableta',
              ),
            ),
            if (_loading) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_status != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_status!, style: TextStyle(color: widget.textSecondary)),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: widget.gold)),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('customer_app_header_save'),
              onPressed: _saving || _loading
                  ? null
                  : () async {
                      await save();
                    },
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                widget.t(
                  nl: 'Weergave opslaan',
                  en: 'Save display',
                  fr: 'Enregistrer l’affichage',
                  es: 'Guardar visualización',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(CustomerAppHeaderMode mode) {
    switch (mode) {
      case CustomerAppHeaderMode.logoOnly:
        return widget.t(
          nl: 'Alleen logo',
          en: 'Logo only',
          fr: 'Logo uniquement',
          es: 'Solo logo',
        );
      case CustomerAppHeaderMode.coverOnly:
        return widget.t(
          nl: 'Alleen headerafbeelding',
          en: 'Header image only',
          fr: 'Image d’en-tête uniquement',
          es: 'Solo imagen de cabecera',
        );
      case CustomerAppHeaderMode.coverAndLogo:
        return widget.t(
          nl: 'Header + logo',
          en: 'Header + logo',
          fr: 'En-tête + logo',
          es: 'Cabecera + logo',
        );
    }
  }

  String _subtitle(CustomerAppHeaderMode mode) {
    switch (mode) {
      case CustomerAppHeaderMode.logoOnly:
        return widget.t(
          nl: 'Groot logo, horizontaal gecentreerd bovenaan.',
          en: 'Large logo, horizontally centered at the top.',
          fr: 'Grand logo, centré horizontalement en haut.',
          es: 'Logo grande, centrado horizontalmente arriba.',
        );
      case CustomerAppHeaderMode.coverOnly:
        return widget.t(
          nl: 'Volledige bestaande cover in de goedgekeurde verhoudingen. Geen extra los logo.',
          en: 'Full existing cover in the approved proportions. No extra standalone logo.',
          fr: 'Couverture existante complète dans les proportions approuvées. Pas de logo séparé.',
          es: 'Portada existente completa en las proporciones aprobadas. Sin logo suelto.',
        );
      case CustomerAppHeaderMode.coverAndLogo:
        return widget.t(
          nl: 'De bestaande cover met een kleiner logo boven op de afbeelding.',
          en: 'The existing cover with a smaller logo on top of the image.',
          fr: 'La couverture existante avec un logo plus petit sur l’image.',
          es: 'La portada existente con un logo más pequeño sobre la imagen.',
        );
    }
  }
}
