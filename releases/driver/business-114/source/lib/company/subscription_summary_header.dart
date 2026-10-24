import 'package:flutter/material.dart';

/// Content-sized subscription identity and amount; never gives a long label
/// the remaining zero width of a price Row on a narrow phone.
class SubscriptionSummaryHeader extends StatelessWidget {
  const SubscriptionSummaryHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.amount,
    required this.period,
    required this.internalAccount,
    required this.textColor,
    required this.secondaryTextColor,
    required this.accent,
  });
  final String title, subtitle, amount, period;
  final Widget badge;
  final bool internalAccount;
  final Color textColor, secondaryTextColor, accent;

  @override
  Widget build(BuildContext context) {
    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: accent,
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: textColor,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 520 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  badge,
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 8), badge],
            );
          },
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: amount,
                style: TextStyle(
                  color: textColor,
                  fontSize: internalAccount ? 18 : 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextSpan(
                text: internalAccount ? '\n$period' : '  $period',
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          style: const TextStyle(height: 1.3),
        ),
      ],
    );
  }
}
