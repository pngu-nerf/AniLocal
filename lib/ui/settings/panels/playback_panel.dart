import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/skip_mode.dart';
import '../../theme/xp_tokens.dart';
import '../setting_row.dart';
import '../settings_labels.dart';
import '../settings_model.dart';

/// Playback: what the player does on its own.
class PlaybackPanel extends StatelessWidget {
  const PlaybackPanel({super.key, required this.model});

  final SettingsModel model;

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: 'Episodes',
    children: [
      SettingRow(
        label: 'Autoplay next episode',
        control: SettingSwitch(
          value: model.autoPlayNext,
          onChanged: model.setAutoPlayNext,
        ),
      ),
      SettingRow(
        label: 'Skip intro / outro',
        // The 3-way control is carried over exactly: same options, same order,
        // same single write to setSkipMode. Only its placement changed.
        control: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in SkipMode.values)
              SettingRadio(
                label: skipModeLabel(mode),
                selected: mode == model.skipMode,
                onSelected: () => model.setSkipMode(mode),
              ),
          ],
        ),
      ),
      SettingRow(
        label: 'Mark as watched',
        subtitle: 'Time from the end that counts as finished.',
        info:
            'An episode is marked watched once playback reaches this far from '
            'its end.\n\n'
            '0:00 turns off automatic watched-marking entirely.\n\n'
            'Episodes shorter than this duration are marked watched when '
            'opened.\n\n'
            'Maximum 9:59. An entry that is not m:ss is never saved.',
        control: SizedBox(
          width: 96,
          child: TextField(
            controller: model.thresholdController,
            // Digits + a single colon; m:ss never exceeds 4 chars.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9:]')),
              LengthLimitingTextInputFormatter(5),
            ],
            keyboardType: TextInputType.datetime,
            style: const TextStyle(color: Xp.text, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'm:ss',
              errorText: model.thresholdValid ? null : 'm:ss, max 9:59',
              errorStyle: const TextStyle(fontSize: 10),
            ),
            onChanged: model.editThreshold,
            onEditingComplete: () {
              model.commitThreshold();
              FocusScope.of(context).unfocus();
            },
          ),
        ),
      ),
    ],
  );
}
