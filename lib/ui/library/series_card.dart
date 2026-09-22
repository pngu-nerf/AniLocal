import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/missing_episodes.dart';
import '../../domain/models/episode.dart';
import '../../domain/models/picture_mode.dart';
import '../../domain/models/series.dart';
import '../library_services.dart';
import '../routes.dart';
import '../theme/xp_pressable.dart';
import '../theme/xp_tokens.dart';
import '../theme/xp_widgets.dart';
import '../widgets/download_tally_label.dart';
import '../widgets/notices.dart';
import '../widgets/show_cover.dart';

/// Poster aspect ratio (width / height) for every library card's cover.
///
/// Verified against the cached AniList art: `coverImage.extraLarge` is 460px
/// wide with heights clustering at 650 (≈0.707) and ranging 0.667–0.711 — i.e.
/// the covers are NOT a single ratio. We fix the box to the dominant 460×650
/// and [BoxFit.cover] it — the cover FILLS the box (full-bleed, no gaps),
/// cropping whichever dimension overflows. Because the box is already a proper
/// ~2:3 poster shape, a normal cover fills with negligible crop; only a
/// genuinely off-ratio poster crops slightly (acceptable — no empty side/top
/// gaps). Every card's poster is identically sized.
const double kPosterAspect = 460 / 650;

/// Title font size + line height for a card, shared with [kTitleBlockHeight]
/// so the reserved title block is exactly two lines tall.
const double _kCardTitleFontSize = Xp.fontSizeLabel;
const double _kCardTitleLineHeight = 1.25;

/// Height of the ALWAYS-two-lines title block. Reserving two lines even for a
/// one-line title (its second line stays empty) keeps the meta/download line
/// below it pinned to the same vertical position on every card, regardless of
/// title length.
const double kTitleBlockHeight =
    _kCardTitleFontSize * _kCardTitleLineHeight * 2; // 32.5

/// Fixed height of the text band under the poster: the two-line title block, a
/// small gap, and one meta line — plus a little headroom. Fixed (and fed to the
/// grid delegate) so every card is uniform total height regardless of title
/// length; a short title just leaves slack inside its reserved title block.
const double kCardTextRegion = 6 + kTitleBlockHeight + 2 + 15; // ≈55.5

/// Minimum height (logical px) of the overlaid "Next" footer strip, so its label
/// stays legible even when 1/10th of a small poster would be thinner.
const double _kNextStripMinHeight = 22;

/// One show in the library grid.
///
/// Takes the [Series] it renders, the per-card stats the grid computed, and
/// the ONE services bundle — not the eighteen parameters it used to take, of
/// which it read six and forwarded the rest to the show page.
class SeriesCard extends StatefulWidget {
  const SeriesCard({
    super.key,
    required this.series,
    required this.services,
    required this.header,
    required this.nextEpisode,
    required this.downloaded,
    required this.unavailable,
    required this.onPlay,
    required this.onReturn,
  });

  final Series series;
  final LibraryServices services;

  /// Header hooks forwarded to the show page so its header matches home.
  final HeaderHooks header;

  /// The next episode to watch for this series, or null when the series isn't
  /// started / has nothing next. Drives the "Next" button.
  final Episode? nextEpisode;

  /// Downloaded-episode tally for the "⬇N of M +X" metadata line. Null while
  /// the async stats load (the line then shows just the show-type until it
  /// arrives — no wrong numbers flashed).
  final DownloadTally? downloaded;

  /// True when every source folder of this show is currently missing (offline
  /// drive/NAS): dimmed + marked, and a tap shows a reconnect hint rather than
  /// opening it. Still listed in place (cached art/metadata shown).
  final bool unavailable;
  final Future<void> Function(Episode, Series) onPlay;
  final VoidCallback onReturn;

