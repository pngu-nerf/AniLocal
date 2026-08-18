import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../window_chrome.dart';
import 'brand_wordmark.dart';
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

/// The bevel primitive every XP control is built from: a 2-px double 3D border
/// (an outer extreme pair + an inner mild pair) over a face color/gradient.
/// [raised] pops it out (lit top-left, shadowed bottom-right); `false` sinks it
/// in (the inverse) for wells, pressed buttons, and inset panels.
///
/// Square corners by design — the authentic chunky look, and it sidesteps
/// Flutter's "no per-side colors with a border radius" limit. Rounded corners
/// (dialogs) are handled separately by [XpDialog].
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

/// The chassis SURFACE that content sits on inside the instrument chrome
/// (`AppShell`, [XpDialog]). It's a flat [Material] carrying the chassis
/// [color], NOT a bare [ColoredBox] — so `ListTile`/ink widgets inside have a
/// real [Material] to paint their background + splashes on. (A [ColoredBox]
/// between a `ListTile` and the far Material hid that paint and tripped the
/// framework's "ListTile background color or ink splashes may be invisible"
/// warning; the Material here is the one-place root-cause fix.)
///
/// Kept visually IDENTICAL to the old `ColoredBox`: [MaterialType.canvas] with
/// NO elevation/shadow and no M3 tint, and ink splashes/highlights/hover are
/// suppressed for descendants — the Material is for correctness, not to add
/// ripples, so the flat/matte VFD look is unchanged. (Menus/overlays render
/// outside this subtree, so their own hover feedback is untouched.)
class XpChassis extends StatelessWidget {
  const XpChassis({super.key, required this.child, this.color = Xp.frame});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      type: MaterialType.canvas,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: child,
      ),
    );
  }
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
    this.lit = false,
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

  /// ARMED: the legend (icon + label) lights cyan phosphor ([Xp.accent]) on the
  /// matte chassis face — the SC-CH900 "active button" look, for a transient
  /// armed affordance (e.g. Skip Intro / Play Next while available).
  final bool lit;

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
          color: enabled ? (widget.lit ? Xp.accent : Xp.text) : Xp.textFaint,
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
              color: enabled
                  ? (widget.lit ? Xp.accent : Xp.text)
                  : Xp.textFaint,
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

/// The window title bar (the native macOS one is hidden — see
/// `MainFlutterWindow.swift`). Left to right:
///
///   [traffic lights] [AniLocal brand mark] [back / reserved blank]
///       … [—— VFD screen, centred on the WINDOW ——] …   [trailing actions]
///
/// Three things make this the instrument face rather than a toolbar:
/// - **Branding is chassis, not screen.** The `BrandWordmark` is a molded chrome
///   logo printed on the header body, just right of the traffic lights. The
///   black screen ([captionWidget], normally a `HeaderReadout`) is left to show
///   only the CONTEXT — "LIBRARY", a show title.
/// - **The screen is centred on the window's midpoint and symmetric**, at every
///   width — see [_HeaderCenterDelegate], which is where that rule lives.
/// - **Back sits with the brand**, and the screen keeps its place on screens
///   with no back action because the caller reserves the slot (see `XpScreen`).
///
/// **Window chrome:** everything that isn't a button behaves like a real title
/// bar — drag to move, double-click to zoom. A full-bleed [WindowDragArea] sits
/// UNDER everything for the bare chassis, and the VFD screen gets that same
/// [WindowDragArea] wrapped directly around it (see [_brandedRow]) so the
/// largest non-button target in the bar is unambiguously part of the chrome. The
/// button clusters stay OUTSIDE any drag area, so their taps aren't deferred
/// (~300ms) by the double-tap recognizer; the brand mark is an [IgnorePointer],
/// so the chassis under it drags too.
class XpTitleBar extends StatelessWidget {
  const XpTitleBar({
    super.key,
    required this.caption,
    this.captionWidget,
    this.leading,
    this.trailing,
  });

