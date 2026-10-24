enum PrivateChauffeurSetupIssue { pricingModeRequired, tariffRequired }

/// A manual quote needs no tariff. Automatic pricing needs its own complete
/// tariff and must never borrow the taxi tariff.
PrivateChauffeurSetupIssue? validatePrivateChauffeurSetup({
  required bool offered,
  required String pricingMode,
  required bool tariffValid,
}) {
  if (!offered) return null;
  if (pricingMode != 'quote_required' && pricingMode != 'calculator') {
    return PrivateChauffeurSetupIssue.pricingModeRequired;
  }
  if (pricingMode == 'calculator' && !tariffValid) {
    return PrivateChauffeurSetupIssue.tariffRequired;
  }
  return null;
}
