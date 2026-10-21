import 'package:flutter/material.dart';

import '../setting_row.dart';
import '../settings_actions.dart';
import '../settings_model.dart';
import 'source_list_panel.dart';

/// Sources: where information comes from. Two lists, one question each.
///
/// "Show information" is the metadata family ("what is this show"); "Intro /
/// outro timings" is the skip family ("where is the OP/ED"). They keep
/// SEPARATE orders because they answer different questions and fail
/// independently — reordering one never touches the other — but they are one
/// tab because a user asking "where does AniLocal get its data" should find
/// the whole answer in one place. Library folders are a different question
/// ("what do I own") and have their own tab.
///
/// Both lists are shrink-wrapped and the shell scrolls the tab, so this panel
/// is `scrollable: true` in the window's category list.
class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key, required this.model, required this.actions});

  final SettingsModel model;
  final SettingsDialogActions actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsGroup(
        title: 'Show information',
        children: [
          SourceListPanel(
            sources: actions.metadataSources,
            settings: model.repository,
            loadOrder: model.repository.loadMetadataSourceOrder,
            saveOrder: model.repository.setMetadataSourceOrder,
            caption:
                'Top source is used first. The rest are tried only if it fails.',
            scanning: actions.scanning,
          ),
        ],
      ),
      SettingsGroup(
        title: 'Intro / outro timings',
        children: [
          SourceListPanel(
            sources: actions.skipSources,
            settings: model.repository,
            loadOrder: model.repository.loadSkipSourceOrder,
            saveOrder: model.repository.setSkipSourceOrder,
            caption:
                'Top source is used first. The rest are tried only if it has '
                'no data for an episode.',
            scanning: actions.scanning,
          ),
        ],
      ),
    ],
  );
}
