// Phone ordinary Navigatie landscape banner placement (not Tellers, not tablet).

/// Extra inset below the safe top for collapsed ordinary-nav chrome.
///
/// Phone landscape sits tighter to the safe top so the route banner reads
/// higher in the map viewport. Portrait keeps the prior 8 lp inset.
double resolvePhoneOrdinaryNavCollapsedChromeTopInset({
  required bool isPhoneHost,
  required bool isLandscape,
}) {
  if (!isPhoneHost) {
    // Tablet collapsed chrome retains the prior landscape/portrait insets.
    return isLandscape ? 6.0 : 8.0;
  }
  if (isLandscape) return 2.0;
  return 8.0;
}

/// Absolute top for the collapsed ordinary-nav chrome row.
double resolvePhoneOrdinaryNavCollapsedChromeTop({
  required double safeTop,
  required bool isPhoneHost,
  required bool isLandscape,
}) {
  return safeTop +
      resolvePhoneOrdinaryNavCollapsedChromeTopInset(
        isPhoneHost: isPhoneHost,
        isLandscape: isLandscape,
      );
}
