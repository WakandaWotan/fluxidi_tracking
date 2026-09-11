// COMPANY-CUSTOMER-OPS-P0 — existing GET /company/subscription/profile, no checkout.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanySubscriptionStatusPageKey = Key(
  'company_subscription_status_page',
);

class CompanySubscriptionStatusPage extends StatefulWidget {
  const CompanySubscriptionStatusPage({
    super.key,
    this.language,
    this.profileLoader,
  });

  final AppLanguage? language;
  final Future<Map<String, dynamic>> Function()? profileLoader;

  @override
  State<CompanySubscriptionStatusPage> createState() =>
      _CompanySubscriptionStatusPageState();
}

class _CompanySubscriptionStatusPageState
    extends State<CompanySubscriptionStatusPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await (widget.profileLoader ??
          fetchCompanyOpsSubscriptionProfile)();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Abonnementsprofiel laden mislukt.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanySubscriptionStatusPageKey,
        appBar: AppBar(title: const Text('Abonnement')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Plan: ${(_profile['plan_code'] ?? _profile['planCode'] ?? _profile['status'] ?? '—')}',
                  ),
                  Text(
                    'Voertuiglimiet: ${companyOpsMaxVehicles(_profile)}',
                  ),
                  Text(
                    'Chauffeurslimiet: ${companyOpsMaxDrivers(_profile)}',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dit is het bestaande abonnementsprofiel. Checkout, extra voertuig kopen en Mollie-betalingen blijven de native facturatieketen en zijn hier niet gestart.',
                  ),
                ],
              ),
      ),
    );
  }
}
