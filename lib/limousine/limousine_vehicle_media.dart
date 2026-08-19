// Safe public limousine vehicle photography. The car is the hero: contain
// the full vehicle and never crop it to a low fixed strip.

import 'dart:ui';

import 'package:flutter/material.dart';

/// Minimum rendered height for a limousine vehicle photograph.
const double kLimousineVehiclePhotoMinHeight = 220;

/// Discovery / showroom tablet photo share of a horizontal card.
const double kLimousineVehiclePhotoTabletFlex = 0.56;

const Key kLimousineVehiclePhotoContainKey = ValueKey<String>(
  'limousine_vehicle_photo_contain',
);
const Key kLimousineVehiclePhotoPlaceholderKey = ValueKey<String>(
  'limousine_vehicle_photo_placeholder',
);

bool limousineVehicleMediaUsesContainStrategy({
  required double minHeight,
  required BoxFit photoFit,
}) {
  return minHeight >= kLimousineVehiclePhotoMinHeight &&
      photoFit == BoxFit.contain;
}

class LimousineContainPhoto extends StatelessWidget {
  const LimousineContainPhoto({
    super.key,
    required this.imageUrl,
    required this.background,
    this.borderRadius = 18,
    this.minHeight = kLimousineVehiclePhotoMinHeight,
    this.aspectRatio = 16 / 10,
    this.placeholderLabel = '',
    this.gold = const Color(0xFFC9A227),
  });

  final String imageUrl;
  final Color background;
  final double borderRadius;
  final double minHeight;
  final double aspectRatio;
  final String placeholderLabel;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final height = minHeight < kLimousineVehiclePhotoMinHeight
        ? kLimousineVehiclePhotoMinHeight
        : minHeight;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: background,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: imageUrl.isEmpty
                ? _placeholder()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      ColoredBox(color: Colors.black.withOpacity(0.38)),
                      Image.network(
                        imageUrl,
                        key: kLimousineVehiclePhotoContainKey,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              color: gold,
                              strokeWidth: 2,
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => _placeholder(),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    final letter = placeholderLabel.trim().isEmpty
        ? ''
        : placeholderLabel.trim().substring(0, 1).toUpperCase();
    return KeyedSubtree(
      key: kLimousineVehiclePhotoPlaceholderKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              background,
              gold.withOpacity(0.16),
            ],
          ),
        ),
        child: Center(
          child: letter.isEmpty
              ? Icon(
                  Icons.directions_car_filled_outlined,
                  color: gold,
                  size: 42,
                )
              : Text(
                  letter,
                  style: TextStyle(
                    color: gold,
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
