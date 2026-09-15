// COMPANY-AGENDA-P0 — leftover-space route canvas. Real Mapbox static preview.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/maps/fluxidi_static_route_preview.dart';

const Key kCompanyAgendaPlanMapKey = Key('company_agenda_plan_map');
const Key kCompanyAgendaRestoreRouteKey = Key('company_agenda_restore_route');

class CompanyPlanRouteMap extends StatelessWidget {
  const CompanyPlanRouteMap({
    super.key,
    required this.language,
    required this.pickup,
    required this.dropoff,
    this.quote,
    this.loading = false,
    this.error,
    this.onRetry,
    this.pickupLocal,
    this.showPriceSource = false,
    this.polyline = '',
    this.compactPlaceholder = false,
  });

  final AppLanguage language;
  final LimousineAddressValue pickup;
  final LimousineAddressValue dropoff;
  final CompanyPlanQuoteResult? quote;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final DateTime? pickupLocal;
  final bool showPriceSource;
  final String polyline;
  final bool compactPlaceholder;

  FluxidiMapLonLat? get _from {
    final lat = quote?.pickupLat ?? pickup.lat;
    final lon = quote?.pickupLon ?? pickup.lon;
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
      return null;
    }
    return FluxidiMapLonLat(lon, lat);
  }

  FluxidiMapLonLat? get _to {
    final lat = quote?.dropoffLat ?? dropoff.lat;
    final lon = quote?.dropoffLon ?? dropoff.lon;
    if (lat == null || lon == null || !lon.isFinite || !lat.isFinite) {
      return null;
    }
    return FluxidiMapLonLat(lon, lat);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = companyPlanRouteStatus(
      from: pickup,
      to: dropoff,
      loading: loading,
      quote: quote,
      error: error,
      hasPolyline: polyline.trim().isNotEmpty,
    );
    final from = pickup.displayText.trim();
    final to = dropoff.displayText.trim();
    final summary = quote != null && quote!.hasRoute
        ? [
            formatCompanyPlanQuoteRoute(quote!, language),
            formatCompanyPlanQuotePrice(
              quote!,
              language,
              includeSource: showPriceSource,
            ),
            formatCompanyPlanQuoteEta(
              result: quote!,
              pickupLocal: pickupLocal,
            ),
          ].where((part) => part.trim().isNotEmpty).join(' · ')
        : '';
    final fromPoint = _from;
    final toPoint = _to;
    final mapUrl = fromPoint != null && toPoint != null
        ? fluxidiStaticRoutePreviewUrl(pickup: fromPoint, dropoff: toPoint)
        : null;
    final restore = status == CompanyPlanRouteStatus.needsRestore ||
        (status == CompanyPlanRouteStatus.missingEndpoints &&
            compactPlaceholder);
    if (restore && mapUrl == null) {
      return DecoratedBox(
        key: kCompanyAgendaPlanMapKey,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  if (from.isNotEmpty) from,
                  if (to.isNotEmpty) to,
                ].join(' → '),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                kCompanyAgendaRouteMissingCompact.of(language),
                style: theme.textTheme.bodySmall,
              ),
              TextButton(
                key: kCompanyAgendaRestoreRouteKey,
                onPressed: onRetry,
                child: Text(kCompanyAgendaRestoreRoute.of(language)),
              ),
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      key: kCompanyAgendaPlanMapKey,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (mapUrl != null)
                  Image.network(
                    mapUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  )
                else
                  ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MapEnd(
                        icon: Icons.trip_origin,
                        text: from.isEmpty
                            ? kCompanyAgendaPickupPlace.of(language)
                            : from,
                      ),
                      const Spacer(),
                      if (status == CompanyPlanRouteStatus.calculating)
                        Text(
                          kCompanyAgendaRouteCalculating.of(language),
                          key: kCompanyPlanQuoteStatusKey,
                          style: theme.textTheme.titleSmall,
                        )
                      else if (status == CompanyPlanRouteStatus.failed) ...[
                        Text(
                          companyPlanQuoteErrorText(error, language),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        if (onRetry != null)
                          TextButton(
                            key: kCompanyPlanQuoteRetryKey,
                            onPressed: onRetry,
                            child: Text(kCompanyAgendaRouteRetry.of(language)),
                          ),
                      ] else if (summary.isNotEmpty)
                        Text(summary, style: theme.textTheme.titleSmall),
                      const Spacer(),
                      _MapEnd(
                        icon: Icons.flag_outlined,
                        text: to.isEmpty
                            ? kCompanyAgendaDropoffPlace.of(language)
                            : to,
                        alignEnd: true,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MapEnd extends StatelessWidget {
  const _MapEnd({
    required this.icon,
    required this.text,
    this.alignEnd = false,
  });

  final IconData icon;
  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurface),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return alignEnd
        ? Align(alignment: Alignment.centerRight, child: child)
        : child;
  }
}
