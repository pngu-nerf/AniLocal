import 'package:flutter/material.dart';

/// Hover, press, focus and semantics for ONE tappable chassis element.
///
/// Every custom control in the app — buttons, tabs, tiles, cards, list rows —
/// used to be its own `MouseRegion` + `GestureDetector` with its own idea of
/// feedback (an opacity dip, a background swap, a bevel depress). None was
/// focusable: Tab did nothing, Space and Enter did nothing, and a screen
/// reader announced every button as static text. This is the one wrapper they
/// all build on now, so keyboard and assistive access are a property of the
/// primitive rather than something each control remembers to add.
///
/// [builder] receives the live interaction state and draws the control; the
/// wrapper owns the pointer cursor, the hover/press/focus tracking, keyboard
/// activation (Enter / Space through `ActivateIntent`), and a
/// `Semantics(button: true)` node carrying [semanticsLabel] or the child's
/// own text.
class XpPressable extends StatefulWidget {
  const XpPressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.semanticsLabel,
    this.tooltip,
    this.opaque = true,
    this.canRequestFocus = true,
  });

  /// Null = disabled: no cursor change, no focus, no hover state, announced
  /// as disabled.
  final VoidCallback? onTap;

  final Widget Function(BuildContext context, XpPressState state) builder;

  /// Overrides the label a screen reader hears; defaults to the child's text.
  final String? semanticsLabel;
  final String? tooltip;

  /// Whether the whole box is a hit target even where it paints nothing
  /// (rows and cards want this; a tight bevelled button does not care).
  final bool opaque;

  /// A pressable that must stay OUT of the focus traversal (the player's
  /// control bar never holds keyboard focus — see the regression checklist).
  final bool canRequestFocus;

  @override
  State<XpPressable> createState() => _XpPressableState();
}

/// What the control is doing right now, for its painter.
class XpPressState {
  const XpPressState({
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
  });

  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
}

class _XpPressableState extends State<XpPressable> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  void _activate() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final state = XpPressState(
      enabled: enabled,
      hovered: _hover && enabled,
      pressed: _down && enabled,
      focused: _focus && enabled,
    );
    Widget child = widget.builder(context, state);
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        // Focus is only ever requested by the keyboard (Tab); a click keeps
        // focus where it was, like a native desktop button.
        focusNode: null,
        descendantsAreFocusable: false,
        descendantsAreTraversable: false,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        // `enabled: false` above already removes the node from traversal;
        // this keeps a deliberately non-focusable control out even when on.
        includeFocusSemantics: widget.canRequestFocus,
        child: widget.canRequestFocus
            ? _gesture(child, enabled)
            : ExcludeFocus(child: _gesture(child, enabled)),
      ),
    );
  }

  Widget _gesture(Widget child, bool enabled) => GestureDetector(
    behavior: widget.opaque
        ? HitTestBehavior.opaque
        : HitTestBehavior.deferToChild,
    onTapDown: enabled ? (_) => setState(() => _down = true) : null,
    onTapUp: enabled ? (_) => setState(() => _down = false) : null,
    onTapCancel: enabled ? () => setState(() => _down = false) : null,
    onTap: enabled ? _activate : null,
    child: child,
  );
}
