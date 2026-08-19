import 'package:flutter/material.dart';

import '../../theme/xp_tokens.dart';
import '../setting_row.dart';
import '../settings_actions.dart';
import '../settings_model.dart';
import '../settings_shell.dart';
import 'sources_panel.dart';

/// Library: what the app knows about the collection, and its health.
class LibraryPanel extends StatelessWidget {
  const LibraryPanel({super.key, required this.model, required this.actions});

  final SettingsModel model;
  final SettingsDialogActions actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsGroup(
        title: 'Episodes',
        children: [
          SettingRow(
            label: 'Missing episode placeholders',
            subtitle: 'Ghost tiles for gaps in a series.',
            info:
                'Positions with no file are shown as ghost tiles on the show '
                'page, so a gap in a series is visible instead of silent.\n\n'
                'Ghosts you do not want can be hidden per episode; hidden ones '
                'also drop out of the "N of M" tally.\n\n'
                'Turning this off removes the ghost tiles, the Hidden tab and '
                'the hidden-aware counts.',
            control: SettingSwitch(
              value: model.missingEnabled,
              onChanged: model.setMissingEnabled,
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Maintenance',
        children: [
          SettingRow(
            label: 'Unmatched files',
            subtitle: model.unmatchedCount == 0
                ? 'Nothing needs fixing'
                : '${model.unmatchedCount} file(s) we could not identify',
            info:
                'Files we scanned and parsed but could not match to an AniList '
                'entry.\n\n'
                'They stay in the library and can be matched by hand; nothing '
                'is deleted or moved.',
            onTap: () {
              Navigator.of(context).pop();
              actions.onOpenUnmatched();
            },
            control: const _Chevron(),
          ),
          SettingRow(
            label: 'Refresh metadata',
            subtitle: 'Re-fetch idMal + skip data',
            info:
                'Re-fetches metadata for series already in the cache, by id, '
                'and fills in any missing intro/outro skip data.\n\n'
                'This is not a rescan: no files are read, and it never touches '
                'your fix-matches or watch progress.',
            onTap: () => refreshMetadata(context, actions),
            control: const Icon(
              Icons.cloud_sync_outlined,
              size: 16,
              color: Xp.textDim,
            ),
          ),
          SettingRow(
            label: 'Edit sources',
            subtitle: 'Add or reorder library folders',
            info:
                'Library folders are an ordered priority list: when an episode '
                'exists in more than one folder, the highest one wins.\n\n'
                'Reordering re-resolves which copy plays; it never moves or '
                'deletes files, and it leaves per-episode source pins alone.',
            // Sources is a tab in this same window now, so this moves the
            // window rather than closing it and pushing a page.
            onTap: () => SettingsNavigation.goTo(context, sourcesCategoryId),
            control: const _Chevron(),
          ),
        ],
      ),
    ],
  );
}

/// The "this row goes somewhere" marker, so navigation rows read differently
/// from action rows at a glance.
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right, size: 18, color: Xp.textDim);
}
