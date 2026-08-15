import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_color_rail.dart';

const Key kBrandSignatureStyleDockKey = Key('brand_signature_style_dock');
const Key kBrandSignatureStyleEditorAbsorbKey = Key(
  'brand_signature_style_editor_absorb',
);
const Key kBrandSignatureResetDefaultKey = Key('brand_signature_reset_default');
const Key kBrandSignatureStyleApplyKey = Key('brand_signature_style_apply');
const Key kBrandSignatureStyleCancelKey = Key('brand_signature_style_cancel');
const Key kBrandSignatureFamilySwatchKey = Key('brand_signature_family_swatch');
const Key kBrandSignatureHexFieldKey = Key('brand_signature_hex_field');
const Key kBrandSignatureHexValueKey = Key('brand_signature_hex_value');

class BrandSignatureStyleController {
  const BrandSignatureStyleController({
    required this.paletteListenable,
    required this.onPreviewColor,
    required this.onApply,
    required this.onCancel,
  });

  final ValueListenable<BrandSignaturePalette> paletteListenable;
  final void Function(Color color) onPreviewColor;
  final Future<void> Function(BrandSignaturePalette palette) onApply;
  final VoidCallback onCancel;
}

final BrandSignatureStyleController kBusinessBrandSignatureStyleController =
    BrandSignatureStyleController(
      paletteListenable: brandSignaturePaletteNotifier,
      onPreviewColor: previewBrandSignatureColor,
      onApply: applyBrandSignaturePalette,
      onCancel: cancelBrandSignaturePalettePreview,
    );

class BrandSignatureStyleScope extends InheritedWidget {
  const BrandSignatureStyleScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final BrandSignatureStyleController controller;

  static BrandSignatureStyleController of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<BrandSignatureStyleScope>()
            ?.controller ??
        kBusinessBrandSignatureStyleController;
  }

  @override
  bool updateShouldNotify(BrandSignatureStyleScope oldWidget) =>
      oldWidget.controller != controller;
}

Future<void> showBrandSignatureStyleEditor(
  BuildContext context, {
  BrandSignatureStyleController? controller,
}) async {
  final host = controller ?? kBusinessBrandSignatureStyleController;
  host.onPreviewColor(host.paletteListenable.value.base);
  final applied = await Navigator.of(context).push<bool>(
    BrandSignatureStyleEditorRoute(styleController: host),
  );
  if (applied != true) {
    host.onCancel();
  }
}

Future<void> showBrandSignaturePaletteSheet(BuildContext context) =>
    showBrandSignatureStyleEditor(context);

class BrandSignatureStyleEditorRoute extends PageRoute<bool> {
  BrandSignatureStyleEditorRoute({
    this.styleController,
  }) : super(fullscreenDialog: true);

  final BrandSignatureStyleController? styleController;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return BrandSignatureStyleEditor(controller: styleController);
  }
}

class BrandSignatureStyleEditor extends StatelessWidget {
  const BrandSignatureStyleEditor({super.key, this.controller});

  final BrandSignatureStyleController? controller;

