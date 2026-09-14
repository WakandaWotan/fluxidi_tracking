import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_about_labels.dart';
import 'package:fluxidi_tracking/fluxidi_build_stamp.dart';

const Key kFluxidiAboutThisAppKey = Key('fluxidi_about_this_app');
const Key kFluxidiAboutEnvironmentValueKey = Key(
  'fluxidi_about_environment_value',
);
const Key kFluxidiAboutBuiltAtValueKey = Key('fluxidi_about_built_at_value');
const Key kFluxidiAboutRevisionValueKey = Key('fluxidi_about_revision_value');

class FluxidiAboutThisApp extends StatelessWidget {
  const FluxidiAboutThisApp({super.key, required this.language, this.stamp});

  final AppLanguage language;
  final FluxidiBuildStamp? stamp;

  @override
  Widget build(BuildContext context) {
    final info = stamp ?? fluxidiBuildStamp();
    final theme = Theme.of(context);
    return Padding(
      key: kFluxidiAboutThisAppKey,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kFluxidiAboutThisAppTitle.of(language),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _AboutLine(
            label: kFluxidiAboutEnvironment.of(language),
            value: info.environmentLabel,
            valueKey: kFluxidiAboutEnvironmentValueKey,
          ),
          _AboutLine(
            label: kFluxidiAboutBuiltAt.of(language),
            value: _orUnknown(info.builtAtLabel, language),
            valueKey: kFluxidiAboutBuiltAtValueKey,
          ),
          _AboutLine(
            label: kFluxidiAboutSourceRevision.of(language),
            value: _orUnknown(info.revisionLabel, language),
            valueKey: kFluxidiAboutRevisionValueKey,
          ),
        ],
      ),
    );
  }

  String _orUnknown(String value, AppLanguage language) {
    return value.trim().isEmpty ? kFluxidiAboutUnknown.of(language) : value;
  }
}

class _AboutLine extends StatelessWidget {
  const _AboutLine({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, key: valueKey, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
