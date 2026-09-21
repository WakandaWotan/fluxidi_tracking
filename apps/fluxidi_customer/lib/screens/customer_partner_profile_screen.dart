import 'package:flutter/material.dart';

import '../api/public_partner_api.dart';
import '../api/public_partner_models.dart';
import '../api/public_partner_visibility.dart';
import '../app/customer_app_config.dart';
import '../widgets/partner_media.dart';
import 'customer_taxi_search_screen.dart' show failureMessage, failureTitle;

/// Public profile of one existing taxi company.
///
/// Shows only what the server returned. Booking is not wired up in this phase,
/// so no action here starts a ride, quote or payment.
class CustomerPartnerProfileScreen extends StatefulWidget {
  const CustomerPartnerProfileScreen({
    super.key,
    required this.api,
    required this.partnerId,
    required this.companyNameFallback,
    this.config = kCustomerAppConfig,
  });

  final PublicPartnerApi api;
  final String partnerId;
  final String companyNameFallback;
  final CustomerAppConfig config;

  @override
  State<CustomerPartnerProfileScreen> createState() =>
      _CustomerPartnerProfileScreenState();
}

class _CustomerPartnerProfileScreenState
    extends State<CustomerPartnerProfileScreen> {
  static const int _postcodePreviewLimit = 8;

  bool _loading = true;
  PublicApiFailure? _failure;
  PublicPartnerProfile? _profile;
  bool _showAllPostcodes = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final profile = await widget.api.loadProfile(widget.partnerId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _profile = profile;
      });
    } on PublicApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = error.failure;
      });
    }
  }

  String get _title {
    final name = _profile?.companyName ?? '';
    if (name.isNotEmpty) return name;
    final fallback = sanitizePublicPartnerBrandName(widget.companyNameFallback);
    return fallback.isNotEmpty ? fallback : 'Bedrijfsprofiel';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final failure = _failure;
    if (failure != null) {
      return _ProfileFailure(
        failure: failure,
        onRetry: _load,
        config: widget.config,
      );
    }
    final profile = _profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }
    return _ProfileBody(
      profile: profile,
      config: widget.config,
      showAllPostcodes: _showAllPostcodes,
      onShowAllPostcodes: () => setState(() => _showAllPostcodes = true),
      previewLimit: _postcodePreviewLimit,
    );
  }
}

class _ProfileFailure extends StatelessWidget {
  const _ProfileFailure({
    required this.failure,
    required this.onRetry,
    required this.config,
  });

  final PublicApiFailure failure;
  final VoidCallback onRetry;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            failureTitle(failure),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            failure == PublicApiFailure.network
                ? failureMessage(failure)
                : 'Publiek partnerprofiel is momenteel niet beschikbaar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('partner_profile_retry'),
            onPressed: onRetry,
            child: const Text('Opnieuw proberen'),
          ),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.profile,
    required this.config,
    required this.showAllPostcodes,
    required this.onShowAllPostcodes,
    required this.previewLimit,
  });

  final PublicPartnerProfile profile;
  final CustomerAppConfig config;
  final bool showAllPostcodes;
  final VoidCallback onShowAllPostcodes;
  final int previewLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final postcodes = showAllPostcodes || profile.postcodes.length <= previewLimit
        ? profile.postcodes
        : profile.postcodes.take(previewLimit).toList(growable: false);
    final hiddenPostcodes = profile.postcodes.length - postcodes.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: PartnerMedia(
            heroUrl: profile.heroPhotoUrl,
            logoUrl: profile.logoUrl,
            height: 150,
            config: config,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            Chip(
              key: Key(
                profile.bookable
                    ? 'profile_status_active'
                    : 'profile_status_inactive',
              ),
              visualDensity: VisualDensity.compact,
              label: Text(profile.bookable ? 'Actief' : 'Niet actief'),
            ),
            if (profile.presentation.hasBadge)
              Chip(
                key: const Key('profile_presentation_badge'),
                visualDensity: VisualDensity.compact,
                label: Text(profile.presentation.badge),
              ),
            if (profile.verifiedPartner)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('Geverifieerd'),
              ),
          ],
        ),
        if (profile.presentation.hasNotice) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            profile.presentation.notice,
            key: const Key('profile_presentation_notice'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
        ],
        if (!profile.bookable) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            publicPartnerInactiveMessageNl(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
        ],
        if (profile.tagline.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(profile.tagline, style: theme.textTheme.titleSmall),
        ],
        if (profile.about.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            profile.about,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: config.brand.textSoft,
            ),
          ),
        ],
        if (profile.hasContactDetails) ...<Widget>[
          const SizedBox(height: 18),
          _SectionTitle('Servicegebied en contact'),
          if (profile.regionLabel.isNotEmpty)
            _DetailRow(label: 'Regio', value: profile.regionLabel),
          if (postcodes.isNotEmpty)
            _DetailRow(label: 'Postcodes', value: postcodes.join(', ')),
          if (hiddenPostcodes > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('profile_show_all_postcodes'),
                onPressed: onShowAllPostcodes,
                child: Text('Nog $hiddenPostcodes postcodes tonen'),
              ),
            ),
          if (profile.publicPhone.isNotEmpty)
            _DetailRow(label: 'Telefoon', value: profile.publicPhone),
          if (profile.bookingEmail.isNotEmpty)
            _DetailRow(label: 'E-mail', value: profile.bookingEmail),
          if (profile.website.isNotEmpty)
            _DetailRow(label: 'Website', value: profile.website),
        ],
        if (profile.services.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _SectionTitle('Diensten'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final service in profile.services)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_humanizeToken(service)),
                ),
            ],
          ),
        ],
        if (profile.paymentMethods.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _SectionTitle('Betaalmethoden van dit bedrijf'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final method in profile.paymentMethods)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_humanizeToken(method)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        Container(
          key: const Key('profile_booking_not_connected'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: config.brand.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Boeken volgt in een volgende fase',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Je kunt dit bedrijf hier bekijken. Prijs opvragen, boeken en '
                'betalen zijn in deze app nog niet aangesloten.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: config.brand.textSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _humanizeToken(String token) {
    final cleaned = token.trim().replaceAll('_', ' ');
    if (cleaned.isEmpty) return token.trim();
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: kCustomerAppConfig.brand.textSoft,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
