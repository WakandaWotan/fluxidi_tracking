import 'package:flutter/material.dart';

import '../app/customer_theme.dart';

/// Photo card for one customer service.
///
/// Uses the existing standalone photo assets: a round icon on the left, the
/// title next to it and an arrow on the right. The scrim is darkest behind the
/// title, because the photos are bright enough there to swallow white text.
/// The icon is what shows when a photo is missing from the bundle.
class CustomerServiceCard extends StatelessWidget {
  const CustomerServiceCard({
    super.key,
    required this.title,
    required this.asset,
    required this.icon,
    required this.onTap,
    this.cardKey,
    this.height = 132,
  });

  final String title;
  final String asset;
  final IconData icon;
  final VoidCallback onTap;
  final Key? cardKey;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = activeCustomerPalette();
    return SizedBox(
      height: height,
      child: Material(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: cardKey,
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    Center(child: Icon(icon, size: 34, color: palette.gold)),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.78),
                      Colors.black.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    stops: const <double>[0.0, 0.45, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Icon(icon, size: 24, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          shadows: <Shadow>[
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
