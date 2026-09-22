import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/source_descriptor.dart';
import '../../../domain/models/source_preference.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../metadata_failure_message.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import '../../widgets/guarded.dart';
import '../../widgets/notices.dart';
import '../../widgets/xp_message.dart';
import '../../widgets/xp_reorderable_list.dart';
import '../settings_actions.dart';
import 'client_id_dialog.dart';

/// An ordered, individually-switchable list of sources.
///
/// ONE panel for BOTH families — metadata ("what is this show") and skip
/// ("where is the OP/ED"). They are separate categories with separate orders
/// because they answer different questions and fail independently, but the row
/// itself is identical in both, so a second copy of this would only drift.
///
/// The list IS the setting: top is the source of truth, the rest are fallbacks
/// used only when the one above fails or has no data. Turning a source off
/// skips it entirely.
class SourceListPanel extends StatefulWidget {
  const SourceListPanel({
    super.key,
    required this.sources,
    required this.settings,
    required this.loadOrder,
    required this.saveOrder,
    required this.caption,
    this.extra,
    this.scanning,
  });

  /// True while a scan runs: reordering and switching are disabled, like the
  /// Folders panel — the scan reads the order per match, and a list that
  /// changes under it is a scan whose answers came from two orders.
  final ValueListenable<bool>? scanning;

  /// Every source of this family that the build ships, in built-in order.
  final List<SourceDescriptor> sources;
  final SettingsRepository settings;

  /// Which family's order to read and write — the only thing that differs
  /// between the two uses, besides the caption.
  final Future<List<SourcePreference>> Function() loadOrder;
  final Future<void> Function(List<SourcePreference>) saveOrder;

  /// One line explaining what being first means for THIS family.
  final String caption;

  /// An optional control belonging to this family, shown under the caption —
  /// a generic slot, so the panel stays ignorant of which family it is serving.
  final Widget? extra;

  @override
  State<SourceListPanel> createState() => _SourceListPanelState();
}

class _SourceListPanelState extends State<SourceListPanel> {
  /// Null only until the first load — never cleared afterwards, so reordering
  /// doesn't flash the list through a spinner (CLAUDE.md: never clear known
  /// content to show a loading state).
  List<SourceDescriptor>? _ordered;
  List<SourcePreference> _prefs = const [];

  /// token -> the client ID the user has stored, for sources that need one.
  /// Read from settings rather than snapshotted at startup, so pasting a key
  /// takes effect immediately and the panel and the lookup chain can never
  /// disagree about whether a source is usable.
  Map<String, String?> _clientIds = const {};

