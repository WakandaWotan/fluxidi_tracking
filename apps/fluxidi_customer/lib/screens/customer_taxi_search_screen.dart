import 'package:flutter/material.dart';

import '../api/public_partner_api.dart';
import '../api/public_partner_models.dart';
import '../app/customer_app_config.dart';
import '../widgets/partner_media.dart';
import 'customer_partner_profile_screen.dart';

/// Search existing taxi companies by postcode and open a public profile.
///
/// Read-only. No quote, no booking and no payment is wired up here.
class CustomerTaxiSearchScreen extends StatefulWidget {
  const CustomerTaxiSearchScreen({
    super.key,
    required this.api,
    this.config = kCustomerAppConfig,
  });

  final PublicPartnerApi api;
  final CustomerAppConfig config;

  @override
  State<CustomerTaxiSearchScreen> createState() =>
      _CustomerTaxiSearchScreenState();
}

class _CustomerTaxiSearchScreenState extends State<CustomerTaxiSearchScreen> {
  final TextEditingController _postcodeCtrl = TextEditingController();

  bool _searching = false;
  bool _searched = false;
  String _searchedPostcode = '';
  PublicApiFailure? _failure;
  List<PublicPartnerSummary> _partners = const <PublicPartnerSummary>[];

  @override
  void dispose() {
    _postcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final normalized = normalizePublicSearchPostcode(_postcodeCtrl.text);
    if (normalized.isEmpty) {
      setState(() {
        _failure = PublicApiFailure.missingInput;
        _searched = false;
        _partners = const <PublicPartnerSummary>[];
      });
      return;
    }
    setState(() {
      _searching = true;
      _failure = null;
      _searched = false;
      _searchedPostcode = normalized;
      _partners = const <PublicPartnerSummary>[];
    });
    try {
      final result = await widget.api.searchByPostcode(normalized);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _partners = result.partners;
      });
    } on PublicApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = false;
        _failure = error.failure;
      });
    }
  }

  void _openProfile(PublicPartnerSummary partner) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerPartnerProfileScreen(
          api: widget.api,
          partnerId: partner.partnerId,
          companyNameFallback: partner.displayName,
          config: widget.config,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Taxi')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!widget.config.supportsCompanyDiscovery) {
      return const _NoticeCard(
        icon: Icons.storefront_outlined,
        title: 'Bedrijfsvariant nog niet ondersteund',
        message:
            'Deze build is ingesteld als klantenapp van één taxibedrijf. Die '
            'variant is nog niet gebouwd. De algemene bedrijvenlijst wordt hier '
            'bewust niet getoond.',
      );
    }
    if (!widget.api.isConfigured) {
      return const _NoticeCard(
        icon: Icons.settings_ethernet_outlined,
        title: 'API niet geconfigureerd',
        message:
            'Deze build heeft geen basis-URL voor de publieke API. Bouw met '
            '--dart-define=$kPublicBookingBaseUrlDefineKey=<url> om bedrijven '
            'te kunnen zoeken.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SearchField(
          controller: _postcodeCtrl,
          enabled: !_searching,
          onSubmit: _searching ? null : _search,
          config: widget.config,
        ),
        const SizedBox(height: 16),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failure != null)
          _FailureCard(
            failure: _failure!,
            onRetry: _failure == PublicApiFailure.missingInput ? null : _search,
            config: widget.config,
          )
        else if (_searched && _partners.isEmpty)
          _NoticeCard(
            icon: Icons.search_off_outlined,
            title: 'Geen bedrijven gevonden',
            message:
                'Geen partners gevonden voor postcode of servicegebied '
                '$_searchedPostcode.',
          )
        else if (_searched) ...<Widget>[
          Text(
            'Actieve partners in $_searchedPostcode',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final partner in _partners)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PartnerCard(
                partner: partner,
                onTap: () => _openProfile(partner),
                config: widget.config,
              ),
            ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
    required this.config,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onSubmit;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Zoek taxibedrijven op postcode of servicegebied.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: config.brand.textSoft),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('taxi_search_postcode_field'),
          controller: controller,
          enabled: enabled,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSubmit?.call(),
          decoration: const InputDecoration(
            labelText: 'Postcode',
            hintText: 'Bijv. 2000',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('taxi_search_button'),
          onPressed: onSubmit,
          child: const Text('Zoek bedrijven'),
        ),
      ],
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.partner,
    required this.onTap,
    required this.config,
  });

  final PublicPartnerSummary partner;
  final VoidCallback onTap;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PartnerMedia(
              heroUrl: partner.heroPhotoUrl,
              logoUrl: partner.logoUrl,
              height: 96,
              config: config,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    partner.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (partner.locationLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      partner.locationLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: config.brand.textSoft,
                      ),
                    ),
                  ],
                  if (partner.distanceKm != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '${partner.distanceKm!.toStringAsFixed(1)} km',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: config.brand.textSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _StatusChip(bookable: partner.bookable, config: config),
                      if (partner.presentation.hasBadge)
                        Chip(
                          key: const Key('partner_presentation_badge'),
                          label: Text(partner.presentation.badge),
                          visualDensity: VisualDensity.compact,
                        ),
                      for (final badge in partner.serviceBadges)
                        Chip(
                          label: Text(badge),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.bookable, required this.config});

  final bool bookable;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return Chip(
      key: Key(bookable ? 'partner_status_active' : 'partner_status_inactive'),
      visualDensity: VisualDensity.compact,
      label: Text(bookable ? 'Actief' : 'Niet actief'),
      backgroundColor: bookable
          ? config.brand.primary.withValues(alpha: 0.16)
          : null,
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.failure,
    required this.onRetry,
    required this.config,
  });

  final PublicApiFailure failure;
  final VoidCallback? onRetry;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              failureTitle(failure),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              failureMessage(failure),
              style: theme.textTheme.bodySmall?.copyWith(
                color: config.brand.textSoft,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('taxi_search_retry'),
                onPressed: onRetry,
                child: const Text('Opnieuw proberen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String failureTitle(PublicApiFailure failure) {
  switch (failure) {
    case PublicApiFailure.missingInput:
      return 'Vul eerst een postcode in';
    case PublicApiFailure.notConfigured:
      return 'API niet geconfigureerd';
    case PublicApiFailure.network:
      return 'Geen verbinding';
    case PublicApiFailure.badStatus:
    case PublicApiFailure.invalidResponse:
      return 'Zoeken is niet beschikbaar';
  }
}

String failureMessage(PublicApiFailure failure) {
  switch (failure) {
    case PublicApiFailure.missingInput:
      return 'Geef een postcode op om actieve taxibedrijven te zoeken.';
    case PublicApiFailure.notConfigured:
      return 'Deze build heeft geen basis-URL voor de publieke API.';
    case PublicApiFailure.network:
      return 'De verbinding met de server is mislukt. Probeer het opnieuw.';
    case PublicApiFailure.badStatus:
    case PublicApiFailure.invalidResponse:
      return 'Zoeken van bedrijven is momenteel niet beschikbaar.';
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 32, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kCustomerAppConfig.brand.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}