  @override
  Widget build(BuildContext context) {
    final host = controller ?? kBusinessBrandSignatureStyleController;
    return BrandSignatureStyleScope(
      controller: host,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        host.onCancel();
        Navigator.of(context).pop(false);
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned.fill(
              child: AbsorbPointer(
                key: kBrandSignatureStyleEditorAbsorbKey,
                child: SizedBox.expand(),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: BrandSignatureStyleDock(controller: host),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class BrandSignatureStyleDock extends StatefulWidget {
  const BrandSignatureStyleDock({super.key, this.controller});

  final BrandSignatureStyleController? controller;

  @override
  State<BrandSignatureStyleDock> createState() =>
      _BrandSignatureStyleDockState();
}

class _BrandSignatureStyleDockState extends State<BrandSignatureStyleDock> {
  late final TextEditingController _hexController;
  final FocusNode _hexFocus = FocusNode();
  late final BrandSignatureStyleController _host;

  @override
  void initState() {
    super.initState();
    _host = widget.controller ?? kBusinessBrandSignatureStyleController;
    _hexController = TextEditingController(
      text: _host.paletteListenable.value.hex,
    );
    _host.paletteListenable.addListener(_syncHexFromPalette);
  }

  @override
  void dispose() {
    _host.paletteListenable.removeListener(_syncHexFromPalette);
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _syncHexFromPalette() {
    if (!mounted || _hexFocus.hasFocus) return;
    final hex = _host.paletteListenable.value.hex;
    if (_hexController.text.toUpperCase() != hex) {
      _hexController.value = TextEditingValue(
        text: hex,
        selection: TextSelection.collapsed(offset: hex.length),
      );
    }
  }

  void _onHexChanged(String raw) {
    final parsed = parseBrandSignatureHex(raw);
    if (parsed == null) return;
    _host.onPreviewColor(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: _host.paletteListenable,
      builder: (context, colors, _) {
        final chrome = brandSignatureBusinessPalette(colors);
        final hsv = colors.hsv;
        final maxH = MediaQuery.sizeOf(context).height * 0.62;
        final fieldH = MediaQuery.sizeOf(context).shortestSide < 520
            ? 120.0
            : 168.0;
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Material(
            key: kBrandSignatureStyleDockKey,
            color: chrome.surface.withOpacity(0.97),
            elevation: 10,
            shadowColor: const Color(0x66000000),
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      brandSignatureRailTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: chrome.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          key: kBrandSignatureFamilySwatchKey,
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: colors.base,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.border),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            brandSignatureFamilyLabel(colors.familyId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: chrome.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          colors.hex,
                          key: kBrandSignatureHexValueKey,
                          style: TextStyle(
                            color: chrome.textPrimary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: fieldH,
                      width: double.infinity,
                      child: BrandSignatureSvField(
                        hsv: hsv,
                        onChanged: (next) =>
                            _host.onPreviewColor(next.toColor()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: kBrandSignatureColorRailMinHeight,
                      width: double.infinity,
                      child: BrandSignatureColorRail(
                        hue: hsv.hue,
                        onHueChanged: (hue) => _host.onPreviewColor(
                          HSVColor.fromAHSV(
                            1,
                            hue,
                            hsv.saturation,
                            hsv.value,
                          ).toColor(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry
                            in kBrandSignatureNeutralShortcuts.entries)
                          _NeutralChip(
                            id: entry.key,
                            color: entry.value,
                            selected: colors.base == entry.value,
                            onPreview: _host.onPreviewColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: kBrandSignatureHexFieldKey,
                      controller: _hexController,
                      focusNode: _hexFocus,
                      maxLength: 7,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9a-fA-F]'),
                        ),
                      ],
                      style: TextStyle(
                        color: chrome.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        labelText: 'HEX',
                        labelStyle: TextStyle(color: chrome.textMuted),
                      ),
                      onChanged: _onHexChanged,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: kBrandSignatureResetDefaultKey,
                        onPressed: () => _host.onPreviewColor(
                          kBrandSignatureDefaultBase,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: kBrandSignatureGoldAccent,
                        ),
                        child: Text(brandSignatureResetDefaultLabel()),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: kBrandSignatureStyleCancelKey,
                            onPressed: () {
                              _host.onCancel();
                              Navigator.of(context).pop(false);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: chrome.textPrimary,
                              side: const BorderSide(
                                color: kBrandSignatureGoldAccent,
                              ),
                            ),
                            child: Text(businessThemeSelectorCancelLabel()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            key: kBrandSignatureStyleApplyKey,
                            onPressed: () async {
                              await _host.onApply(colors);
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: kBrandSignatureGoldAccent,
                              foregroundColor: const Color(0xFF1A1408),
                            ),
                            child: Text(businessThemeSelectorApplyLabel()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NeutralChip extends StatelessWidget {
  const _NeutralChip({
    required this.id,
    required this.color,
    required this.selected,
    required this.onPreview,
  });

  final String id;
  final Color color;
  final bool selected;
  final ValueChanged<Color> onPreview;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? kBrandSignatureGoldAccent : const Color(0x66000000),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: Key('brand_signature_neutral_$id'),
        onTap: () => onPreview(color),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            brandSignatureFamilyLabel(id),
            style: TextStyle(
              color: brandSignatureReadableTextOn(color),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
