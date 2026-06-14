import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_orientation_flow_page.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const String _fluxidiSupportWhatsAppUrl = 'https://wa.me/32469788891';

const Map<AppLanguage, String> _brochureAssetByLanguage = <AppLanguage, String>{
  AppLanguage.nl:
      'assets/fluxidi/brochures/fluxidi_platform_brochure_nl_final.pdf',
  AppLanguage.en:
      'assets/fluxidi/brochures/fluxidi_platform_brochure_en_final.pdf',
  AppLanguage.fr:
      'assets/fluxidi/brochures/fluxidi_platform_brochure_fr_final.pdf',
  AppLanguage.es:
      'assets/fluxidi/brochures/fluxidi_platform_brochure_es_final.pdf',
};

const Map<AppLanguage, String>
_businessGuideAssetByLanguage = <AppLanguage, String>{
  AppLanguage.nl:
      'assets/fluxidi/manuals/fluxidi_bedrijfspagina_handleiding_nl_v1_0_final.pdf',
  AppLanguage.en:
      'assets/fluxidi/manuals/fluxidi_business_page_guide_en_v1_0_final.pdf',
  AppLanguage.fr:
      'assets/fluxidi/manuals/fluxidi_guide_page_entreprise_fr_v1_0_final.pdf',
  AppLanguage.es:
      'assets/fluxidi/manuals/fluxidi_guia_pagina_empresa_es_v1_0_final.pdf',
};