  /// Whether the header spells itself out at the current window width: tabs
  /// show text labels, and the brand mark is the full wordmark rather than its
  /// initials.
  ///
  /// The ONE place this decision is made. Every part of the header — the back
  /// tab, the action tabs, a screen's own tab, the brand — reads it, so the bar
  /// contracts as a single piece instead of in stages, and re-tuning the point
  /// is a change in one place. (That point is still [Xp.headerLabelWidth], a
  /// flat window-width constant; a threshold derived from the actual labelled
  /// cluster widths — which would fix its blindness to tab count — is diagnosed
  /// and pending.)
  static bool showsLabels(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= Xp.headerLabelWidth;

  final String caption;

  /// Overrides the default [caption] rendering — normally the VFD
  /// `HeaderReadout`. In the standard layout this is the centred screen, and it
  /// is given a TIGHT width (it must fill what it's handed, not size to text).
  final Widget? captionWidget;

  /// Optional leading control — the back button, placed just right of the brand
  /// mark. Callers that have no back action should pass a size-preserving blank
  /// so the screen doesn't shift between screens.
  final Widget? leading;

  /// Optional actions/status shown at the trailing edge (app buttons, a scan
  /// spinner).
  final Widget? trailing;

  /// Between the brand mark and the back button.
  static const double _brandGap = 12;

  /// Between the trailing actions and the window edge.
  static const double _trailingGap = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Xp.titleBarHeight,
      decoration: const BoxDecoration(gradient: Xp.titleGradient),
      child: Column(
        children: [
          // The bright 1px sheen line across the very top — the "Luna" gloss.
          Container(height: 1, color: Xp.titleGloss),
          Expanded(child: _brandedRow(showsLabels(context))),
        ],
      ),
    );
  }

  Widget _brandedRow(bool showLabels) {
    // LEFT cluster: traffic-light inset + brand + back slot. Stretch so the back
    // tab HANGS full-height like the trailing tabs; the brand is centred so it
    // keeps its own height.
    final left = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fixed inset clearing the traffic lights, which float over the bar.
        const SizedBox(width: kTrafficLightInset),
        // Decorative: IgnorePointer so the chassis under the logo stays
        // draggable (a text render box would otherwise absorb the pointer).
        Center(
          child: IgnorePointer(child: BrandWordmark(abbreviated: !showLabels)),
        ),
        if (leading != null) ...[const SizedBox(width: _brandGap), leading!],
      ],
    );
    final right = trailing == null
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              trailing!,
              const SizedBox(width: _trailingGap),
            ],
          );

    return ClipRect(
      child: Stack(
        children: [
          // Under everything: any bare chassis drags the window.
          Positioned.fill(
            child: WindowDragArea(child: const SizedBox.expand()),
          ),
          Positioned.fill(
            child: CustomMultiChildLayout(
              delegate: _HeaderCenterDelegate(),
              children: [
                LayoutId(id: _HeaderSlot.left, child: left),
                LayoutId(
                  id: _HeaderSlot.center,
                  // The screen is CHROME, not a control: it gets the same
                  // [WindowDragArea] as the bare chassis, so dragging it moves
                  // the window and double-clicking it zooms — identical to the
                  // rest of the non-button bar. Wrapped directly rather than
                  // left to fall through to the full-bleed layer beneath: the
                  // display is the biggest target in the bar, and its chrome
                  // behaviour shouldn't depend on every widget inside it
                  // happening to stay pointer-transparent.
                  child: WindowDragArea(
                    child:
                        captionWidget ??
                        Center(
                          child: ChromeLabel(
                            caption,
                            color: Xp.textOnTitle,
                            fontSize: 12,
                            letterSpacing: 1.5,
                          ),
                        ),
                  ),
                ),
                if (right != null)
                  LayoutId(id: _HeaderSlot.right, child: right),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _HeaderSlot { left, center, right }

/// Places the header's VFD screen **centred on the window's horizontal
/// midpoint, symmetrically**, between the two button clusters.
///
/// This is deliberately NOT "fill the gap between the clusters": the clusters
/// are different widths, so gap-filling would put the screen visibly off-centre.
/// Symmetry-about-the-window-centre wins. The half-width is therefore taken from
/// whichever cluster is CLOSER to the centre *right now*, and applied to both
/// sides — which leaves intentional empty chassis on the roomier side.
///
/// Which side constrains FLIPS with window width, so it is measured live rather
/// than assumed: wide, the right cluster (Sources/Sync/Settings with labels) is
/// the wider one; once the window narrows past [Xp.headerLabelWidth] those tabs
/// collapse to icons and the LEFT cluster (traffic lights + brand + back)
/// becomes the wider one. Both clusters are laid out first here, so the numbers
/// used are their actual rendered widths at this instant.
class _HeaderCenterDelegate extends MultiChildLayoutDelegate {
  /// Clear air kept between the screen and the nearer cluster.
  static const double margin = 10;

  /// Floor on the screen's width, below which it's too cramped to read. Bought
  /// by giving up [margin] first; past that the screen keeps shrinking rather
  /// than run under a cluster. (Keeping the floor reachable at ordinary window
  /// sizes is the job of the tab label/icon collapse — [Xp.headerLabelWidth].)
  static const double minScreenWidth = 132;

  @override
  void performLayout(Size size) {
    // Tight height so a cluster's tabs hang the full bar height. Width is left
    // UNBOUNDED so an absurdly cramped bar clips (the caller wraps this in a
    // ClipRect) instead of throwing a RenderFlex overflow.
    final cluster = BoxConstraints(
      minHeight: size.height,
      maxHeight: size.height,
    );
    var leftW = 0.0;
    var rightW = 0.0;
    if (hasChild(_HeaderSlot.left)) {
      leftW = layoutChild(_HeaderSlot.left, cluster).width;
      positionChild(_HeaderSlot.left, Offset.zero);
    }
    if (hasChild(_HeaderSlot.right)) {
      rightW = layoutChild(_HeaderSlot.right, cluster).width;
      positionChild(_HeaderSlot.right, Offset(size.width - rightW, 0));
    }
    if (!hasChild(_HeaderSlot.center)) return;

    final centerX = size.width / 2;
    // Distance from the window centre to whichever cluster is NEARER it. That
    // one number is the budget for BOTH sides — this is where "symmetric about
    // the window centre" beats "fill the gap".
    final room = math.min(centerX - leftW, centerX - rightW);
    var half = room - margin;
    if (2 * half < minScreenWidth) {
      // Too cramped: spend the clear-air margin before spending width, but
      // never past the nearer cluster. Symmetry is never traded away — a
      // centred screen that has shrunk (its text marquees, and it clips
      // cleanly) still reads right; an off-centre one never does.
      half = math.min(room, minScreenWidth / 2);
    }
    final width = math.max(0.0, 2 * half);
    // Tight width (the screen fills its allotment and measures its own text fit
    // against it), loose height so it keeps its own and can be centred.
    final screen = layoutChild(
      _HeaderSlot.center,
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: size.height),
    );
    positionChild(
      _HeaderSlot.center,
      Offset(centerX - width / 2, (size.height - screen.height) / 2),
    );
  }

  // Stateless rule — a rebuild can't change it. Cluster/screen resizes still
  // relayout: their children are laid out inside performLayout.
  @override
  bool shouldRelayout(_HeaderCenterDelegate old) => false;
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
