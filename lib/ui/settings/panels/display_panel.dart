import 'package:flutter/material.dart';

import '../setting_row.dart';
import '../settings_model.dart';

/// Display: what the screens show.
///
/// The homepage's sections and the show-level indicators, together: every row
/// here is a thing the user does or does not want to SEE. None of them changes
/// what the library contains or what the player does.
class DisplayPanel extends StatelessWidget {
  const DisplayPanel({super.key, required this.model});

  final SettingsModel model;

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
                'Warning: this is a master switch. Changing it OVERWRITES each '
                "show's own next-episode choice to match, and those individual "
                'choices are not restored if you change it back.',
            // DISPLAY is inverted, the stored value is not: the setting
            // persists as "hide next episode", and a row labelled "Next
            // episode" that was ON when the button was HIDDEN would read
            // backwards. What reaches the repository — including its
            // apply-to-all overwrite — is unchanged.
            control: SettingSwitch(
              value: !model.hideNextEpisode,
              onChanged: (shown) => model.setHideNextEpisode(!shown),
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