class BusinessHelpManualPage extends StatelessWidget {
  const BusinessHelpManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, themeVariant, _) {
        final palette = paletteForBusinessTheme(themeVariant);
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: appLanguageNotifier,
          builder: (context, language, _) {
            return Scaffold(
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.background,
                foregroundColor: palette.textPrimary,
                elevation: 0,
                title: Text(
                  _t(
                    language,
                    nl: 'Help & handleiding',
                    en: 'Help & guide',
                    fr: 'Aide & guide',
                    es: 'Ayuda y guía',
                  ),
                ),
              ),
              body: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 760;
                    final maxWidth = isWide ? 980.0 : double.infinity;
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 28 : 16,
                        8,
                        isWide ? 28 : 16,
                        28,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _HelpHeaderCard(
                                palette: palette,
                                language: language,
                              ),
                              const SizedBox(height: 16),
                              _QuickActionsGrid(
                                palette: palette,
                                language: language,
                              ),
                              const SizedBox(height: 18),
                              ..._helpSections.map(
                                (section) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _HelpExpansionCard(
                                    palette: palette,
                                    language: language,
                                    title: section.title,
                                    points: section.points,
                                    icon: section.icon,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _FaqBlock(palette: palette, language: language),
                              const SizedBox(height: 14),
                              _SupportCard(
                                palette: palette,
                                language: language,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HelpHeaderCard extends StatelessWidget {
  const _HelpHeaderCard({required this.palette, required this.language});

  final BusinessThemePalette palette;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _premiumDecoration(palette),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBadge(icon: Icons.menu_book_outlined, palette: palette),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      language,
                      nl: 'Help & handleiding',
                      en: 'Help & guide',
                      fr: 'Aide & guide',
                      es: 'Ayuda y guía',
                    ),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _t(
                      language,
                      nl: 'Vind snel uitleg over instellingen, publiceren, boekingen, klantenflow en dagelijks gebruik.',
                      en: 'Quickly find guidance about settings, publishing, bookings, customer flow and daily use.',
                      fr: 'Retrouvez rapidement des explications sur les paramètres, la publication, les réservations, le parcours client et l’utilisation quotidienne.',
                      es: 'Encuentre rápidamente ayuda sobre ajustes, publicación, reservas, flujo de clientes y uso diario.',
                    ),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                      height: 1.38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.palette, required this.language});

  final BusinessThemePalette palette;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final spacing = 12.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: _QuickActionCard(
                palette: palette,
                icon: Icons.play_circle_outline_rounded,
                title: _t(
                  language,
                  nl: 'Platform tour bekijken',
                  en: 'View platform tour',
                  fr: 'Voir la visite de la plateforme',
                  es: 'Ver recorrido de la plataforma',
                ),
                subtitle: _t(
                  language,
                  nl: 'Open de volledige 15-stappen rondleiding opnieuw.',
                  en: 'Open the full 15-step platform tour again.',
                  fr: 'Ouvrez à nouveau la visite complète en 15 étapes.',
                  es: 'Vuelva a abrir el recorrido completo de 15 pasos.',
                ),
                onTap: () => _openPlatformTour(context),
              ),
            ),
            SizedBox(
              width: width,
              child: _QuickActionCard(
                palette: palette,
                icon: Icons.picture_as_pdf_outlined,
                title: _t(
                  language,
                  nl: 'Brochure bekijken',
                  en: 'View brochure',
                  fr: 'Voir la brochure',
                  es: 'Ver folleto',
                ),
                subtitle: _t(
                  language,
                  nl: 'Open de volledige platformbrochure.',
                  en: 'Open the full platform brochure.',
                  fr: 'Ouvrez la brochure complète de la plateforme.',
                  es: 'Abre el folleto completo de la plataforma.',
                ),
                onTap: () => _viewPlatformBrochure(context, language),
              ),
            ),
            SizedBox(
              width: width,
              child: _QuickActionCard(
                palette: palette,
                icon: Icons.menu_book_outlined,
                title: _t(
                  language,
                  nl: 'Bedrijfspagina handleiding bekijken',
                  en: 'View business page guide',
                  fr: 'Voir le guide de la page entreprise',
                  es: 'Ver guía de la página de empresa',
                ),
                subtitle: _t(
                  language,
                  nl: 'Open de volledige bedrijfspagina-handleiding.',
                  en: 'Open the full business page guide.',
                  fr: 'Ouvrez le guide complet de la page entreprise.',
                  es: 'Abre la guía completa de la página de empresa.',
                ),
                onTap: () => _viewBusinessPageGuide(context, language),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final BusinessThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: _premiumDecoration(palette),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _IconBadge(icon: icon, palette: palette),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12.4,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.accent.withOpacity(0.88),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpExpansionCard extends StatelessWidget {
  const _HelpExpansionCard({
    required this.palette,
    required this.language,
    required this.title,
    required this.points,
    required this.icon,
  });

  final BusinessThemePalette palette;
  final AppLanguage language;
  final _L title;
  final List<_L> points;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _premiumDecoration(palette),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: palette.accent.withOpacity(0.08),
          highlightColor: palette.accent.withOpacity(0.05),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: palette.accent,
          collapsedIconColor: palette.textMuted,
          leading: Icon(icon, color: palette.accent),
          title: Text(
            title.of(language),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15.2,
            ),
          ),
          children: [
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: palette.accent.withOpacity(0.82),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        point.of(language),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13.2,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FaqBlock extends StatelessWidget {
  const _FaqBlock({required this.palette, required this.language});

  final BusinessThemePalette palette;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text(
            _t(
              language,
              nl: 'Veelgestelde vragen',
              en: 'FAQ',
              fr: 'Questions fréquentes',
              es: 'Preguntas frecuentes',
            ),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        for (final item in _faqItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HelpExpansionCard(
              palette: palette,
              language: language,
              title: item.question,
              points: <_L>[item.answer],
              icon: Icons.help_outline_rounded,
            ),
          ),
      ],
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.palette, required this.language});

  final BusinessThemePalette palette;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _premiumDecoration(palette),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBadge(icon: Icons.support_agent_rounded, palette: palette),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      language,
                      nl: 'Hulp nodig?',
                      en: 'Need help?',
                      fr: 'Besoin d’aide ?',
                      es: '¿Necesita ayuda?',
                    ),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      language,
                      nl: 'Controleer eerst je instellingen, boekingslink en chauffeursgegevens. Veel dagelijkse vragen worden daar opgelost.',
                      en: 'First check your settings, booking link and driver details. Most daily questions are solved there.',
                      fr: 'Vérifiez d’abord vos paramètres, votre lien de réservation et les données chauffeur. La plupart des questions quotidiennes se résolvent là.',
                      es: 'Revise primero sus ajustes, enlace de reserva y datos de conductores. La mayoría de preguntas diarias se resuelven ahí.',
                    ),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13.2,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openWhatsAppSupport(context, language),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(
                        _t(
                          language,
                          nl: 'WhatsApp-support openen',
                          en: 'Open WhatsApp support',
                          fr: 'Ouvrir le support WhatsApp',
                          es: 'Abrir soporte por WhatsApp',
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.textOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.palette});

  final IconData icon;
  final BusinessThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withOpacity(palette.isDark ? 0.26 : 0.18),
            palette.surfaceAlt,
          ],
        ),
        border: Border.all(color: palette.accent.withOpacity(0.42)),
      ),
      child: Icon(icon, color: palette.accent, size: 24),
    );
  }
}

