/// HTTPS checks and cache-busting for company header images.
///
/// Reuses the saved public logo and cover URLs. Does not invent Taxi Mario
/// assets or a second upload slot.
library;

/// Remote company images must be https and must not be the platform mark.
bool customerAppHeaderImageIsUsable(String url) {
  final value = url.trim();
  if (!value.toLowerCase().startsWith('https://')) return false;
  if (value.toLowerCase().contains('fluxidi_logo')) return false;
  return true;
}

String customerAppHeaderNormalizedUrl(String url) => url.trim();

/// Appends or replaces `v=` so a replaced image is not stuck behind a cache
/// of the previous bytes at the same path.
String customerAppHeaderCacheBustedUrl(String url, {String revision = ''}) {
  final value = url.trim();
  if (value.isEmpty) return '';
  final parsed = Uri.tryParse(value);
  if (parsed == null || !parsed.hasScheme) return value;
  final stamp = revision.trim();
  if (stamp.isEmpty) return value;
  final params = Map<String, String>.from(parsed.queryParameters);
  params['v'] = stamp;
  return parsed.replace(queryParameters: params).toString();
}

/// Identity used as an [Image] key so Flutter drops a stale cached frame.
String customerAppHeaderImageKey(String url, {String revision = ''}) {
  final busted = customerAppHeaderCacheBustedUrl(url, revision: revision);
  return busted.isEmpty ? url.trim() : busted;
}
