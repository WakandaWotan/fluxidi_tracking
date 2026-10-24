// COMPANY-CUSTOMER-OPS-P0 — public fixed price tile and the full searchable list.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'public_fixed_prices.dart';

typedef PublicFixedPriceBookCallback = void Function(PublicFixedPrice entry);

class PublicFixedPriceTile extends StatelessWidget {
  const PublicFixedPriceTile({
    super.key,
    required this.entry,
    required this.language,
    required this.palette,
    required this.onBook,
  });

  final PublicFixedPrice entry;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final PublicFixedPriceBookCallback onBook;

  @override
  Widget build(BuildContext context) {
    final accent = palette.isDark ? palette.gold : palette.bronze;
    final badges = <String>[
      publicFixedPriceScopeLabel(entry, language),
      publicFixedPriceDirectionLabel(entry, language),
      ...publicFixedPriceConditionLabels(entry, language),
    ].where((text) => text.trim().isNotEmpty).toList(growable: false);
    final surcharges = publicFixedPriceSurchargeLabels(entry, language);
    final route = publicFixedPriceRouteText(entry);
    final name = entry.name.trim();

    return Container(
      key: publicFixedPriceTileKey(entry.ruleId),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accent.withOpacity(palette.isDark ? 0.3 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            route,
            softWrap: true,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (name.isNotEmpty && name != route) ...[
            const SizedBox(height: 2),
            Text(
              name,
              softWrap: true,
              style: TextStyle(color: palette.textMuted, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            publicFixedPriceAmountText(entry, language),
            softWrap: true,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in badges)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(palette.isDark ? 0.13 : 0.09),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withOpacity(palette.isDark ? 0.4 : 0.3),
                      ),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (surcharges.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final line in surcharges)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  softWrap: true,
                  style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                ),
              ),
          ],
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: publicFixedPriceBookKey(entry.ruleId),
              onPressed: () => onBook(entry),
              icon: const Icon(Icons.event_available_outlined, size: 17),
              label: Text(kPublicFixedPricesViewAndBook.of(language)),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: palette.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PublicFixedPricesAllPage extends StatefulWidget {
  const PublicFixedPricesAllPage({
    super.key,
    required this.companyName,
    required this.catalog,
    required this.onBook,
  });

  final String companyName;
  final PublicFixedPriceCatalog catalog;
  final PublicFixedPriceBookCallback onBook;

  @override
  State<PublicFixedPricesAllPage> createState() =>
      _PublicFixedPricesAllPageState();
}

class _PublicFixedPricesAllPageState extends State<PublicFixedPricesAllPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, theme, _) {
        final palette = paletteForCustomerTheme(theme);
        final lang = appConfig.currentLanguage;
        final airport = publicFixedPricesMatching(
          widget.catalog.airport,
          _query,
        );
        final city = publicFixedPricesMatching(widget.catalog.city, _query);
        final accent = palette.isDark ? palette.gold : palette.bronze;
        return Scaffold(
          key: kPublicFixedPricesAllPageKey,
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.surface,
            foregroundColor: palette.textPrimary,
            title: Text(kPublicFixedPricesAll.of(lang)),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Text(
                  widget.companyName,
                  softWrap: true,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: kPublicFixedPricesSearchKey,
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  style: TextStyle(color: palette.textPrimary),
                  decoration: InputDecoration(
                    labelText: kPublicFixedPricesSearch.of(lang),
                    labelStyle: TextStyle(color: palette.textMuted),
                    prefixIcon: Icon(Icons.search, color: palette.textMuted),
                    filled: true,
                    fillColor: palette.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (airport.isEmpty && city.isEmpty)
                  Text(
                    kPublicFixedPricesNoSearchResult.of(lang),
                    softWrap: true,
                    style: TextStyle(color: palette.textMuted),
                  ),
                if (airport.isNotEmpty) ...[
                  _groupTitle(kPublicFixedPricesAirports.of(lang), accent),
                  for (final entry in airport)
                    PublicFixedPriceTile(
                      entry: entry,
                      language: lang,
                      palette: palette,
                      onBook: widget.onBook,
                    ),
                  const SizedBox(height: 8),
                ],
                if (city.isNotEmpty) ...[
                  _groupTitle(kPublicFixedPricesCities.of(lang), accent),
                  for (final entry in city)
                    PublicFixedPriceTile(
                      entry: entry,
                      language: lang,
                      palette: palette,
                      onBook: widget.onBook,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _groupTitle(String title, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