void _openPlatformTour(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (orientationCtx) => BusinessOrientationFlowPage(
        onFinish: () {
          if (!orientationCtx.mounted) return;
          Navigator.of(orientationCtx).maybePop();
        },
        onSkip: () {
          if (!orientationCtx.mounted) return;
          Navigator.of(orientationCtx).maybePop();
        },
      ),
    ),
  );
}

Future<void> _openWhatsAppSupport(
  BuildContext context,
  AppLanguage language,
) async {
  final Uri uri = Uri.parse(_fluxidiSupportWhatsAppUrl).replace(
    queryParameters: <String, String>{
      'text': _t(
        language,
        nl: 'Hallo Fluxidi, ik heb hulp nodig met mijn account of instellingen.',
        en: 'Hello Fluxidi, I need help with my account or settings.',
        fr: 'Bonjour Fluxidi, j’ai besoin d’aide avec mon compte ou mes paramètres.',
        es: 'Hola Fluxidi, necesito ayuda con mi cuenta o configuración.',
      ),
    },
  );
  final bool opened = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        _t(
          language,
          nl: 'WhatsApp kon niet geopend worden.',
          en: 'WhatsApp could not be opened.',
          fr: 'WhatsApp n’a pas pu être ouvert.',
          es: 'No se pudo abrir WhatsApp.',
        ),
      ),
    ),
  );
}

String _brochureAssetPathForLanguage(AppLanguage language) {
  return _brochureAssetByLanguage[language] ??
      _brochureAssetByLanguage[AppLanguage.en]!;
}

Future<void> _viewPlatformBrochure(
  BuildContext context,
  AppLanguage language,
) async {
  try {
    final String assetPath = _brochureAssetPathForLanguage(language);
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final Directory tempDir = await getTemporaryDirectory();
    final String fileName = assetPath.split('/').last;
    final File file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final OpenResult result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done || !context.mounted) return;
    _showBrochureViewError(context, language);
  } catch (error, stackTrace) {
    debugPrint(
      '[HELP_MANUAL][BROCHURE_VIEW_FAIL] error=$error stack=$stackTrace',
    );
    if (!context.mounted) return;
    _showBrochureViewError(context, language);
  }
}

void _showBrochureViewError(BuildContext context, AppLanguage language) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        _t(
          language,
          nl: 'De brochure kon niet worden geopend. Probeer het opnieuw.',
          en: 'Could not open the brochure. Please try again.',
          fr: 'Impossible d’ouvrir la brochure. Veuillez réessayer.',
          es: 'No se pudo abrir el folleto. Inténtelo de nuevo.',
        ),
      ),
    ),
  );
}

String _businessGuideAssetPathForLanguage(AppLanguage language) {
  return _businessGuideAssetByLanguage[language] ??
      _businessGuideAssetByLanguage[AppLanguage.en]!;
}

Future<void> _viewBusinessPageGuide(
  BuildContext context,
  AppLanguage language,
) async {
  try {
    final String assetPath = _businessGuideAssetPathForLanguage(language);
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final Directory tempDir = await getTemporaryDirectory();
    final String fileName = assetPath.split('/').last;
    final File file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final OpenResult result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done || !context.mounted) return;
    _showBusinessGuideViewError(context, language);
  } catch (error, stackTrace) {
    debugPrint(
      '[HELP_MANUAL][BUSINESS_GUIDE_VIEW_FAIL] error=$error stack=$stackTrace',
    );
    if (!context.mounted) return;
    _showBusinessGuideViewError(context, language);
  }
}

void _showBusinessGuideViewError(BuildContext context, AppLanguage language) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        _t(
          language,
          nl: 'De bedrijfspagina-handleiding kon niet worden geopend. Probeer het opnieuw.',
          en: 'Could not open the business page guide. Please try again.',
          fr: 'Impossible d’ouvrir le guide de la page entreprise. Veuillez réessayer.',
          es: 'No se pudo abrir la guía de la página de empresa. Inténtelo de nuevo.',
        ),
      ),
    ),
  );
}

