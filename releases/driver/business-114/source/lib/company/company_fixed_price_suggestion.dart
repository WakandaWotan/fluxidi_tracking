import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_breakdown.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';

class CompanyFixedPriceSuggestion extends StatefulWidget {
  const CompanyFixedPriceSuggestion({
    super.key,
    required this.language,
    required this.from,
    required this.to,
    this.fromCity = '',
    this.toCity = '',
    this.fromPostcode = '',
    this.airportIata = '',
    this.airportDirection = '',
    this.passengers = 1,
    this.tier = '',
    this.pickupLat,
    this.pickupLon,
    this.dropoffLat,
    this.dropoffLon,
    this.hasManualAmount = false,
    this.previewer,
    this.onApply,
  });

  final AppLanguage language;
  final String from;
  final String to;
  final String fromCity;
  final String toCity;
  final String fromPostcode;
  final String airportIata;
  final String airportDirection;
  final int passengers;
  final String tier;
  final double? pickupLat;
  final double? pickupLon;
  final double? dropoffLat;
  final double? dropoffLon;
  final bool hasManualAmount;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)?
      previewer;
  final ValueChanged<Map<String, dynamic>>? onApply;

  @override
  State<CompanyFixedPriceSuggestion> createState() =>
      _CompanyFixedPriceSuggestionState();
}

class _CompanyFixedPriceSuggestionState
    extends State<CompanyFixedPriceSuggestion> {
  Map<String, dynamic>? _result;
  bool _loading = false;

  @override
  void didUpdateWidget(covariant CompanyFixedPriceSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from ||
        oldWidget.to != widget.to ||
        oldWidget.airportIata != widget.airportIata ||
        oldWidget.airportDirection != widget.airportDirection) {
      _result = null;
    }
  }

  Future<void> _load() async {
    if (widget.from.trim().isEmpty || widget.to.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final previewer = widget.previewer ?? previewCompanyFixedPrice;
      final result = await previewer(<String, dynamic>{
        'from': widget.from,
        'to': widget.to,
        'from_city': widget.fromCity,
        'to_city': widget.toCity,
        'from_postcode': widget.fromPostcode,
        'airport_iata': widget.airportIata,
        'airport_direction': widget.airportDirection,
        'pax': widget.passengers,
        if (widget.tier.trim().isNotEmpty) 'tier': widget.tier,
        if (widget.pickupLat != null) 'pickup_lat': widget.pickupLat,
        if (widget.pickupLon != null) 'pickup_lon': widget.pickupLon,
        if (widget.dropoffLat != null) 'dropoff_lat': widget.dropoffLat,
        if (widget.dropoffLon != null) 'dropoff_lon': widget.dropoffLon,
      });
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = companyFixedPriceSnapshotOf(_result);
    final matched = _result?['matched'] == true && snapshot != null;
    return Column(
      key: kCompanyFixedPriceSuggestionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: _loading ? null : _load,
          child: Text(
            _loading ? '…' : kCompanyFixedPricesPreview.of(widget.language),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 8),
          if (matched)
            CompanyFixedPriceBreakdown(
              language: widget.language,
              snapshot: snapshot,
            )
          else
            Text(
              companyQuoteRequiresManualQuote(_result)
                  ? kCompanyFixedPricesFallbackQuote.of(widget.language)
                  : kCompanyFixedPricesNoMatch.of(widget.language),
              softWrap: true,
            ),
          if (matched && widget.onApply != null) ...[
            const SizedBox(height: 8),
            FilledButton(
              key: kCompanyFixedPriceUseKey,
              onPressed: () => widget.onApply!(snapshot),
              child: Text(
                widget.hasManualAmount
                    ? '${kCompanyFixedPricesUse.of(widget.language)} — conceptbedrag blijft tot je dit kiest'
                    : kCompanyFixedPricesUse.of(widget.language),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
