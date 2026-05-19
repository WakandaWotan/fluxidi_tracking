import 'package:flutter/material.dart';

class DirectRideEstimatePanel extends StatelessWidget {
  final bool visible;
  final double? estimatedFare;
  final bool isLoading;
  final String? error;
  final String currency;
  final String label;
  final String note;
  final String loadingText;
  final String unavailableText;
  final String Function(double amount, String currency) formatAmount;

  const DirectRideEstimatePanel({
    super.key,
    required this.visible,
    required this.estimatedFare,
    required this.isLoading,
    required this.error,
    required this.currency,
    required this.label,
    required this.note,
    required this.loadingText,
    required this.unavailableText,
    required this.formatAmount,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final estimateValue = estimatedFare != null
        ? formatAmount(estimatedFare!, currency)
        : null;
    final statusText = isLoading
        ? loadingText
        : (estimateValue ?? unavailableText);
    final valueIsEstimate = !isLoading && estimateValue != null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF090909).withOpacity(0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55E5B641)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_taxi_outlined,
                size: 14,
                color: Color(0xFFE5B641),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE5B641),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            maxLines: valueIsEstimate ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueIsEstimate ? const Color(0xFFFFD36A) : Colors.white70,
              fontSize: valueIsEstimate ? 15 : 11.5,
              fontWeight: valueIsEstimate ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.63),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