BoxDecoration _premiumDecoration(BusinessThemePalette palette) {
  return BoxDecoration(
    color: palette.surface.withOpacity(palette.isDark ? 0.96 : 1),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: palette.border.withOpacity(0.82)),
    boxShadow: [
      BoxShadow(
        color: palette.shadow.withOpacity(palette.isDark ? 0.34 : 0.14),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

String _t(
  AppLanguage language, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  return _L(nl: nl, en: en, fr: fr, es: es).of(language);
}

class _L {
  const _L({
    required this.nl,
    required this.en,
    required this.fr,
    required this.es,
  });

  final String nl;
  final String en;
  final String fr;
  final String es;

  String of(AppLanguage language) {
    switch (language) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
    }
  }
}

class _HelpManualSection {
  const _HelpManualSection({
    required this.title,
    required this.icon,
    required this.points,
  });

  final _L title;
  final IconData icon;
  final List<_L> points;
}

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});

  final _L question;
  final _L answer;
}

const _helpSections = <_HelpManualSection>[
  _HelpManualSection(
    title: _L(
      nl: 'Eerste instellingen',
      en: 'First settings',
      fr: 'Premiers réglages',
      es: 'Primeros ajustes',
    ),
    icon: Icons.tune_rounded,
    points: [
      _L(
        nl: 'Bedrijfsgegevens vormen de basis voor boekingen, ritbonnen en facturen.',
        en: 'Company details are the basis for bookings, receipts and invoices.',
        fr: 'Les données de l’entreprise sont la base des réservations, reçus et factures.',
        es: 'Los datos de empresa son la base de reservas, recibos y facturas.',
      ),
      _L(
        nl: 'Btw/facturatie moet correct zijn voor zakelijke documenten.',
        en: 'VAT and billing details must be correct for business documents.',
        fr: 'La TVA et la facturation doivent être correctes pour les documents professionnels.',
        es: 'El IVA y la facturación deben ser correctos para documentos profesionales.',
      ),
      _L(
        nl: 'Diensten en prijzen bepalen wat klanten kunnen boeken en welke prijs Fluxidi berekent.',
        en: 'Services and prices define what customers can book and which price Fluxidi calculates.',
        fr: 'Les services et prix déterminent ce que les clients peuvent réserver et le prix calculé par Fluxidi.',
        es: 'Servicios y precios determinan qué pueden reservar los clientes y qué precio calcula Fluxidi.',
      ),
      _L(
        nl: 'Voertuigen en chauffeurs zijn nodig voor planning, dispatch en uitvoering.',
        en: 'Vehicles and drivers are needed for planning, dispatch and ride execution.',
        fr: 'Les véhicules et chauffeurs sont nécessaires pour la planification, le dispatch et l’exécution.',
        es: 'Vehículos y conductores son necesarios para planificación, despacho y ejecución.',
      ),
    ],
  ),
  _HelpManualSection(
    title: _L(
      nl: 'Publiceren & boekingslink',
      en: 'Publishing & booking link',
      fr: 'Publication & lien de réservation',
      es: 'Publicación y enlace de reserva',
    ),
    icon: Icons.qr_code_2_rounded,
    points: [
      _L(
        nl: 'Publiceren maakt het bedrijfsprofiel, diensten en boekingsmogelijkheden klaar voor klanten.',
        en: 'Publishing prepares the company profile, services and booking options for customers.',
        fr: 'La publication prépare le profil, les services et les possibilités de réservation pour les clients.',
        es: 'Publicar prepara el perfil, servicios y opciones de reserva para los clientes.',
      ),
      _L(
        nl: 'De publieke boekingslink en QR-code kunnen gedeeld worden via website, WhatsApp, e-mail of drukwerk.',
        en: 'The public booking link and QR code can be shared via website, WhatsApp, email or print.',
        fr: 'Le lien public et le code QR peuvent être partagés via site web, WhatsApp, e-mail ou support imprimé.',
        es: 'El enlace público y código QR pueden compartirse por web, WhatsApp, correo o material impreso.',
      ),
      _L(
        nl: 'Een volledig profiel verhoogt vertrouwen: logo, thema, regio, diensten, contactgegevens en voertuiginformatie.',
        en: 'A complete profile builds trust: logo, theme, region, services, contact details and vehicle information.',
        fr: 'Un profil complet inspire confiance : logo, thème, région, services, coordonnées et informations véhicules.',
        es: 'Un perfil completo genera confianza: logo, tema, región, servicios, contacto e información de vehículos.',
      ),
      _L(
        nl: 'Correct publiceren voorkomt dat klanten onvolledige of oude informatie zien.',
        en: 'Publishing correctly prevents customers from seeing incomplete or old information.',
        fr: 'Une publication correcte évite que les clients voient des informations incomplètes ou anciennes.',
        es: 'Publicar correctamente evita que los clientes vean información incompleta o antigua.',
      ),
    ],
  ),
  _HelpManualSection(
    title: _L(
      nl: 'Boekingen begrijpen',
      en: 'Understanding bookings',
      fr: 'Comprendre les réservations',
      es: 'Entender las reservas',
    ),
    icon: Icons.calendar_month_rounded,
    points: [
      _L(
        nl: 'Een boeking loopt van aanvraag naar prijsberekening, bevestiging, betaling of betalen in de wagen, uitvoering en ritgeschiedenis.',
        en: 'A booking moves from request to price calculation, confirmation, payment or pay-in-car, execution and ride history.',
        fr: 'Une réservation va de la demande au calcul du prix, à la confirmation, au paiement ou paiement dans le véhicule, à l’exécution et à l’historique.',
        es: 'Una reserva pasa de solicitud a cálculo de precio, confirmación, pago o pago en el vehículo, ejecución e historial.',
      ),
      _L(
        nl: 'Boekingen verschijnen in de cockpit en in de chauffeurflow afhankelijk van toewijzing en status.',
        en: 'Bookings appear in the cockpit and driver flow depending on assignment and status.',
        fr: 'Les réservations apparaissent dans le cockpit et le parcours chauffeur selon l’affectation et le statut.',
        es: 'Las reservas aparecen en la cabina y flujo del conductor según asignación y estado.',
      ),
      _L(
        nl: 'Luchthavenritten, zakelijke ritten, klantboekingen en directe ritten kunnen elk hun eigen context hebben.',
        en: 'Airport rides, business rides, customer bookings and direct rides can each have their own context.',
        fr: 'Courses aéroport, trajets professionnels, réservations client et courses directes peuvent avoir leur propre contexte.',
        es: 'Traslados de aeropuerto, viajes empresariales, reservas de cliente y viajes directos pueden tener su propio contexto.',
      ),
      _L(
        nl: 'Annulaties, refunds en credits blijven onderdeel van de boekingsgeschiedenis.',
        en: 'Cancellations, refunds and credits remain part of booking history.',
        fr: 'Annulations, remboursements et crédits restent dans l’historique des réservations.',
        es: 'Cancelaciones, reembolsos y créditos siguen formando parte del historial de reservas.',
      ),
    ],
  ),
  _HelpManualSection(
    title: _L(
      nl: 'Klantenflow',
      en: 'Customer flow',
      fr: 'Parcours client',
      es: 'Flujo del cliente',
    ),
    icon: Icons.people_alt_outlined,
    points: [
      _L(
        nl: 'De klantflow helpt klanten sneller boeken via link of QR.',
        en: 'The customer flow helps customers book faster via link or QR.',
        fr: 'Le parcours client aide les clients à réserver plus vite via lien ou QR.',
        es: 'El flujo del cliente ayuda a reservar más rápido por enlace o QR.',
      ),
      _L(
        nl: 'Klanten kunnen gegevens invullen, ritten bevestigen, betalen en ritstatus volgen.',
        en: 'Customers can enter details, confirm rides, pay and follow ride status.',
        fr: 'Les clients peuvent saisir leurs données, confirmer, payer et suivre le statut de course.',
        es: 'Los clientes pueden introducir datos, confirmar viajes, pagar y seguir el estado.',
      ),
      _L(
        nl: 'Een duidelijke klantflow verhoogt herhaalboekingen en vermindert telefonische vragen.',
        en: 'A clear customer flow increases repeat bookings and reduces phone questions.',
        fr: 'Un parcours clair augmente les réservations répétées et réduit les questions téléphoniques.',
        es: 'Un flujo claro aumenta reservas repetidas y reduce preguntas por teléfono.',
      ),
      _L(
        nl: 'Correcte klantgegevens zijn belangrijk voor bevestigingen, ritbonnen en opvolging.',
        en: 'Correct customer details are important for confirmations, receipts and follow-up.',
        fr: 'Des données client correctes sont importantes pour confirmations, reçus et suivi.',
        es: 'Los datos correctos del cliente son importantes para confirmaciones, recibos y seguimiento.',
      ),
    ],
  ),
  _HelpManualSection(
    title: _L(
      nl: 'Chauffeursflow',
      en: 'Driver flow',
      fr: 'Parcours chauffeur',
      es: 'Flujo del conductor',
    ),
    icon: Icons.local_taxi_outlined,
    points: [
      _L(
        nl: 'Chauffeurs zien hun ritten, starten/stoppen ritten en gebruiken calculator of streetride waar voorzien.',
        en: 'Drivers see their rides, start/stop rides and use calculator or streetride where available.',
        fr: 'Les chauffeurs voient leurs courses, démarrent/arrêtent et utilisent le calculateur ou streetride si prévu.',
        es: 'Los conductores ven sus viajes, inician/detienen viajes y usan calculadora o streetride si está previsto.',
      ),
      _L(
        nl: 'Navigatie kan vanuit de chauffeurflow geopend worden.',
        en: 'Navigation can be opened from the driver flow.',
        fr: 'La navigation peut être ouverte depuis le parcours chauffeur.',
        es: 'La navegación puede abrirse desde el flujo del conductor.',
      ),
      _L(
        nl: 'Chauffeursdocumenten, voertuigkoppeling en status helpen de operatie correct houden.',
        en: 'Driver documents, vehicle linking and status help keep operations correct.',
        fr: 'Documents chauffeur, véhicule lié et statut aident à garder l’opération correcte.',
        es: 'Documentos del conductor, vehículo vinculado y estado ayudan a mantener la operación correcta.',
      ),
      _L(
        nl: 'De chauffeurflow ondersteunt dagelijks gebruik zonder dat de bedrijfsleider alles manueel moet opvolgen.',
        en: 'The driver flow supports daily use without the business owner following up everything manually.',
        fr: 'Le parcours chauffeur soutient l’usage quotidien sans suivi manuel de tout par le dirigeant.',
        es: 'El flujo del conductor facilita el uso diario sin que el responsable controle todo manualmente.',
      ),
    ],
  ),
  _HelpManualSection(
    title: _L(nl: 'Betalingen', en: 'Payments', fr: 'Paiements', es: 'Pagos'),
    icon: Icons.payments_outlined,
    points: [
      _L(
        nl: 'Fluxidi ondersteunt betalen in de wagen en online betaalflows afhankelijk van de configuratie.',
        en: 'Fluxidi supports pay-in-car and online payment flows depending on configuration.',
        fr: 'Fluxidi prend en charge le paiement dans le véhicule et les paiements en ligne selon la configuration.',
        es: 'Fluxidi admite pago en el vehículo y pagos online según la configuración.',
      ),
      _L(
        nl: 'Betaalstatussen helpen cockpit, chauffeur en klant dezelfde informatie zien.',
        en: 'Payment statuses help cockpit, driver and customer see the same information.',
        fr: 'Les statuts de paiement aident cockpit, chauffeur et client à voir les mêmes informations.',
        es: 'Los estados de pago ayudan a cabina, conductor y cliente a ver la misma información.',
      ),
      _L(
        nl: 'Refunds en credits horen bij correcte klantenservice en administratie.',
        en: 'Refunds and credits belong to correct customer service and administration.',
        fr: 'Remboursements et crédits font partie d’un service client et d’une administration corrects.',
        es: 'Reembolsos y créditos forman parte de buen servicio al cliente y administración.',
      ),
      _L(
        nl: 'Stel betaalmethoden bewust in zodat klanten weten wat mogelijk is.',
        en: 'Set payment methods deliberately so customers know what is possible.',
        fr: 'Configurez les méthodes de paiement consciemment pour que les clients sachent ce qui est possible.',
        es: 'Configure métodos de pago con intención para que los clientes sepan qué es posible.',
      ),
    ],
  ),
  _HelpManualSection(
    title: _L(
      nl: 'Ritbonnen, documenten & compliance',
      en: 'Receipts, documents & compliance',
      fr: 'Reçus, documents & conformité',
      es: 'Recibos, documentos y cumplimiento',
    ),
    icon: Icons.description_outlined,
    points: [
      _L(
        nl: 'Ritbonnen en geschiedenis helpen bij administratie, klantvragen en controle.',
        en: 'Receipts and history help with administration, customer questions and checks.',
        fr: 'Reçus et historique aident pour l’administration, les questions client et les contrôles.',
        es: 'Recibos e historial ayudan con administración, preguntas de clientes y control.',
      ),
      _L(
        nl: 'Documenten voor chauffeurs en voertuigen houden de vloot professioneel georganiseerd.',
        en: 'Documents for drivers and vehicles keep the fleet professionally organized.',
        fr: 'Les documents chauffeurs et véhicules gardent la flotte organisée professionnellement.',
        es: 'Documentos de conductores y vehículos mantienen la flota organizada profesionalmente.',
      ),
      _L(
        nl: 'Compliance-registratie ondersteunt een betrouwbare ritadministratie.',
        en: 'Compliance registration supports reliable ride administration.',
        fr: 'L’enregistrement conformité soutient une administration fiable des courses.',
        es: 'El registro de cumplimiento apoya una administración fiable de viajes.',
      ),
      _L(
        nl: 'Chiron- en Peppol-gerichte administratie hoort bij professionele Vlaamse taxi- en vervoersbedrijven.',
        en: 'Chiron and Peppol-focused administration belongs with professional Flemish taxi and transport companies.',
        fr: 'L’administration orientée Chiron et Peppol fait partie des entreprises flamandes professionnelles de taxi et transport.',
        es: 'La administración orientada a Chiron y Peppol corresponde a empresas flamencas profesionales de taxi y transporte.',
      ),
    ],
  ),
];

