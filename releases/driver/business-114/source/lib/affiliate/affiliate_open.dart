import 'package:flutter/material.dart';
import '../app_strings.dart';
import '../customer_phone_recovery_page.dart';
import 'affiliate_labels.dart';
import 'affiliate_page.dart';
import 'affiliate_repository.dart';

Future<void> openAffiliatePage(
  BuildContext context, {
  Future<void> Function(BuildContext)? onSignIn,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => AffiliatePage(
      repository: AffiliateRepository(),
      disposeRepository: true,
      onSignIn: onSignIn ?? _personalSignIn,
    ),
  ),
);

Future<void> _personalSignIn(BuildContext context) async {
  final result = await Navigator.of(context).push<Object?>(
    MaterialPageRoute<Object?>(
      builder: (_) => const CustomerPhoneRecoveryPage(),
    ),
  );
  if (!context.mounted) return;
  if (result == CustomerPhoneRecoveryPage.newCustomerResult) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(affiliateLabel('newAccount', appLanguageNotifier.value)),
      ),
    );
  }
  // Recovery saves only a genuine personal CustomerSession. Never change the
  // active company session, role or company-admin bearer in this entry.
}
