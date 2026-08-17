import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_accepted_booking.dart';
import 'limousine_accepted_booking_resume_labels.dart';

class LimousineAcceptedBookingContinueAction extends StatelessWidget {
  const LimousineAcceptedBookingContinueAction({
    super.key,
    required this.language,
    required this.onContinue,
    this.onDiscard,
  });

  final AppLanguage language;
  final VoidCallback onContinue;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(kLimousineAcceptedBookingResumeHint.of(language)),
        const SizedBox(height: 8),
        FilledButton(
          key: kLimousineAcceptedBookingContinueKey,
          onPressed: onContinue,
          child: Text(kLimousineAcceptedBookingContinue.of(language)),
        ),
        if (onDiscard != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: kLimousineAcceptedBookingDiscardKey,
              onPressed: onDiscard,
              child: Text(kLimousineAcceptedBookingDiscard.of(language)),
            ),
          ),
      ],
    );
  }
}
