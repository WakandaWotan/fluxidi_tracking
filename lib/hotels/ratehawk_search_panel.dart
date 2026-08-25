import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

import 'ratehawk_search.dart';

class RatehawkSearchStrip extends StatelessWidget {
  const RatehawkSearchStrip({
    required this.controller,
    required this.languageCode,
    required this.palette,
    this.showSubmitButton = true,
    this.destinationGuidance,
    super.key,
  });

  final RatehawkSearchController controller;
  final String languageCode;
  final CustomerThemePalette palette;
  final bool showSubmitButton;
  final String? destinationGuidance;

  @override
  Widget build(BuildContext context) {
    final complete = controller.completeness().complete;
    final gold = palette.gold;
    final text = palette.textPrimary;
    final muted = palette.textMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: gold.withOpacity(palette.isDark ? 0.34 : 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ratehawkSearchLabel(
              languageCode,
              nl: 'Bestemming en data',
              en: 'Destination and dates',
              fr: 'Destination et dates',
              es: 'Destino y fechas',
            ),
            style: TextStyle(
              color: text,
              fontSize: 13.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: destinationGuidance ??
                ratehawkSearchLabel(
                  languageCode,
                  nl: 'Stad of regio',
                  en: 'City or region',
                  fr: 'Ville ou région',
                  es: 'Ciudad o región',
                ),
            child: _field(
              value: controller.criteria.destination,
              hint: ratehawkSearchLabel(
                languageCode,
                nl: 'Stad of regio',
                en: 'City or region',
                fr: 'Ville ou région',
                es: 'Ciudad o región',
              ),
              onChanged: (value) {
                controller.setCriteria(
                  controller.criteria.copyWith(destination: value),
                );
              },
            ),
          ),
          if ((destinationGuidance ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              destinationGuidance!.trim(),
              style: TextStyle(
                color: muted,
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
                height: 1.28,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dateButton(
                  context: context,
                  label: ratehawkSearchLabel(
                    languageCode,
                    nl: 'Check-in',
                    en: 'Check-in',
                    fr: 'Arrivée',
                    es: 'Entrada',
                  ),
                  value: controller.criteria.checkinYmd,
                  onPicked: (date) {
                    controller.setCriteria(
                      controller.criteria.copyWith(checkin: date),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateButton(
                  context: context,
                  label: ratehawkSearchLabel(
                    languageCode,
                    nl: 'Check-out',
                    en: 'Check-out',
                    fr: 'Départ',
                    es: 'Salida',
                  ),
                  value: controller.criteria.checkoutYmd,
                  onPicked: (date) {
                    controller.setCriteria(
                      controller.criteria.copyWith(checkout: date),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _stepper(
                label: ratehawkSearchLabel(
                  languageCode,
                  nl: 'Kamers',
                  en: 'Rooms',
                  fr: 'Chambres',
                  es: 'Habitaciones',
                ),
                value: controller.criteria.rooms,
                min: 1,
                onChanged: (value) {
                  controller.setCriteria(
                    controller.criteria.copyWith(rooms: value),
                  );
                },
              ),
              _stepper(
                label: ratehawkSearchLabel(
                  languageCode,
                  nl: 'Volwassenen',
                  en: 'Adults',
                  fr: 'Adultes',
                  es: 'Adultos',
                ),
                value: controller.criteria.adults,
                min: 1,
                onChanged: (value) {
                  controller.setCriteria(
                    controller.criteria.copyWith(adults: value),
                  );
                },
              ),
              _stepper(
                label: ratehawkSearchLabel(
                  languageCode,
                  nl: 'Kinderen',
                  en: 'Children',
                  fr: 'Enfants',
                  es: 'Niños',
                ),
                value: controller.criteria.childAges.length,
                min: 0,
                onChanged: (value) {
                  final ages = List<int>.from(controller.criteria.childAges);
                  if (value > ages.length) {
                    ages.addAll(List<int>.filled(value - ages.length, 8));
                  } else if (value < ages.length) {
                    ages.removeRange(value, ages.length);
                  }
                  controller.setCriteria(
                    controller.criteria.copyWith(childAges: ages),
                  );
                },
              ),
            ],
          ),
          if (controller.criteria.childAges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              ratehawkSearchLabel(
                languageCode,
                nl: 'Leeftijden kinderen',
                en: 'Child ages',
                fr: 'Âges des enfants',
                es: 'Edades de los niños',
              ),
              style: TextStyle(
                color: muted,
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < controller.criteria.childAges.length; i++)
                  _stepper(
                    label: '${i + 1}',
                    value: controller.criteria.childAges[i],
                    min: 0,
                    onChanged: (value) {
                      final ages = List<int>.from(
                        controller.criteria.childAges,
                      );
                      ages[i] = value;
                      controller.setCriteria(
                        controller.criteria.copyWith(childAges: ages),
                      );
                    },
                  ),
              ],
            ),
          ],
          if (showSubmitButton) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: complete ? () => controller.submit() : null,
                style: FilledButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: palette.isDark
                      ? Colors.black
                      : const Color(0xFF1F1706),
                  disabledBackgroundColor: gold.withOpacity(0.28),
                  minimumSize: const Size.fromHeight(40),
                ),
                child: Text(
                  ratehawkStateLabel(
                    RatehawkSearchLifecycleState.idle,
                    languageCode,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      style: TextStyle(color: palette.textPrimary, fontSize: 13.2),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 12.6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.gold),
        ),
      ),
    );
  }

  Widget _dateButton({
    required BuildContext context,
    required String label,
    required String value,
    required ValueChanged<DateTime> onPicked,
  }) {
    return OutlinedButton(
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now.add(const Duration(days: 14)),
          firstDate: now,
          lastDate: now.add(const Duration(days: 365)),
        );
        if (picked != null) onPicked(picked);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        minimumSize: const Size.fromHeight(40),
      ),
      child: Text(
        value.isEmpty ? label : '$label $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required int min,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label $value',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 11.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          color: palette.gold,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          color: palette.gold,
        ),
      ],
    );
  }
}

