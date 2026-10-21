import 'package:flutter/material.dart';

import '../../widgets/confirm_dialog.dart';
import '../../widgets/guarded.dart';
import '../../widgets/notices.dart';
import '../setting_row.dart';
import '../settings_actions.dart';
import '../settings_model.dart';

/// Display: what the screens show.
///
/// The homepage's sections and the show-level indicators, together: every row
/// here is a thing the user does or does not want to SEE. None of them changes
/// what the library contains or what the player does.
class DisplayPanel extends StatelessWidget {
  const DisplayPanel({super.key, required this.model, required this.actions});

  final SettingsModel model;
  final SettingsDialogActions actions;

  /// The Next episode master switch OVERWRITES every show's own choice. Ask
  /// only when that would actually change something: a library where no show
  /// carries a choice (the common case) just flips. "Would change" is a row
  /// whose stored value differs from the one about to be written; a show with
  /// no row has no choice to lose.
  Future<void> _setNextEpisodeShown(BuildContext context, bool shown) async {
    final hidden = !shown;
    final prefs = await actions.showPreferences.allPreferences();
    final overwrites = prefs.values
        .where((p) => p.nextEpisodeHidden != hidden)
        .length;
    if (overwrites > 0) {
      if (!context.mounted) return;
      final ok = await confirmAction(
        context,
        title: 'Apply to every show?',
        body:
            '$overwrites ${overwrites == 1 ? 'show has its' : 'shows have their'} '
            'own "Next episode" choice. Turning this ${shown ? 'on' : 'off'} '
            'replaces ${overwrites == 1 ? 'it' : 'all of them'}, and '
            '${overwrites == 1 ? 'it is' : 'they are'} not restored if you '
            'change it back.',
        confirmLabel: 'Apply to all',
      );
      if (!ok) return;
    }
    model.setHideNextEpisode(hidden);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsGroup(
        title: 'Homepage',
        children: [
          SettingRow(
            label: 'Continue watching',
            control: SettingSwitch(
              value: model.showContinueWatching,
              onChanged: model.setShowContinueWatching,
            ),
          ),
          SettingRow(
            label: 'Search bar',
            control: SettingSwitch(
              value: model.showSearchBar,
              onChanged: model.setShowSearchBar,
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Shows',
        children: [
          SettingRow(
            label: 'Next episode',
            subtitle: 'Play-next button on show cards and the show page.',
            info:
                'Shows the "Next: Ep N" button on show cards and on the show '
                'page.\n\n'
                'This is a master switch. Changing it OVERWRITES each '
                "show's own next-episode choice to match, and those individual "
                'choices are not restored if you change it back — it asks '
                'first when any show would lose one.',
            // DISPLAY is inverted, the stored value is not: the setting
            // persists as "hide next episode", and a row labelled "Next
            // episode" that was ON when the button was HIDDEN would read
            // backwards. What reaches the repository — including its
            // apply-to-all overwrite — is unchanged.
            control: SettingSwitch(
              value: !model.hideNextEpisode,
              onChanged: (shown) => guarded(
                'next episode switch',
                () => _setNextEpisodeShown(context, shown),
                onError: (e) {
                  if (context.mounted) {
                    showFailure(context, "Couldn't read per-show choices.", e);
                  }
                },
              ),
            ),
          ),
          SettingRow(
            label: 'Missing episode placeholders',
            subtitle: 'Ghost tiles for gaps in a show.',
            info:
                'Positions with no file are shown as ghost tiles on the show '
                'page, so a gap in a show is visible instead of silent.\n\n'
                'Ghosts you do not want can be hidden per episode; hidden ones '
                'also drop out of the "N of M" tally.\n\n'
                'Turning this off removes the ghost tiles, the Hidden tab and '
                'the hidden-aware counts.',
            control: SettingSwitch(
              value: model.missingEnabled,
              onChanged: model.setMissingEnabled,
            ),
          ),
          SettingRow(
            label: 'Airing status',
            subtitle: 'Which shows are airing, and when an episode is out.',
            info:
                'On the episode-count line: a dim note while a show is '
                'airing and you are caught up ("Ep 9 · in 3d"), and an amber '
                'flag once an episode has aired that is not in your library '
                '("Ep 8 out"). The flag stays for a week after the finale.\n\n'
                'Air times come from the metadata sources during a scan; the '
                'words are measured against your clock, so they do not go '
                'stale between scans.\n\n'
                'A show can be muted on its own from the card\'s menu.',
            control: SettingSwitch(
              value: model.airingEnabled,
              onChanged: model.setAiringEnabled,
            ),
          ),
        ],
      ),
    ],
  );
}
