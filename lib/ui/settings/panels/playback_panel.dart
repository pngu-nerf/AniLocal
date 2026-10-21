import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/skip_mode.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../theme/xp_tokens.dart';
import '../setting_row.dart';
import '../settings_labels.dart';
import '../settings_model.dart';

/// Playback: what the player does on its own.
///
/// Everything about skipping lives HERE — the mode, the minimum length and the
/// cross-check — because they are one decision the viewer makes about one
/// behaviour. Where the timings come FROM is a Sources question and sits on
/// that tab; splitting the behaviour across the two was the drift this layout
/// replaced.
class PlaybackPanel extends StatelessWidget {
  const PlaybackPanel({super.key, required this.model});

  final SettingsModel model;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsGroup(
        title: 'Next episode',
        children: [
          SettingRow(
            label: 'Autoplay next episode',
            control: SettingSwitch(
              value: model.autoPlayNext,
              onChanged: model.setAutoPlayNext,
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Intro & outro',
        children: [
          SettingRow(
            label: 'Skip intro / outro',
            // The 3-way control is carried over exactly: same options, same
            // order, same single write to setSkipMode.
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
            label: 'Ignore skips shorter than',
            subtitle: 'Seconds. 0 keeps every window.',
            info:
                'An opening runs about 90 seconds, so a very short "skip" is '
                'usually a source mistaking a sting or scene break for a '
                'theme.\n\n'
                'Applies to every timing source. Maximum 600 seconds.',
            control: SizedBox(
              width: 96,
              child: _SecondsField(
                seconds: model.minSkipLength.inSeconds,
                onChanged: model.setMinSkipLength,
              ),
            ),
          ),
          SettingRow(
            label: 'Cross-check sources',
            subtitle: 'Compare every timing source before skipping.',
            // No "slower": since v19 every source is asked at scan time
            // regardless, and this decides only how the answers are read.
            info:
                'Ask every source and compare. Two that agree can auto-skip; '
                'ones that disagree offer a button instead.\n\n'
                'A source with no data for an episode is not a disagreement.',
            control: SettingSwitch(
              value: model.corroborateSkips,
              onChanged: model.setCorroborateSkips,
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Watched',
        children: [
          SettingRow(
            label: 'Mark as watched',
            subtitle: 'Time from the end that counts as finished.',
            info:
                'An episode is marked watched once playback reaches this far '
                'from its end.\n\n'
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
                style: const TextStyle(
                  color: Xp.text,
                  fontSize: Xp.fontSizeLabel,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'm:ss',
                  errorText: model.thresholdValid ? null : 'm:ss, max 9:59',
                  errorStyle: const TextStyle(fontSize: Xp.fontSizeMicro),
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
      ),
    ],
  );
}

/// A plain seconds field.
///
/// Deliberately not the m:ss control the watched-threshold uses: this is a
/// short duration the user thinks about in seconds ("ignore anything under
/// 30"), and m:ss would make them type a colon to say so.
class _SecondsField extends StatefulWidget {
  const _SecondsField({required this.seconds, required this.onChanged});

  final int seconds;
  final void Function(int) onChanged;

  @override
  State<_SecondsField> createState() => _SecondsFieldState();
}

class _SecondsFieldState extends State<_SecondsField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.seconds}',
  );

  /// What was last written, so a blur that changed nothing writes nothing.
  late String _committed = '${widget.seconds}';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Committed on blur/submit rather than per keystroke: mid-typing "3" on the
  /// way to "30" is a different setting, and saving it would briefly hide
  /// windows the user never meant to exclude.
  void _commit() {
    final text = _controller.text.trim();
    if (text == _committed) return;
    final parsed = int.tryParse(text);
    if (parsed == null) {
      _controller.text = _committed; // unparseable -> leave it alone
      return;
    }
    final clamped = parsed.clamp(0, minSkipLengthMax.inSeconds);
    _controller.text = '$clamped';
    _committed = '$clamped';
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (hasFocus) {
      if (!hasFocus) _commit();
    },
    child: TextField(
      controller: _controller,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Xp.text, fontSize: Xp.fontSizeLabel),
      decoration: const InputDecoration(
        isDense: true,
        suffixText: 's',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
    ),
  );
}
