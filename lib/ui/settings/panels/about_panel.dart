import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../diagnostics/app_log.dart';
import '../../../diagnostics/diagnostics.dart';
import '../../theme/xp_widgets.dart';
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
    final text = await Diagnostics.report();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = 'Copied ${AppLog.recent().length} log lines.');
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
            subtitle:
                'AniLocal is GPL-3.0-or-later. Bundled: libmpv/FFmpeg, '
                'Archivo, and every package it builds on.',
            control: XpButton(
              label: 'View',
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'AniLocal',
                applicationVersion: Diagnostics.appVersion,
              ),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Diagnostics',
        children: [
          SettingRow(
            label: 'Copy diagnostics',
            subtitle:
                _copied ??
                'Version, library counts, active settings and the recent log — '
                    'paste it into a bug report.',
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
      const SettingsGroup(
        title: 'Privacy',
        children: [
          SettingRow(
            label: 'What leaves this Mac',
            subtitle:
                'To identify a show, its parsed title is sent to the metadata '
                'services you have enabled (AniList, Kitsu, Jikan), and a '
                'MyAnimeList id and episode number to AniSkip for skip times. '
                'File names, folder paths and anything that identifies you or '
                'this computer are never sent. There is no telemetry, no '
                'analytics and no account.',
          ),
        ],
      ),
    ],
  );
}
