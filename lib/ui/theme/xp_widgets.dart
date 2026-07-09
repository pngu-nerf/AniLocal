import 'package:flutter/material.dart';

import '../window_chrome.dart';
import 'xp_tokens.dart';

/// The bevel primitive every XP control is built from: a 2-px double 3D border
/// (an outer extreme pair + an inner mild pair) over a face color/gradient.
/// [raised] pops it out (lit top-left, shadowed bottom-right); `false` sinks it
/// in (the inverse) for wells, pressed buttons, and inset panels.
///
/// Square corners by design — the authentic chunky look, and it sidesteps
/// Flutter's "no per-side colors with a border radius" limit. Rounded corners
/// (the window) are handled separately by [XpWindow].
class XpBevel extends StatelessWidget {
  const XpBevel({
    super.key,
    required this.child,
    this.raised = true,
    this.gradient,
    this.color,
    this.padding,
  });

  final Widget child;
  final bool raised;
  final Gradient? gradient;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  static Border _ring({required Color topLeft, required Color bottomRight}) =>
      Border(
        top: BorderSide(color: topLeft, width: Xp.bevel),
        left: BorderSide(color: topLeft, width: Xp.bevel),
        right: BorderSide(color: bottomRight, width: Xp.bevel),
        bottom: BorderSide(color: bottomRight, width: Xp.bevel),
      );

  @override
  Widget build(BuildContext context) {
    final outer = raised
        ? _ring(topLeft: Xp.bevelHiSoft, bottomRight: Xp.bevelLo)
        : _ring(topLeft: Xp.bevelLoSoft, bottomRight: Xp.bevelHiSoft);
    final inner = raised
        ? _ring(topLeft: Xp.bevelHi, bottomRight: Xp.bevelLoSoft)
        : _ring(topLeft: Xp.bevelLo, bottomRight: Xp.bevelHi);
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    return DecoratedBox(
      decoration: BoxDecoration(border: outer),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: inner,
          gradient: gradient,
          color: gradient == null ? (color ?? Xp.surface) : null,
        ),
        child: content,
      ),
    );
  }
}

/// A raised or inset beveled panel — the chrome container for groups of content.
class XpPanel extends StatelessWidget {
  const XpPanel({
    super.key,
    required this.child,
    this.inset = false,
    this.padding,
    this.color,
  });

  final Widget child;
  final bool inset;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => XpBevel(
    raised: !inset,
    color: color ?? (inset ? Xp.well : Xp.surface),
    padding: padding,
    child: child,
  );
}

/// A tactile XP push button: beveled-out at rest, sinking in (and nudging its
/// label down-right 1px) when pressed, and warming on hover. Icon and/or label;
/// consumes only design tokens, so every button on the page matches.
class XpButton extends StatefulWidget {
  const XpButton({
    super.key,
    this.onPressed,
    this.icon,
    this.label,
    this.tooltip,
    this.selected = false,
    this.dense = false,
  });

  final VoidCallback? onPressed;
  final IconData? icon;
  final String? label;
  final String? tooltip;

  /// Drawn pre-pressed (sunken) — for a sticky/active toolbar state.
  final bool selected;

  /// Compact variant (smaller padding/type) for in-content affordances like a
  /// card's "Next episode" button.
  final bool dense;

  @override
  State<XpButton> createState() => _XpButtonState();
}

class _XpButtonState extends State<XpButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = (_down || widget.selected) && enabled;
    final dense = widget.dense;
    final children = <Widget>[
      if (widget.icon != null)
        Icon(
          widget.icon,
          size: dense ? 14 : 16,
          color: enabled ? Xp.text : Xp.textFaint,
        ),
      if (widget.icon != null && widget.label != null)
        SizedBox(width: dense ? 5 : 7),
      if (widget.label != null)
        // Dense buttons live in bounded-width slots (a card) → let the label
        // ellipsize. Toolbar buttons sit in an unbounded Wrap, where a Flexible
        // in a min-size Row would throw, so they size to their text.
        () {
          final text = Text(
            widget.label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Xp.fontFamily,
              fontFamilyFallback: Xp.fontFallback,
              fontSize: dense ? 12 : 13,
              color: enabled ? Xp.text : Xp.textFaint,
            ),
          );
          return dense ? Flexible(child: text) : text;
        }(),
    ];

    Widget button = XpBevel(
      raised: !pressed,
      gradient: enabled
          ? Xp.controlGradient(hover: _hover)
          : const LinearGradient(colors: [Xp.surface, Xp.surface]),
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : Xp.controlPadding,
      child: Transform.translate(
        // The "depress" — content shifts into the sunken face when pressed.
        offset: pressed ? const Offset(1, 1) : Offset.zero,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: button,
      ),
    );
  }
}

