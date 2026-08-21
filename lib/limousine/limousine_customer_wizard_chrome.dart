// LIMOUSINE-MARKETPLACE-P2D4C1C — reusable customer-wizard chrome.

import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_customer_entry.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_p2d4c1c_journey.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

class LimousineWizardHero extends StatelessWidget {
  const LimousineWizardHero({
    super.key,
    required this.tokens,
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final LimousineUxTokens tokens;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: compact ? 132 : 168,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              LimousineCustomerEntryContract.visualAsset,
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: tokens.surfaceAlt),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    tokens.heroScrim.withOpacity(0.18),
                    tokens.heroScrim.withOpacity(0.78),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: kLimousineJourneyHeroTitleKey,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onHero,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 18 : 22,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.onHero.withOpacity(0.9),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LimousineWizardStepper extends StatelessWidget {
  const LimousineWizardStepper({
    super.key,
    required this.tokens,
    required this.language,
    required this.current,
    required this.onOpenPast,
  });

  final LimousineUxTokens tokens;
  final AppLanguage language;
  final LimousineRequestWizardStep current;
  final ValueChanged<LimousineRequestWizardStep> onOpenPast;

  @override
  Widget build(BuildContext context) {
    final currentIndex = kLimousineRequestWizardSteps.indexOf(current);
    return SingleChildScrollView(
      key: kLimousineRequestWizardStepperKey,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < kLimousineRequestWizardSteps.length; i++) ...[
            if (i > 0)
              Container(
                width: 22,
                height: 2,
                margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
                color: i <= currentIndex ? tokens.gold : tokens.border,
              ),
            _step(kLimousineRequestWizardSteps[i], i, currentIndex),
          ],
        ],
      ),
    );
  }

  Widget _step(LimousineRequestWizardStep step, int index, int currentIndex) {
    final selected = index == currentIndex;
    final past = index < currentIndex;
    return Material(
      key: limousineRequestWizardStepKey(step),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: past ? () => onOpenPast(step) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: past || selected ? tokens.gold : Colors.transparent,
                  border: Border.all(
                    color: past || selected ? tokens.gold : tokens.muted,
                    width: 1.4,
                  ),
                ),
                child: past
                    ? Icon(Icons.check, size: 16, color: tokens.onPrimarySafe)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: selected ? tokens.onPrimarySafe : tokens.muted,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                limousineRequestWizardStepLabel(step).of(language),
                style: TextStyle(
                  color: selected ? tokens.onSurface : tokens.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on LimousineUxTokens {
  Color get onPrimarySafe =>
      isDark ? const Color(0xFF14110C) : const Color(0xFF1A1408);
}

class LimousineWizardFooter extends StatelessWidget {
  const LimousineWizardFooter({
    super.key,
    required this.tokens,
    required this.language,
    required this.step,
    required this.canAdvance,
    required this.submitting,
    required this.hint,
    required this.onBack,
    required this.onNext,
    required this.maxWidth,
    this.primaryAction,
  });

  final LimousineUxTokens tokens;
  final AppLanguage language;
  final LimousineRequestWizardStep step;
  final bool canAdvance;
  final bool submitting;
  final String hint;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double maxWidth;
  final LocalizedText? primaryAction;

  @override
  Widget build(BuildContext context) {
    final isReview = step == LimousineRequestWizardStep.review;
    return Material(
      key: kLimousineRequestWizardFooterKey,
      color: tokens.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canAdvance)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        hint,
                        key: kLimousineRequestWizardHintKey,
                        style: TextStyle(color: tokens.muted, fontSize: 12.5),
                      ),
                    ),
                  Row(
                    children: [
                      if (onBack != null)
                        OutlinedButton(
                          key: kLimousineRequestWizardBackKey,
                          onPressed: onBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.onSurface,
                            side: BorderSide(color: tokens.border),
                            minimumSize: const Size(48, 48),
                          ),
                          child: Text(kLimousineCustomerBack.of(language)),
                        ),
                      if (onBack != null) const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: isReview
                              ? kLimousineCustomerSubmitKey
                              : kLimousineRequestWizardNextKey,
                          onPressed: canAdvance && !submitting ? onNext : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: tokens.gold,
                            foregroundColor: tokens.onPrimarySafe,
                            minimumSize: const Size(48, 48),
                          ),
                          child: Text(
                            (primaryAction ??
                                    limousineRequestWizardPrimaryAction(step))
                                .of(language),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LimousineJourneyTypeGrid extends StatelessWidget {
  const LimousineJourneyTypeGrid({
    super.key,
    required this.tokens,
    required this.language,
    required this.selected,
    required this.onSelected,
    required this.wide,
  });

  final LimousineUxTokens tokens;
  final AppLanguage language;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool wide;

  static const _types = <String>[
    'point_to_point',
    'airport_transfer',
    'hotel_transfer',
    'event_transfer',
    'hourly_package',
  ];

  static const _icons = <String, IconData>{
    'point_to_point': Icons.route_outlined,
    'airport_transfer': Icons.flight_takeoff,
    'hotel_transfer': Icons.hotel_outlined,
    'event_transfer': Icons.celebration_outlined,
    'hourly_package': Icons.schedule_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in _types)
              SizedBox(
                width: width,
                child: Material(
                  color: selected == type
                      ? tokens.gold.withOpacity(0.14)
                      : tokens.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: ValueKey<String>('limousine_journey_type_$type'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelected(type),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 72),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == type ? tokens.gold : tokens.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_icons[type], color: tokens.gold, size: 20),
                          const SizedBox(height: 6),
                          Text(
                            (kLimousineJourneyTypeLabels[type] ??
                                    kLimousineCustomerStepJourney)
                                .of(language),
                            style: TextStyle(
                              color: tokens.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class LimousineProviderOfferCard extends StatelessWidget {
  const LimousineProviderOfferCard({
    super.key,
    required this.tokens,
    required this.language,
    required this.provider,
    required this.offer,
    required this.selected,
    required this.onSelect,
    required this.wide,
    this.onProfile,
  });

  final LimousineUxTokens tokens;
  final AppLanguage language;
  final LimousineDiscoveredProvider provider;
  final LimousinePublishedOffer offer;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onProfile;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final title = localizedLimousineText(
      offer.title,
      languageCode: language.name,
    );
    final price = limousineCustomerPresentationLabel(
      offer.pricePresentation,
      language,
    );
    final image = offer.photoUrl.isNotEmpty
        ? offer.photoUrl
        : provider.heroPhotoUrl;
    final media = image.isNotEmpty
        ? Image.network(
            image,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: tokens.surfaceAlt,
              child: Icon(Icons.directions_car_filled, color: tokens.gold),
            ),
          )
        : ColoredBox(
            color: tokens.surfaceAlt,
            child: Icon(Icons.directions_car_filled, color: tokens.gold),
          );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          provider.companyName,
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        Text(
          title.isEmpty ? offer.offerId : title,
          style: TextStyle(color: tokens.muted),
        ),
        const SizedBox(height: 6),
        Text(
          offer.isVehicleTargeted
              ? kLimousineProviderExactVehicle.of(language)
              : kLimousineProviderServiceClass.of(language),
          style: TextStyle(
            color: tokens.gold,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        Wrap(
          spacing: 10,
          children: [
            if (offer.passengerCapacity != null)
              Text(
                '${offer.passengerCapacity}',
                style: TextStyle(color: tokens.muted, fontSize: 12),
              ),
            if (offer.luggageCapacity != null)
              Text(
                '${offer.luggageCapacity}',
                style: TextStyle(color: tokens.muted, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          price,
          style: TextStyle(
            color: tokens.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (onProfile != null)
          TextButton(
            onPressed: onProfile,
            child: Text(kLimousineProviderViewProfile.of(language)),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onSelect,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tokens.gold : tokens.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: wide
                ? Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(width: 132, height: 96, child: media),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: details),
                      if (selected)
                        Icon(Icons.check_circle, color: tokens.gold),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(height: 120, child: media),
                      ),
                      const SizedBox(height: 10),
                      details,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class LimousineExtraTile extends StatelessWidget {
  const LimousineExtraTile({
    super.key,
    required this.tokens,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final LimousineUxTokens tokens;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tokens.gold.withOpacity(0.14) : tokens.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72, minWidth: 88),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? tokens.gold : tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.add_circle_outline,
                color: tokens.gold,
                size: 18,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LimousineReturnModeCard extends StatelessWidget {
  const LimousineReturnModeCard({
    super.key,
    required this.tokens,
    required this.title,
    required this.body,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.footer,
  });

  final LimousineUxTokens tokens;
  final String title;
  final String body;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final border = selected ? tokens.gold : tokens.border;
    return Material(
      color: selected ? tokens.gold.withOpacity(0.12) : tokens.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(body, style: TextStyle(color: tokens.muted, height: 1.35)),
              if (footer != null) ...[const SizedBox(height: 8), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

class LimousineDateTimeTile extends StatelessWidget {
  const LimousineDateTimeTile({
    super.key,
    required this.tokens,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.error,
  });

  final LimousineUxTokens tokens;
  final String label;
  final String value;
  final String placeholder;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? placeholder : value,
                  style: TextStyle(
                    color: value.isEmpty ? tokens.muted : tokens.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (error != null && error!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    error!,
                    style: TextStyle(color: tokens.danger, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LimousineReviewSection extends StatelessWidget {
  const LimousineReviewSection({
    super.key,
    required this.tokens,
    required this.title,
    required this.child,
    required this.editLabel,
    required this.onEdit,
  });

  final LimousineUxTokens tokens;
  final String title;
  final Widget child;
  final String editLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 16, color: tokens.gold),
                label: Text(editLabel),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
