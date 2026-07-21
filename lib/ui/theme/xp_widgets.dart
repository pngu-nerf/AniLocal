import 'package:flutter/material.dart';

import '../window_chrome.dart';
import 'vfd_readout.dart';
import 'xp_tokens.dart';

/// A CHROME label — the thin, tracked-out, matte UPPERCASE text "screen-printed
/// on the chassis" (screen titles, section headers, button/tab labels). Uses
/// [Xp.chrome]; renders UPPERCASE but keeps the original-case string as its
/// [Semantics] label (screen readers + tests). Deliberately distinct from the
/// lit dot-matrix readouts ([VfdReadout]) and from body running text — it reads
/// as printed on the metal, not lit.
class ChromeLabel extends StatelessWidget {
  const ChromeLabel(
    this.text, {
    super.key,
    this.color = Xp.text,
    this.fontSize = 12,
    this.letterSpacing = 2,
    this.weight = FontWeight.w300,
    this.maxLines = 1,
    this.height = 1.1,
    this.upper = true,
  });

  final String text;
  final Color color;
  final double fontSize;
  final double letterSpacing;
  final FontWeight weight;

  /// Allow a multi-line chrome title (e.g. a show name); still ellipsizes.
  final int maxLines;

  /// Line height — pass the caller's own to preserve a tuned fixed-height block.
  final double height;

  /// Uppercase the text (the default chrome look for UI labels). Content titles
  /// / episode names pass `false` to keep the chrome treatment (thin, tracked,
  /// matte) while preserving readable mixed case.
  final bool upper;

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    // Replace the child Text's own semantics with the original-case label —
    // screen readers get the real string and finders match it (matters most
    // when [upper] is true).
    excludeSemantics: true,
    child: Text(
      upper ? text.toUpperCase() : text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Xp.chrome(
        fontSize: fontSize,
        color: color,
        weight: weight,
        letterSpacing: letterSpacing,
        height: height,
      ),
    ),
  );
}

/// The app WORDMARK — a cream serif rendering of the app name (branding ONLY,
/// never arbitrary text). Its own role, distinct from chrome/body/display.
class Wordmark extends StatelessWidget {
  const Wordmark(this.text, {super.key, this.fontSize = 15});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: Xp.wordmarkFont,
      fontFamilyFallback: Xp.wordmarkFallback,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: Xp.wordmark,
    ),
  );
}

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
          // Button text is CHROME — tracked-out matte caps, printed on the key.
          final text = Text(
            widget.label!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Xp.chrome(
              fontSize: dense ? 11 : 12,
              color: enabled ? Xp.text : Xp.textFaint,
              letterSpacing: dense ? 1.2 : 1.6,
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
                  // The caption is a CHROME label — a section header: matte
                  // cream tracked-caps, printed on the chassis. NOT the lit
                  // cyan dot-matrix (reserved for time/counters/status).
                  child: ChromeLabel(title),
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
  const XpTitleBar({
    super.key,
    required this.caption,
    this.captionWidget,
    this.leading,
    this.trailing,
  });

  final String caption;

  /// Overrides the default [caption] rendering — used to show the serif
  /// [Wordmark] on the home window instead of a chrome label.
  final Widget? captionWidget;

  /// Optional leading control (e.g. a back button on a pushed screen), placed
  /// AFTER the traffic-light inset and BEFORE the caption. Rendered outside the
  /// [WindowDragArea] so its taps aren't deferred by the drag recognizer.
  final Widget? leading;

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
                // Optional leading control (back button), past the traffic
                // lights and outside the drag area so its taps aren't deferred.
                ?leading,
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
                          // Default: a CHROME caption (tracked matte caps on the
                          // flat metal). The home window overrides with a serif
                          // [Wordmark] via [captionWidget].
                          Expanded(
                            child:
                                captionWidget ??
                                ChromeLabel(
                                  caption,
                                  color: Xp.textOnTitle,
                                  fontSize: 12,
                                  letterSpacing: 1.5,
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
    this.captionWidget,
    this.titleLeading,
    this.titleTrailing,
  });

  final String caption;
  final Widget child;

  /// Overrides the default caption rendering (e.g. the serif [Wordmark]).
  final Widget? captionWidget;
  final Widget? titleLeading;
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
              XpTitleBar(
                caption: caption,
                captionWidget: captionWidget,
                leading: titleLeading,
                trailing: titleTrailing,
              ),
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

/// One binder-style tab for the title bar: an icon + optional title on a raised
/// XP bevel that hangs from just below the top sheen down to the bar's bottom
/// edge, so a row of them reads as folder tabs. Built from [XpBevel] +
/// [Xp.controlGradient], so it warms on hover and depresses on press exactly
/// like every other control. Used for the homepage's title actions AND a pushed
/// screen's back / settings controls, so both title bars match.
class XpTitleTab extends StatefulWidget {
  const XpTitleTab({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.showLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;

  /// Whether to show the title beside the icon. Collapses to icon-only on a
  /// very narrow window.
  final bool showLabel;
  final VoidCallback? onPressed;

  @override
  State<XpTitleTab> createState() => _XpTitleTabState();
}

class _XpTitleTabState extends State<XpTitleTab> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = _down && enabled;
    final color = enabled ? Xp.text : Xp.textFaint;

    final tab = XpBevel(
      raised: !pressed,
      gradient: enabled
          ? Xp.controlGradient(hover: _hover)
          : const LinearGradient(colors: [Xp.surface, Xp.surface]),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 14, color: color),
            if (widget.showLabel) ...[
              const SizedBox(width: 5),
              // Tab labels are CHROME — tracked-out matte caps.
              Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Xp.chrome(
                  fontSize: 12,
                  color: color,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      // Hang from just below the sheen; flush at the bottom so it meets the
      // content. A 2px left gap separates adjacent tabs.
      padding: const EdgeInsets.only(top: 3, left: 2),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: widget.onPressed,
          child: Tooltip(message: widget.tooltip, child: tab),
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