const _faqItems = <_FaqItem>[
  _FaqItem(
    question: _L(
      nl: 'Waarom moet ik publiceren?',
      en: 'Why do I need to publish?',
      fr: 'Pourquoi dois-je publier ?',
      es: '¿Por qué debo publicar?',
    ),
    answer: _L(
      nl: 'Publiceren maakt je actuele profiel, diensten en boekingsmogelijkheden zichtbaar voor klanten.',
      en: 'Publishing makes your current profile, services and booking options visible to customers.',
      fr: 'Publier rend visibles votre profil, vos services et vos options de réservation actuels.',
      es: 'Publicar muestra a los clientes su perfil, servicios y opciones de reserva actuales.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Waar vind ik mijn boekingslink?',
      en: 'Where do I find my booking link?',
      fr: 'Où trouver mon lien de réservation ?',
      es: '¿Dónde encuentro mi enlace de reserva?',
    ),
    answer: _L(
      nl: 'Gebruik “Deel boekingslink” op Business Home voor de link en QR-code.',
      en: 'Use “Share booking link” on Business Home for the link and QR code.',
      fr: 'Utilisez « Partager le lien de réservation » sur Business Home pour le lien et le QR.',
      es: 'Use “Compartir enlace de reserva” en Business Home para el enlace y QR.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Hoe deel ik mijn QR-code?',
      en: 'How do I share my QR code?',
      fr: 'Comment partager mon code QR ?',
      es: '¿Cómo comparto mi código QR?',
    ),
    answer: _L(
      nl: 'Open “Deel boekingslink” en gebruik de deeloptie voor website, WhatsApp, e-mail of drukwerk.',
      en: 'Open “Share booking link” and use the share option for website, WhatsApp, email or print.',
      fr: 'Ouvrez « Partager le lien de réservation » et utilisez l’option de partage.',
      es: 'Abra “Compartir enlace de reserva” y use la opción de compartir.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Waarom moet ik voertuigen en chauffeurs toevoegen?',
      en: 'Why add vehicles and drivers?',
      fr: 'Pourquoi ajouter véhicules et chauffeurs ?',
      es: '¿Por qué añadir vehículos y conductores?',
    ),
    answer: _L(
      nl: 'Ze zijn nodig voor planning, toewijzing, uitvoering en duidelijke ritopvolging.',
      en: 'They are needed for planning, assignment, execution and clear ride follow-up.',
      fr: 'Ils sont nécessaires pour planifier, affecter, exécuter et suivre les courses.',
      es: 'Son necesarios para planificar, asignar, ejecutar y seguir viajes.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Hoe wijzig ik mijn prijzen?',
      en: 'How do I change my prices?',
      fr: 'Comment modifier mes prix ?',
      es: '¿Cómo cambio mis precios?',
    ),
    answer: _L(
      nl: 'Ga naar instellingen en pas je diensten, tarieven en prijsregels aan. Publiceer daarna opnieuw.',
      en: 'Go to settings and update services, rates and price rules. Then publish again.',
      fr: 'Allez dans les paramètres, modifiez services, tarifs et règles, puis republiez.',
      es: 'Vaya a ajustes, actualice servicios, tarifas y reglas, y publique de nuevo.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Hoe ziet een klant zijn rit?',
      en: 'How does a customer see their ride?',
      fr: 'Comment un client voit-il sa course ?',
      es: '¿Cómo ve un cliente su viaje?',
    ),
    answer: _L(
      nl: 'Via de klantflow kan de klant details, bevestiging, betaling en status volgen.',
      en: 'Through the customer flow, the customer can follow details, confirmation, payment and status.',
      fr: 'Via le parcours client, il suit détails, confirmation, paiement et statut.',
      es: 'En el flujo del cliente puede ver detalles, confirmación, pago y estado.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Hoe werkt betalen in de wagen?',
      en: 'How does pay-in-car work?',
      fr: 'Comment fonctionne le paiement dans le véhicule ?',
      es: '¿Cómo funciona pagar en el vehículo?',
    ),
    answer: _L(
      nl: 'Als dit geconfigureerd is, ziet klant en chauffeur dat betaling in de wagen mogelijk is.',
      en: 'When configured, both customer and driver see that payment in the car is available.',
      fr: 'Si configuré, client et chauffeur voient que le paiement dans le véhicule est possible.',
      es: 'Si está configurado, cliente y conductor ven que el pago en vehículo está disponible.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Waar vind ik ritbonnen?',
      en: 'Where do I find receipts?',
      fr: 'Où trouver les reçus ?',
      es: '¿Dónde encuentro recibos?',
    ),
    answer: _L(
      nl: 'Ritbonnen horen bij ritgeschiedenis en administratie na uitvoering van ritten.',
      en: 'Receipts belong with ride history and administration after rides are completed.',
      fr: 'Les reçus se trouvent avec l’historique et l’administration après les courses.',
      es: 'Los recibos están con historial y administración tras completar viajes.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Wat gebeurt er bij annulatie?',
      en: 'What happens with a cancellation?',
      fr: 'Que se passe-t-il lors d’une annulation ?',
      es: '¿Qué ocurre con una cancelación?',
    ),
    answer: _L(
      nl: 'De boeking krijgt een annulatiestatus en blijft zichtbaar in de geschiedenis.',
      en: 'The booking receives a cancellation status and remains visible in history.',
      fr: 'La réservation reçoit un statut annulé et reste visible dans l’historique.',
      es: 'La reserva recibe estado de cancelación y queda visible en el historial.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Kan een chauffeur navigatie openen?',
      en: 'Can a driver open navigation?',
      fr: 'Un chauffeur peut-il ouvrir la navigation ?',
      es: '¿Puede un conductor abrir navegación?',
    ),
    answer: _L(
      nl: 'Ja, waar beschikbaar kan navigatie vanuit de chauffeurflow geopend worden.',
      en: 'Yes, where available, navigation can be opened from the driver flow.',
      fr: 'Oui, si disponible, la navigation s’ouvre depuis le parcours chauffeur.',
      es: 'Sí, cuando esté disponible, se abre desde el flujo del conductor.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Kan ik de platformrondleiding opnieuw bekijken?',
      en: 'Can I view the platform tour again?',
      fr: 'Puis-je revoir la visite de la plateforme ?',
      es: '¿Puedo volver a ver el recorrido?',
    ),
    answer: _L(
      nl: 'Ja, gebruik “Platformrondleiding bekijken” bovenaan deze help-pagina.',
      en: 'Yes, use “View platform tour” at the top of this help page.',
      fr: 'Oui, utilisez « Voir la visite de la plateforme » en haut de cette page.',
      es: 'Sí, use “Ver recorrido de la plataforma” arriba en esta página.',
    ),
  ),
  _FaqItem(
    question: _L(
      nl: 'Waar vind ik de brochure?',
      en: 'Where do I find the brochure?',
      fr: 'Où trouver la brochure ?',
      es: '¿Dónde encuentro el folleto?',
    ),
    answer: _L(
      nl: 'De brochure staat op kaart 15 van de platformrondleiding en gebruikt automatisch je huidige taal.',
      en: 'The brochure is on card 15 of the platform tour and automatically uses your current language.',
      fr: 'La brochure se trouve sur la carte 15 de la visite et utilise automatiquement votre langue.',
      es: 'El folleto está en la tarjeta 15 del recorrido y usa automáticamente su idioma actual.',
    ),
  ),
];
