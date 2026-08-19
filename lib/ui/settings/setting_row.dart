import 'package:flutter/material.dart';

import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';

/// THE settings row. Every setting in the window is one of these — there is no
/// second row implementation, so alignment, spacing and type are decided once.
///
/// **Three tiers of information, so the window stays scannable:**
/// 1. [label] — always. Short, and states the ON condition positively; never
///    "Show / hide X".
/// 2. [subtitle] — ONLY when the setting isn't self-evident. One short line.
///    Omit it for obvious settings rather than padding them out; a subtitle on
///    every row is the wall of text this component exists to prevent.
/// 3. [info] — the ⓘ popover, for the fuller explanation and the edge cases.
///    Long copy goes HERE, never on the always-visible surface.
///
/// The [control] sits in a fixed-width right-hand column so switches, fields
/// and radio groups line up down the panel regardless of label length.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.subtitle,
    this.info,
    this.control,
    this.onTap,
  });

  final String label;

  /// One short line. Null (the default) for self-evident settings.
  final String? subtitle;

  /// Fuller explanation, shown in the ⓘ popover. Null = no ⓘ.
  final String? info;

  /// Switch / field / radio group, right-aligned in the control column.
  final Widget? control;

  /// Makes the whole row activate — for navigation and action rows.
  final VoidCallback? onTap;

  /// Reserved width for the control column. One constant so every row aligns.
  static const double controlColumn = 120;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: const TextStyle(color: Xp.text, fontSize: 13),
                      ),
                    ),
                    if (info != null) ...[
                      const SizedBox(width: 6),
                      SettingInfo(text: info!, label: label),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Xp.textDim, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (control != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: controlColumn),
              child: Align(alignment: Alignment.centerRight, child: control),
            ),
        ],
      ),
    );
    if (onTap == null) return body;
    return HoverTap(onTap: onTap!, child: body);
  }
}

/// A titled group of rows inside a panel. Purely visual grouping — the sidebar
/// does the navigating, so these never collapse.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ChromeLabel(
          title,
          color: Xp.textFaint,
          fontSize: 10,
          letterSpacing: 1.6,
        ),
      ),
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: Xp.divider),
        children[i],
      ],
      const SizedBox(height: 18),
    ],
  );
}

/// The switch used by every boolean setting, wearing the instrument palette
/// rather than the Material default. Tokens only.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Switch(
    value: value,
    onChanged: onChanged,
    // Lit cyan when on, dark chassis metal when off — the same
    // "sparse-lit against dark" rule the rest of the UI follows.
    thumbColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? Xp.accentBright : Xp.textDim,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? Xp.accentDeep : Xp.well,
    ),
    trackOutlineColor: const WidgetStatePropertyAll(Xp.bevelHiSoft),
  );
}

/// One option in a settings radio group.
class SettingRadio extends StatelessWidget {
  const SettingRadio({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => HoverTap(
    onTap: onSelected,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 16,
            color: selected ? Xp.accent : Xp.textFaint,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? Xp.text : Xp.textDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Tap + hover feedback without ink.
///
/// `XpChassis` deliberately suppresses splashes, highlights and hover for
/// everything inside it (the flat matte look), so an `InkWell` here would give
/// no feedback at all. This paints the hover itself with a token color.
class HoverTap extends StatefulWidget {
  const HoverTap({
    super.key,
    required this.onTap,
    required this.child,
    this.background = Xp.frame,
    this.hoverBackground = Xp.surfaceAlt,
  });

  final VoidCallback onTap;
  final Widget child;

  /// Resting fill — must match whatever surface the row sits on, since this
  /// paints its own background rather than compositing a translucent ink layer.
  final Color background;
  final Color hoverBackground;

  @override
  State<HoverTap> createState() => _HoverTapState();
}

class _HoverTapState extends State<HoverTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: ColoredBox(
        color: _hover ? widget.hoverBackground : widget.background,
        child: widget.child,
      ),
    ),
  );
}

/// The ⓘ affordance: a quiet glyph that opens a small popover with the full
/// explanation.
///
/// This is where depth lives. Anything longer than a one-line subtitle — edge
/// cases, warnings, "what does 0:00 do" — belongs in one of these rather than
/// inline, so the panel reads as a list of settings instead of a document.
///
/// Rendered through an [OverlayPortal] so the popover escapes the panel's
/// clip and scroll bounds, with a full-screen barrier behind it: a click
/// anywhere else dismisses, which is the only dismissal the popover needs.
class SettingInfo extends StatefulWidget {
  const SettingInfo({super.key, required this.text, required this.label});

  final String text;

  /// The owning row's label — used for the popover heading and the tooltip, so
  /// an opened popover always says what it is explaining.
  final String label;

  @override
  State<SettingInfo> createState() => _SettingInfoState();
}

class _SettingInfoState extends State<SettingInfo> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildPopover,
      child: HoverTap(
        onTap: _portal.toggle,
        background: Xp.frame,
        hoverBackground: Xp.frame,
        child: Tooltip(
          message: 'About “${widget.label}”',
          child: Icon(Icons.info_outline, size: 14, color: Xp.textFaint),
        ),
      ),
    ),
  );

  Widget _buildPopover(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _portal.hide,
        ),
      ),
      CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(-6, 8),
        // The follower is sized by the Stack, so the card needs its own
        // alignment + width bound or it would stretch the full overlay.
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: XpPanel(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChromeLabel(
                    widget.label,
                    color: Xp.textDim,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.text,
                    style: const TextStyle(
                      color: Xp.text,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
