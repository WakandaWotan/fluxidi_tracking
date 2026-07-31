import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';

class DriverCreatorDialogStyle {
  const DriverCreatorDialogStyle({
    required this.sheetBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.inputFill,
    required this.inputBorder,
    required this.gold,
    required this.textOnAccent,
  });

  final Color sheetBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color inputFill;
  final Color inputBorder;
  final Color gold;
  final Color textOnAccent;
}

DriverCreatorDialogStyle driverCreatorDialogStyleFor(
  BusinessThemeVariant variant,
) {
  final palette = paletteForBusinessTheme(variant);
  final isClean = variant == BusinessThemeVariant.cleanProfessional;
  return DriverCreatorDialogStyle(
    sheetBg: isClean ? palette.surface : palette.surfaceAlt,
    textPrimary: palette.textPrimary,
    textSecondary: palette.textSecondary,
    inputFill: isClean
        ? palette.surfaceAlt.withOpacity(0.95)
        : const Color(0xFF0B0B0B),
    inputBorder: palette.border.withOpacity(isClean ? 0.8 : 0.44),
    gold: palette.accent,
    textOnAccent: palette.textOnAccent,
  );
}

String _localizedDriverCreatorLabel(
  AppLanguage lang, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (lang) {
    case AppLanguage.nl:
      return nl;
    case AppLanguage.en:
      return en;
    case AppLanguage.fr:
      return fr;
    case AppLanguage.es:
      return es;
    case AppLanguage.de:
      return en;
  }
}

Widget _driverCreatorTextField(
  TextEditingController controller,
  String label,
  DriverCreatorDialogStyle style, {
  bool enabled = true,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      enabled: enabled,
      style: TextStyle(
        color: enabled
            ? style.textPrimary
            : style.textPrimary.withOpacity(0.88),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: style.textSecondary),
        filled: true,
        fillColor: style.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.inputBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.inputBorder.withOpacity(0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: style.gold.withOpacity(0.7)),
        ),
      ),
    ),
  );
}

Future<DriverProfile?> showDriverCreatorDialog(
  BuildContext context, {
  DriverProfile? existing,
  String? companyId,
  DriverCreatorDialogStyle? style,
}) async {
  final resolvedStyle =
      style ?? driverCreatorDialogStyleFor(businessThemeNotifier.value);
  final lang = appConfig.currentLanguage;
  final isEdit = existing != null;
  final nameCtrl = TextEditingController(text: existing?.fullName ?? '');
  final idCtrl = TextEditingController(text: existing?.employeeNumber ?? '');
  final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
  final taxiCardNumberCtrl = TextEditingController(
    text: existing?.taxiDriverCardNumber ?? '',
  );
  final taxiCardExpiryCtrl = TextEditingController(
    text: existing?.taxiDriverCardExpiry ?? '',
  );
  DriverProfile? saved;
  final scopedCompanyId = (companyId ?? '').trim().isNotEmpty
      ? companyId!.trim()
      : resolveActiveCompanyIdForFleetUi();

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: resolvedStyle.sheetBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEdit
            ? _localizedDriverCreatorLabel(
                lang,
                nl: 'Chauffeur bewerken',
                en: 'Edit driver',
                fr: 'Modifier chauffeur',
                es: 'Editar conductor',
              )
            : _localizedDriverCreatorLabel(
                lang,
                nl: 'Chauffeur toevoegen',
                en: 'New driver',
                fr: 'Ajouter un chauffeur',
                es: 'Agregar conductor',
              ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _driverCreatorTextField(
              nameCtrl,
              _localizedDriverCreatorLabel(
                lang,
                nl: 'Naam',
                en: 'Name',
                fr: 'Nom',
                es: 'Nombre',
              ),
              resolvedStyle,
            ),
            _driverCreatorTextField(
              idCtrl,
              _localizedDriverCreatorLabel(
                lang,
                nl: 'Chauffeur-ID',
                en: 'Driver ID',
                fr: 'ID chauffeur',
                es: 'ID conductor',
              ),
              resolvedStyle,
              enabled: !isEdit,
            ),
            _driverCreatorTextField(
              phoneCtrl,
              _localizedDriverCreatorLabel(
                lang,
                nl: 'Telefoonnummer',
                en: 'Phone number',
                fr: 'Numéro de téléphone',
                es: 'Número de teléfono',
              ),
              resolvedStyle,
            ),
            _driverCreatorTextField(
              taxiCardNumberCtrl,
              _localizedDriverCreatorLabel(
                lang,
                nl: 'Kaartnummer',
                en: 'Card number',
                fr: 'N° carte',
                es: 'N.º tarjeta',
              ),
              resolvedStyle,
            ),
            _driverCreatorTextField(
              taxiCardExpiryCtrl,
              _localizedDriverCreatorLabel(
                lang,
                nl: 'Vervaldatum kaart',
                en: 'Card expiry',
                fr: 'Expiration carte',
                es: 'Vencimiento tarjeta',
              ),
              resolvedStyle,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _localizedDriverCreatorLabel(
                        lang,
                        nl: 'Annuleren',
                        en: 'Cancel',
                        fr: 'Annuler',
                        es: 'Cancelar',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final fullName = nameCtrl.text.trim();
                      final employeeNumber = idCtrl.text.trim();
                      if (!isEdit &&
                          (fullName.isEmpty || employeeNumber.isEmpty)) {
                        return;
                      }
                      if (isEdit) {
                        saved = existing.copyWith(
                          fullName: fullName,
                          phone: phoneCtrl.text.trim(),
                          taxiDriverCardNumber: taxiCardNumberCtrl.text.trim(),
                          taxiDriverCardExpiry: taxiCardExpiryCtrl.text.trim(),
                        );
                        updateDriver(existing.id, saved!);
                      } else {
                        saved = DriverProfile(
                          id: 'drv_${DateTime.now().millisecondsSinceEpoch}',
                          fullName: fullName,
                          employeeNumber: employeeNumber,
                          phone: phoneCtrl.text.trim(),
                          taxiDriverCardNumber: taxiCardNumberCtrl.text.trim(),
                          taxiDriverCardExpiry: taxiCardExpiryCtrl.text.trim(),
                          isActive: true,
                          companyId: scopedCompanyId,
                        );
                        addDriver(saved!);
                      }
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      isEdit
                          ? _localizedDriverCreatorLabel(
                              lang,
                              nl: 'Opslaan',
                              en: 'Save',
                              fr: 'Enregistrer',
                              es: 'Guardar',
                            )
                          : _localizedDriverCreatorLabel(
                              lang,
                              nl: 'Toevoegen',
                              en: 'Add',
                              fr: 'Ajouter',
                              es: 'Agregar',
                            ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return saved;
}