/// An XP group box: a raised sub-panel with a slim caption strip and a sunken
/// content well — a little window-within-the-window. Used to frame the
/// continue-watching side panel.
class XpGroupBox extends StatelessWidget {
  const XpGroupBox({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return XpPanel(
      color: Xp.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Xp.fontFamily,
                      fontFamilyFallback: Xp.fontFallback,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Xp.accentBright,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: XpPanel(inset: true, child: child)),
        ],
      ),
    );
  }
}

/// The XP title bar: the glossy blue gradient caption with a 1px top sheen, an
/// app glyph, and the caption text. This is where the design spends its boldness.
///
/// It IS the window's real title bar now: the standard macOS one is hidden (see
/// `MainFlutterWindow.swift`). The caption region is a [WindowDragArea]
/// (click-drag moves the window, double-click zooms) and its leading content is
/// inset past the traffic lights, which float over its left edge. The old
/// ornamental min/restore/close pips are gone — the native traffic lights are
/// the real, and only, window controls now.
///
/// The optional [trailing] actions sit at the top-right OUTSIDE the drag area:
/// the double-tap-to-zoom recognizer would otherwise defer their single clicks
/// (~300ms), so only the caption/background is draggable, not the buttons.
class XpTitleBar extends StatelessWidget {
  const XpTitleBar({super.key, required this.caption, this.trailing});

  final String caption;

  /// Optional actions/status shown at the trailing edge (app buttons, a scan
  /// spinner). Rendered outside the [WindowDragArea] so taps aren't deferred.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Xp.titleBarHeight,
      decoration: const BoxDecoration(gradient: Xp.titleGradient),
      child: Column(
        children: [
          // The bright 1px sheen line across the very top — the "Luna" gloss.
          Container(height: 1, color: Xp.titleGloss),
          Expanded(
            child: Row(
              // Stretch so trailing actions can fill the bar's height and reach
              // its bottom edge (the "binder tab" look).
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fixed inset clearing the traffic lights — OUTSIDE the flexible
                // caption, so it never gets squeezed (and so can never overflow)
                // when wide trailing tabs shrink the caption slot.
                const SizedBox(width: kTrafficLightInset),
                // The caption is the draggable region and the ONLY thing that
                // yields when space is tight: its text ellipsizes, and on an
                // extremely narrow slot even the glyph drops — so the bar fits
                // any width without overflow.
                Expanded(
                  child: WindowDragArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          if (constraints.maxWidth > 40) ...[
                            const Icon(
                              Icons.tv,
                              size: 16,
                              color: Xp.textOnTitle,
                            ),
                            const SizedBox(width: 7),
                          ],
                          Expanded(
                            child: Text(
                              caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: Xp.fontFamily,
                                fontFamilyFallback: Xp.fontFallback,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Xp.textOnTitle,
                                shadows: [
                                  Shadow(
                                    color: Color(0x99000000),
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The window-chrome look: a blue active-window frame with rounded top corners,
/// an [XpTitleBar] on top, and the content below sitting on the chrome base.
class XpWindow extends StatelessWidget {
  const XpWindow({
    super.key,
    required this.caption,
    required this.child,
    this.titleTrailing,
  });

  final String caption;
  final Widget child;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    const topRadius = Radius.circular(Xp.windowRadius);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Xp.frameBlue,
        borderRadius: BorderRadius.vertical(top: topRadius),
      ),
      // The blue frame shows as a slim border on the sides + bottom; the title
      // bar covers the top, so no top padding.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Xp.frameWidth,
          0,
          Xp.frameWidth,
          Xp.frameWidth,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: topRadius),
          child: Column(
            children: [
              XpTitleBar(caption: caption, trailing: titleTrailing),
              Expanded(
                child: ColoredBox(color: Xp.frame, child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chunky XP scrollbar: a thick, always-visible square thumb over a sunken
/// track. (Beveled-thumb + arrow end-caps are a future deepening on the same
/// wrapper.)
class XpScrollbar extends StatelessWidget {
  const XpScrollbar({super.key, required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: Xp.scrollbarThickness,
      radius: Radius.zero,
      thumbColor: Xp.bevelHi,
      trackColor: Xp.well,
      trackBorderColor: Xp.divider,
      child: child,
    );
  }
}