  /// A source is usable if it needs no key, or has one.
  bool _configured(SourceDescriptor s) =>
      !s.requiresClientId || (_clientIds[s.token]?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Set when the load failed; rendered instead of the spinner.
  Object? _loadError;

  Future<void> _load() => guarded(
    'source list',
    _loadUnguarded,
    onError: (e) {
      if (mounted) setState(() => _loadError = e);
    },
  );

  Future<void> _loadUnguarded() async {
    final prefs = await widget.loadOrder();
    final keys = <String, String?>{};
    for (final source in widget.sources) {
      if (source.requiresClientId) {
        keys[source.token] = await widget.settings.loadSourceClientId(
          source.token,
        );
      }
    }
    if (!mounted) return;
    _clientIds = keys;
    setState(() {
      _prefs = prefs;
      // enabledOnly: false — the panel must show a disabled source, otherwise
      // there is no way to turn it back on.
      _ordered = applySourceOrder(
        widget.sources,
        (s) => s.token,
        prefs,
        enabledOnly: false,
        isFallbackOnly: (s) => s.fallbackOnly,
      );
    });
  }

  /// A write that did not land: say so, then re-read so the list shows what
  /// IS stored rather than what was attempted.
  void _sayWriteFailed(Object e) {
    if (!mounted) return;
    showWriteFailed(context, e);
    unawaited(_load());
  }

  /// Persist the list exactly as displayed, so what the user sees IS the saved
  /// order — no separate notion of order living anywhere else.
  Future<void> _persist(List<SourceDescriptor> ordered) async {
    final prefs = [
      for (final s in ordered)
        SourcePreference(
          token: s.token,
          enabled: isSourceEnabled(s.token, _prefs),
        ),
    ];
    setState(() {
      // Re-apply the rule so a fallback-only source dragged above a real one
      // visibly settles back rather than appearing to have been accepted.
      _ordered = applySourceOrder(
        ordered,
        (s) => s.token,
        prefs,
        enabledOnly: false,
        isFallbackOnly: (s) => s.fallbackOnly,
      );
      _prefs = prefs;
    });
    await guarded(
      'save source order',
      () => widget.saveOrder(prefs),
      onError: _sayWriteFailed,
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final list = [...?_ordered];
    list.insert(newIndex, list.removeAt(oldIndex));
    await _persist(list);
  }

  Future<void> _toggle(SourceDescriptor source, bool enabled) async {
    final list = [...?_ordered];
    final prefs = [
      for (final s in list)
        SourcePreference(
          token: s.token,
          enabled: s.token == source.token
              ? enabled
              : isSourceEnabled(s.token, _prefs),
        ),
    ];
    setState(() => _prefs = prefs);
    await guarded(
      'save source order',
      () => widget.saveOrder(prefs),
      onError: _sayWriteFailed,
    );
  }

  Future<void> _editClientId(SourceDescriptor source) async {
    final entered = await showClientIdDialog(
      context,
      source: source,
      current: _clientIds[source.token],
    );
    if (entered == null) return; // cancelled — leave the stored key alone
    await guarded(
      'save client id',
      () => widget.settings.setSourceClientId(source.token, entered),
      onError: _sayWriteFailed,
    );
    if (!mounted) return;
    setState(() {
      _clientIds = {
        ..._clientIds,
        source.token: entered.isEmpty ? null : entered,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    if (ordered == null) {
      final error = _loadError;
      if (error != null) {
        return XpMessage(
          "Couldn't read the source list. ${userFacingMessage(error)}",
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            widget.caption,
            style: const TextStyle(
              color: Xp.textDim,
              fontSize: Xp.fontSizeCaption,
            ),
          ),
        ),
        if (widget.extra != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: widget.extra,
          ),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable:
                widget.scanning ?? const AlwaysStoppedAnimation<bool>(false),
            builder: (context, scanning, _) => XpReorderableList<SourceDescriptor>(
              enabled: !scanning,
              items: ordered,
              keyOf: (s) => s.token,
              titleOf: (s) => s.displayName,
              firstCaption: 'Source of truth',
              subtitleOf: (s) => switch (s) {
                _ when !_configured(s) => s.setupHint,
                _ when s.fallbackOnly =>
                  'Fallback only — never the source of truth',
                _ => null,
              },
              dimmed: (s) =>
                  !_configured(s) || !isSourceEnabled(s.token, _prefs),
              onReorder: _reorder,
              trailingBuilder: (s) => !s.requiresClientId
                  ? const SizedBox.shrink()
                  : XpButton(
                      dense: true,
                      icon: Icons.key_outlined,
                      label: _configured(s) ? 'Change' : 'Add key',
                      tooltip: 'Client ID for ${s.displayName}',
                      onPressed: () => _editClientId(s),
                    ),
              leadingBuilder: (s) => Tooltip(
                message: scanning ? kWaitForScanTooltip : '',
                child: Checkbox(
                  value: isSourceEnabled(s.token, _prefs),
                  // An unconfigured source can't be switched on — there is
                  // nothing behind it yet. The row stays visible and says what
                  // is missing. Nor can any source while a scan runs.
                  onChanged: _configured(s) && !scanning
                      ? (v) => _toggle(s, v ?? false)
                      : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
