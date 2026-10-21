import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/app_log.dart';
import '../../../diagnostics/diagnostics.dart';
import '../../licences_screen.dart';
import '../../theater/controls/shortcut_labels.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/copy_diagnostics.dart';
import '../../widgets/guarded.dart';
import '../setting_row.dart';

/// About & Diagnostics: the version, the evidence, and the disclosures.
///
/// This panel exists because before it there was no way to learn the app
/// version, no way to get a log out of the app, and nowhere for the licence
/// and privacy notices a distributed app owes. One category, three groups.
class AboutPanel extends StatefulWidget {
  const AboutPanel({super.key});

  @override
  State<AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<AboutPanel> {
  String? _copied;

  Future<void> _copyDiagnostics() async {
    final outcome = await copyDiagnostics();
    if (mounted) setState(() => _copied = outcome);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsGroup(
        title: 'About',
        children: [
          SettingRow(label: 'Version', subtitle: Diagnostics.appVersion),
          SettingRow(
            label: 'Licences',
            subtitle: 'GNU GPL v3 or later. No warranty.',
            info:
                'AniLocal is free software under the GNU GPL v3 or later, and '
                'comes with ABSOLUTELY NO WARRANTY. You may redistribute it '
                'under the terms of that licence; the source is at the '
                'project repository.\n\n'
                'Bundled: libmpv/FFmpeg (GPL/LGPL), libass, Archivo (OFL), '
                'and every package it builds on.',
            control: XpButton(
              label: 'View',
              // Close the window, then open OUR licences page (it publishes a
              // header spec; the stock page did not and blanked the header).
              onPressed: () {
                Navigator.of(context).pop();
                fireAndForget(
                  'open licences',
                  () => LicencesScreen.open(context),
                );
              },
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Diagnostics',
        children: [
          SettingRow(
            label: 'Copy diagnostics',
            // The outcome of the last copy replaces the subtitle, so the row
            // itself says whether it worked.
            subtitle:
                _copied ?? 'Version, counts, settings and the recent log.',
            info:
                'Paste it into a bug report: the app version, library counts, '
                'active settings and the recent log.\n\n'
                'May include your library folder names; your home directory '
                'is shown as ~.',
            control: XpButton(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onPressed: _copyDiagnostics,
            ),
          ),
          SettingRow(
            label: 'Log file',
            subtitle: AppLog.filePath ?? 'Not attached',
            control: XpButton(
              icon: Icons.folder_open_outlined,
              label: 'Reveal',
              onPressed: AppLog.filePath == null
                  ? null
                  : Diagnostics.revealLogFolder,
            ),
          ),
        ],
      ),
      // Read-only rows: the key on the right where a control would sit. The
      // list is DERIVED from the player's key map, so it cannot drift from
      // what the keys actually do.
      SettingsGroup(
        title: 'Keyboard',
        children: [
          for (final shortcut in shortcutReference(
            mac: defaultTargetPlatform == TargetPlatform.macOS,
          ))
            SettingRow(
              label: shortcut.action,
              control: Text(
                shortcut.keys,
                style: const TextStyle(
                  color: Xp.textDim,
                  fontSize: Xp.fontSizeLabel,
                ),
              ),
            ),
        ],
      ),
      const SettingsGroup(
        title: 'Privacy',
        children: [
          SettingRow(
            label: 'What leaves this computer',
            subtitle:
                'Show titles and ids go to the sources you enable. Nothing '
                'that identifies you.',
            info:
                'To identify a show, its parsed title is sent to the metadata '
                'services you have enabled (AniList, Kitsu, Jikan), and a '
                'MyAnimeList id and episode number to AniSkip for skip times. '
                'Cover images are downloaded from those services, and a public '
                'id-mapping list is fetched from GitHub about once a week.\n\n'
                'File names, folder paths and anything that identifies you or '
                'this computer are never sent. There is no telemetry, no '
                'analytics and no account.',
          ),
        ],
      ),
    ],
  );
}
