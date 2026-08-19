import 'package:flutter/material.dart';

import '../setting_row.dart';
import '../settings_model.dart';

/// Homepage: what the library screen puts in front of you.
class HomepagePanel extends StatelessWidget {
  const HomepagePanel({super.key, required this.model});

  final SettingsModel model;

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: 'Sections',
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
      SettingRow(
        label: 'Next episode',
        subtitle: 'Play-next button on every show card.',
        info:
            'Shows the "Next: Ep N" button on show cards and on the show '
            'page.\n\n'
            'Warning: this is a master switch. Changing it OVERWRITES each '
            "show's own next-episode choice to match, and those individual "
            'choices are not restored if you change it back.',
        // DISPLAY is inverted, the stored value is not: the setting persists as
        // "hide next episode", and a row labelled "Next episode" that was ON
        // when the button was HIDDEN would read backwards. What reaches the
        // repository — including its apply-to-all overwrite — is unchanged.
        control: SettingSwitch(
          value: !model.hideNextEpisode,
          onChanged: (shown) => model.setHideNextEpisode(!shown),
        ),
      ),
    ],
  );
}
