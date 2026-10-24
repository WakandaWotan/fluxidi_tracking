import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';

/// Full-card role target: opaque hits, semantic button, Tab / Enter / Space.
class RoleEntryRoleCard extends StatefulWidget {
  const RoleEntryRoleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    required this.icon,
    required this.height,
    this.highlighted = false,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPressed;
  final IconData icon;
  final double height;
  final bool highlighted;
  final bool compact;

  @override
  State<RoleEntryRoleCard> createState() => _RoleEntryRoleCardState();
}

class _RoleEntryRoleCardState extends State<RoleEntryRoleCard> {
  bool _focused = false;
  bool _hovered = false;

  Color get _gold => appConfig.primaryColor;

  @override
  Widget build(BuildContext context) {
    const double normalFillOpacity = 0.09;
    const double activeFillOpacity = 0.14;
    const double normalBorderOpacity = 0.56;
    const double activeBorderOpacity = 0.76;
    const double normalGlowOpacity = 0.08;
    const double activeGlowOpacity = 0.15;
    final highlighted = widget.highlighted || _focused || _hovered;
    final fillOpacity = highlighted ? activeFillOpacity : normalFillOpacity;
    final borderOpacity = highlighted
        ? activeBorderOpacity
        : normalBorderOpacity;
    final glowOpacity = highlighted ? activeGlowOpacity : normalGlowOpacity;
    final double iconCircleSize = widget.compact ? 48.0 : 74.0;
    final double iconGlyphSize = widget.compact ? 26.0 : 40.0;
    final double iconRowGap = widget.compact ? 8.0 : 10.0;
    final double horizontalPadding = widget.compact ? 9.0 : 12.0;
    final double verticalPadding = widget.compact ? 6.0 : 8.0;
    final double titleFontSize = widget.compact ? 14.0 : 18.2;
    final double subtitleFontSize = widget.compact ? 9.6 : 10.8;
    final double chevronSize = widget.compact ? 16.0 : 21.0;
    final double chevronGap = widget.compact ? 2.0 : 4.0;
    final borderWidth = _focused ? 2.2 : (highlighted ? 1.4 : 1.0);

    return Semantics(
      button: true,
      enabled: true,
      excludeSemantics: true,
      focusable: true,
      focused: _focused,
      label: widget.title,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        descendantsAreFocusable: false,
        descendantsAreTraversable: false,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (show) {
          if (!mounted) return;
          setState(() => _focused = show);
        },
        onShowHoverHighlight: (show) {
          if (!mounted) return;
          setState(() => _hovered = show);
        },
        mouseCursor: SystemMouseCursors.click,
        child: Material(
          color: const Color(0xE60E1524),
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onPressed,
            canRequestFocus: false,
            excludeFromSemantics: true,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)) {
                return const Color(0xFFE5B641).withOpacity(0.16);
              }
              return null;
            }),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFFFFFF).withOpacity(fillOpacity),
                    const Color(0xFFFFFFFF).withOpacity(fillOpacity * 0.52),
                    const Color(0xFF111827).withOpacity(
                      highlighted ? 0.1 : 0.08,
                    ),
                  ],
                ),
                border: Border.all(
                  color: _gold.withOpacity(borderOpacity),
                  width: borderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withOpacity(glowOpacity),
                    blurRadius: highlighted ? 12 : 9,
                    spreadRadius: highlighted ? 0.26 : 0.12,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 9,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.06),
                    blurRadius: 2,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: iconCircleSize,
                          height: iconCircleSize,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827).withOpacity(0.08),
                            shape: BoxShape.circle,
                            border: Border.all(color: _gold.withOpacity(0.64)),
                          ),
                          child: Icon(
                            widget.icon,
                            color: _gold,
                            size: iconGlyphSize,
                          ),
                        ),
                        SizedBox(width: iconRowGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: const Color(0xFFFDFDFD),
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.15,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x8A000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: subtitleFontSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.14,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x70000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: chevronGap),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: _gold.withOpacity(0.98),
                          size: chevronSize,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
