// COMPANY-CUSTOMER-OPS-P0 — searchable European airport field.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';

class CompanyAirportSearchField extends StatefulWidget {
  const CompanyAirportSearchField({
    super.key,
    required this.language,
    required this.selected,
    required this.onSelected,
    this.fieldKey,
    this.label,
  });

  final AppLanguage language;
  final AirportCatalogAirport? selected;
  final ValueChanged<AirportCatalogAirport> onSelected;
  final Key? fieldKey;
  final String? label;

  @override
  State<CompanyAirportSearchField> createState() =>
      _CompanyAirportSearchFieldState();
}

class _CompanyAirportSearchFieldState extends State<CompanyAirportSearchField> {
  late final TextEditingController _query;
  List<AirportCatalogAirport> _matches = const [];

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(
      text: widget.selected?.displayLabel ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant CompanyAirportSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.selected?.displayLabel ?? '';
    if (widget.selected?.iata != oldWidget.selected?.iata &&
        _query.text != next) {
      _query.text = next;
      _matches = const [];
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    setState(() {
      _matches = raw.trim().length < 2
          ? const []
          : searchPublishedAirports(raw);
    });
  }

  void _pick(AirportCatalogAirport airport) {
    _query.text = airport.displayLabel;
    setState(() => _matches = const []);
    widget.onSelected(airport);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: widget.fieldKey ?? kCompanyAirportSearchFieldKey,
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label ?? kCompanyAirportSearch.of(widget.language),
            hintText: kCompanyAirportSearchHint.of(widget.language),
            suffixIcon: selected == null
                ? const Icon(Icons.flight_rounded)
                : IconButton(
                    tooltip: kCompanyAirportSearch.of(widget.language),
                    onPressed: () {
                      _query.clear();
                      setState(() => _matches = const []);
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: _onQueryChanged,
        ),
        if (_matches.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Material(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _matches.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final airport = _matches[index];
                  return ListTile(
                    key: companyAirportSuggestionKey(airport.iata),
                    dense: true,
                    title: Text(airport.displayLabel, softWrap: true),
                    subtitle: Text(airport.formattedAddress, softWrap: true),
                    onTap: () => _pick(airport),
                  );
                },
              ),
            ),
          ),
        ],
        if (selected != null && _matches.isEmpty) ...[
          const SizedBox(height: 8),
          Text(selected.formattedAddress, softWrap: true),
        ],
      ],
    );
  }
}
