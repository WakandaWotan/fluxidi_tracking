// Compile-time stamp so Christophe can see which Windows start copy is open.
// Filled by scripts/windows_start_env.ps1. Empty defines stay visible as unknown.

import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';

const String kFluxidiBuildTimeDefineKey = 'FLUXIDI_BUILD_TIME';
const String kFluxidiSourceRevisionDefineKey = 'FLUXIDI_SOURCE_REVISION';
const String kFluxidiSourceDirtyDefineKey = 'FLUXIDI_SOURCE_DIRTY';

const String kFluxidiBuildTimeDefine = String.fromEnvironment(
  kFluxidiBuildTimeDefineKey,
);
const String kFluxidiSourceRevisionDefine = String.fromEnvironment(
  kFluxidiSourceRevisionDefineKey,
);
const String kFluxidiSourceDirtyDefine = String.fromEnvironment(
  kFluxidiSourceDirtyDefineKey,
);

class FluxidiBuildStamp {
  const FluxidiBuildStamp({
    required this.kind,
    required this.builtAtRaw,
    required this.sourceRevision,
    required this.dirty,
  });

  final FluxidiRuntimeKind kind;
  final String builtAtRaw;
  final String sourceRevision;
  final bool dirty;

  String get environmentLabel => fluxidiWindowTitle(kind: kind);

  String get builtAtLabel => formatFluxidiBuildTime(builtAtRaw);

  String get revisionLabel {
    final rev = sourceRevision.trim();
    if (rev.isEmpty) return '';
    return dirty ? '$rev · lokale wijzigingen' : rev;
  }
}

bool fluxidiDefineIsDirty(String raw) {
  switch (raw.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    default:
      return false;
  }
}

String formatFluxidiBuildTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

FluxidiBuildStamp fluxidiBuildStamp({
  FluxidiRuntimeKind? kind,
  String runtimeEnv = kFluxidiRuntimeEnvDefine,
  String bookingBaseUrlOverride = kFluxidiRuntimeBookingBaseUrlOverride,
  String buildTime = kFluxidiBuildTimeDefine,
  String revision = kFluxidiSourceRevisionDefine,
  String dirty = kFluxidiSourceDirtyDefine,
}) {
  return FluxidiBuildStamp(
    kind:
        kind ??
        resolveFluxidiRuntimeKind(
          runtimeEnv: runtimeEnv,
          bookingBaseUrlOverride: bookingBaseUrlOverride,
        ),
    builtAtRaw: buildTime.trim(),
    sourceRevision: revision.trim(),
    dirty: fluxidiDefineIsDirty(dirty),
  );
}