  @override
  State<SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<SeriesCard> {
  Future<void> _open(BuildContext context, String title) async {
    if (widget.unavailable) {
      // Fail gracefully with a reconnect hint (consistent with the banner) —
      // don't open into a screen that can't play anything.
      showNotice(
        context,
        "$title isn't connected. Reconnect its drive, then scan again.",
        replace: true,
      );
      return;
    }
    await AppRoutes.detail(
      context,
      series: widget.series,
      services: widget.services,
      header: widget.header,
    );
    widget.onReturn(); // continue-watching / up-next may have changed
  }

  /// The metadata line: "ShowType · ⬇N of M +X". `maxLines: 1` + ellipsis
  /// degrades gracefully on a cramped card — the tail (the +X) drops first,
  /// never overflowing. The unavailable / pending states keep their plain copy.
  Widget _metaLine(Series series, bool unavailable) {
    const style = TextStyle(
      color: Xp.textDim,
      fontSize: Xp.fontSizeCaption,
      height: 1.2,
    );
    const one = TextOverflow.ellipsis;
    if (unavailable) {
      return const Text(
        'Unavailable — not connected',
        maxLines: 1,
        overflow: one,
        style: style,
      );
    }
    if (series.pending) {
      // "Identifying…" only while a scan is actually running. A placeholder
      // left by Stop, an outage or a cancelled run used to promise progress
      // that nothing was making.
      return Text(
        widget.services.scanning.value
            ? 'Identifying…'
            : 'Not identified yet — scan to retry',
        maxLines: 1,
        overflow: one,
        style: style,
      );
    }
    final spans = <InlineSpan>[];
    if (series.format != null) spans.add(TextSpan(text: series.format));
    final dl = widget.downloaded;
    if (dl != null) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' · '));
      spans.addAll(DownloadTallyLabel.spans(dl, fontSize: Xp.fontSizeCaption));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: one,
    );
  }

  Future<void> _setPicture(PictureMode mode) async {
    await widget.services.showPreferences.setPictureMode(
      widget.series.seriesId,
      mode,
    );
    widget.onReturn(); // reload so the projection (and every cover) refreshes
  }

  Future<void> _setNextHidden(bool hidden) async {
    await widget.services.showPreferences.setNextEpisodeHidden(
      widget.series.seriesId,
      hidden: hidden,
    );
    widget.onReturn();
  }

  /// The per-show three-dots menu: an Edit Picture submenu (three mutually
  /// exclusive cover states, current one checked; Blur/Reset disabled when the
  /// show has no cached cover) + a Hide Next Episode toggle.
  Widget _showMenu(Series series) {
    final mode = series.pictureMode;
    final hasCover = ShowCover.hasCover(series.coverImageRef);
    Widget radio(bool on) =>
        Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        tooltip: 'Show options',
        style: IconButton.styleFrom(
          backgroundColor: Xp.scrim,
          foregroundColor: Xp.text,
          minimumSize: const Size(28, 28),
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.more_vert),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SubmenuButton(
          leadingIcon: const Icon(Icons.image_outlined, size: 18),
          menuChildren: [
            MenuItemButton(
              leadingIcon: radio(mode == PictureMode.blur),
              // Needs a cover to blur — disabled when the show has none.
              onPressed: hasCover ? () => _setPicture(PictureMode.blur) : null,
              child: const Text('Blur Picture'),
            ),
            MenuItemButton(
              leadingIcon: radio(mode == PictureMode.removed),
              onPressed: () => _setPicture(PictureMode.removed),
              child: const Text('Remove Picture'),
            ),
            MenuItemButton(
              leadingIcon: radio(mode == PictureMode.normal),
              // Reset only means something when there's a cover to restore.
              onPressed: hasCover
                  ? () => _setPicture(PictureMode.normal)
                  : null,
              child: const Text('Reset to default'),
            ),
          ],
          child: const Text('Edit Picture'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            series.nextEpisodeHidden
                ? Icons.check_box
                : Icons.check_box_outline_blank,
            size: 18,
          ),
          onPressed: () => _setNextHidden(!series.nextEpisodeHidden),
          // Scoped in its label: this hides the CARD's button. The player's
          // auto-play pre-roll is the Playback › auto-play setting.
          child: const Text("Hide this card's Next button"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final unavailable = widget.unavailable;
    final next = widget.nextEpisode;
    final title = series.displayTitle;
    final art = series.coverImageRef;
    // Inverted card: the poster is the FIXED element — a 2:3 box showing the
    // whole cover, uncropped and identical across every card — sitting in a
    // sunken bevel frame that pops out (raised) on hover (the tactile XP cue
    // that it's a button). Below it a fixed-height text band keeps card heights
    // uniform regardless of title length. The "Next" affordance is a beveled
    // footer strip OVERLAID on the poster's bottom sliver, so its presence never
    // changes the card's height.
    return Opacity(
      opacity: unavailable ? 0.5 : 1,
      child: XpPressable(
        onTap: () => _open(context, title),
        semanticsLabel: unavailable ? '$title — not connected' : title,
        builder: (context, s) {
          final lit = (s.hovered || s.focused) && !unavailable;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: kPosterAspect,
                child: LayoutBuilder(
                  builder: (context, box) => XpBevel(
                    raised: lit,
                    color: Xp.well,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The cover, rendered through its per-show picture mode
                        // (normal / blurred / removed). cover-fit FILLS the 2:3
                        // box; the cached image is never altered.
                        ShowCover(
                          imagePath: art,
                          pictureMode: series.pictureMode,
                          // Pending reads as "identifying", not a broken image.
                          placeholderIcon: series.pending
                              ? (widget.services.scanning.value
                                    ? Icons.hourglass_empty
                                    : Icons.help_outline)
                              : Icons.image_not_supported,
                        ),
                        if (unavailable)
                          Container(
                            color: Xp.scrimHeavy,
                            alignment: Alignment.center,
                            // Amber = status (the drive is disconnected, not
                            // broken) — the panel's reserved attention color.
                            child: const Icon(
                              Icons.link_off,
                              color: Xp.warning,
                              size: 32,
                            ),
                          ),
                        // Per-show "Next episode" affordance — suppressed when
                        // this show's hide-next-episode preference is on.
                        if (next != null &&
                            !unavailable &&
                            !series.nextEpisodeHidden)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            // ~1/10th of the poster, but never below a legible
                            // floor so the label reads on the smallest tiles.
                            height: math.max(
                              _kNextStripMinHeight,
                              box.maxHeight * 0.1,
                            ),
                            child: _NextStrip(
                              number: next.number,
                              onPlay: () async {
                                await widget.onPlay(next, series);
                                widget.onReturn();
                              },
                            ),
                          ),
                        // Per-show three-dots menu (Edit Picture / Hide Next
                        // Episode), top-right. Not on a pending placeholder (no
                        // real identity to key a preference to).
                        if (!series.pending)
                          Positioned(
                            top: Xp.spaceXxs,
                            right: Xp.spaceXxs,
                            child: _showMenu(series),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: kCardTextRegion,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always a two-line-tall block (a one-line title leaves
                      // its second line empty) so the meta line below is pinned
                      // to the same Y on every card.
                      SizedBox(
                        height: kTitleBlockHeight,
                        width: double.infinity,
                        // Show title as a CHROME label — the thin tracked matte
                        // caps used for "Continue watching" / "Settings". Keeps
                        // the card's fixed font size + line height so the 2-line
                        // title block stays uniform across cards.
                        child: ChromeLabel(
                          title,
                          upper: false,
                          maxLines: 2,
                          fontSize: _kCardTitleFontSize,
                          height: _kCardTitleLineHeight,
                          letterSpacing: 1,
                          color: lit ? Xp.accentBright : Xp.text,
                        ),
                      ),
                      const SizedBox(height: Xp.spaceXxs),
                      _metaLine(series, unavailable),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The "Next: Ep N" affordance: a beveled footer strip seated on the bottom
/// sliver of a card's poster. It reads as an integrated part of the card (a
/// bottom "seat"), styled from the same tokens as [XpButton] — NOT a floating
/// Material button. Its own tap plays the next episode; because it's a nested
/// gesture target, the tap wins the gesture arena and does NOT bubble to the
/// card's open-detail tap (the same control-vs-parent pattern the player uses).
class _NextStrip extends StatelessWidget {
  const _NextStrip({required this.number, required this.onPlay});

  final int number;
  final Future<void> Function() onPlay;

  @override
  Widget build(BuildContext context) => XpPressable(
    onTap: onPlay,
    semanticsLabel: 'Play next: Episode $number',
    builder: (context, s) => XpBevel(
      raised: !s.pressed,
      gradient: Xp.controlGradient(hover: s.hovered || s.focused),
      child: Transform.translate(
        offset: s.pressed ? const Offset(1, 1) : Offset.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow, size: 14, color: Xp.text),
            const SizedBox(width: Xp.spaceXs),
            Flexible(
              child: Text(
                'Next: Ep $number',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: Xp.fontSizeCaption,
                  fontWeight: FontWeight.bold,
                  color: Xp.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