class RatehawkSearchStatusPanel extends StatelessWidget {
  const RatehawkSearchStatusPanel({
    required this.controller,
    required this.languageCode,
    required this.palette,
    super.key,
  });

  final RatehawkSearchController controller;
  final String languageCode;
  final CustomerThemePalette palette;

  @override
  Widget build(BuildContext context) {
    if (controller.state == RatehawkSearchLifecycleState.idle) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final criteria = controller.criteria;
    final resolved = resolveRatehawkSearchDestination(criteria);
    return AnimatedOpacity(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      opacity: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ratehawkStateLabel(controller.state, languageCode),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if ((resolved.city ?? criteria.destination).trim().isNotEmpty)
                  resolved.city ?? criteria.destination,
                if (criteria.checkinYmd.isNotEmpty &&
                    criteria.checkoutYmd.isNotEmpty)
                  '${criteria.checkinYmd} – ${criteria.checkoutYmd}',
                '${criteria.rooms} / ${criteria.adults}',
              ].join(' · '),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (controller.retrievedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                ratehawkSearchLabel(
                  languageCode,
                  nl: 'Opgehaald ${controller.retrievedAt!.toLocal()}',
                  en: 'Retrieved ${controller.retrievedAt!.toLocal()}',
                  fr: 'Récupéré ${controller.retrievedAt!.toLocal()}',
                  es: 'Recuperado ${controller.retrievedAt!.toLocal()}',
                ),
                style: TextStyle(color: palette.textMuted, fontSize: 10.8),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: controller.cancelEdit,
                  child: Text(
                    ratehawkSearchLabel(
                      languageCode,
                      nl: 'Annuleren / bewerken',
                      en: 'Cancel / edit',
                      fr: 'Annuler / modifier',
                      es: 'Cancelar / editar',
                    ),
                  ),
                ),
                if (controller.state ==
                        RatehawkSearchLifecycleState.retryable ||
                    controller.state ==
                        RatehawkSearchLifecycleState.unavailable)
                  TextButton(
                    onPressed: () => controller.submit(),
                    child: Text(
                      ratehawkSearchLabel(
                        languageCode,
                        nl: 'Opnieuw',
                        en: 'Retry',
                        fr: 'Réessayer',
                        es: 'Reintentar',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
