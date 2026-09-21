import 'package:flutter/material.dart';

import '../app/customer_theme.dart';

/// Photo card for one customer service.
///
/// Uses the existing standalone photo assets. The title sits on a gradient so
/// it stays readable on every photo, and the icon is what shows when a photo
/// is missing from the bundle.
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
        borderRadius: BorderRadius.circular(16),
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
                errorBuilder: (context, error, stack) => Center(
                  child: Icon(icon, size: 34, color: palette.gold),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.70),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
