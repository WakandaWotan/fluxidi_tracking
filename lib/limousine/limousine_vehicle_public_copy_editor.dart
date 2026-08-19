import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_vehicle_public_copy.dart';

class LimousineVehiclePublicCopyDialog extends StatefulWidget {
  const LimousineVehiclePublicCopyDialog({
    super.key,
    required this.initial,
    required this.language,
    required this.primaryLang,
    this.backgroundColor,
  });

  final Map<String, String> initial;
  final AppLanguage language;
  final String primaryLang;
  final Color? backgroundColor;

  @override
  State<LimousineVehiclePublicCopyDialog> createState() =>
      _LimousineVehiclePublicCopyDialogState();
}

class _LimousineVehiclePublicCopyDialogState
    extends State<LimousineVehiclePublicCopyDialog> {
  late final Map<String, TextEditingController> _controllers;

  String _t(LocalizedText text) => text.of(widget.language);

  @override
  void initState() {
    super.initState();
    final initial = limousinePublicCopyLocalizedOf(widget.initial);
    _controllers = <String, TextEditingController>{
      for (final lang in kLimousinePublicCopyLanguages)
        lang: TextEditingController(text: initial[lang] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> _value() {
    return limousineClampPublicCopy(<String, String>{
      for (final lang in kLimousinePublicCopyLanguages)
        lang: _controllers[lang]!.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryLang;
    return AlertDialog(
      key: kLimousineVehiclePublicCopyDialogKey,
      backgroundColor: widget.backgroundColor,
      title: Text(_t(kLimousineBusinessSetupEditPublicDetails)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t(kLimousineBusinessSetupVehiclePublicCopyHint),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _field(primary, key: kLimousineVehiclePublicCopyFieldKey),
              ExpansionTile(
                key: kLimousineVehiclePublicCopyOtherLanguagesKey,
                title: Text(_t(kLimousineBusinessSetupOtherLanguages)),
                children: [
                  for (final lang in kLimousinePublicCopyLanguages)
                    if (lang != primary) _field(lang),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: kLimousineVehiclePublicCopyCancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t(kLimousineBusinessSetupLeaveCancel)),
        ),
        FilledButton(
          key: kLimousineVehiclePublicCopySaveKey,
          onPressed: () => Navigator.of(context).pop(_value()),
          child: Text(_t(kLimousineBusinessSetupSave)),
        ),
      ],
    );
  }

  Widget _field(String lang, {Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key ?? limousineVehiclePublicCopyLangFieldKey(lang),
        controller: _controllers[lang],
        minLines: 3,
        maxLines: 6,
        maxLength: kLimousineVehiclePublicDescriptionMaxChars,
        decoration: InputDecoration(
          labelText:
              '${_t(kLimousineBusinessSetupVehiclePublicCopyField)} (${lang.toUpperCase()})',
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
