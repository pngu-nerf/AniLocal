import 'package:flutter/material.dart';

import '../../../domain/models/metadata_source.dart';
import '../../../domain/models/source_preference.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../theme/xp_tokens.dart';
import '../../theme/xp_widgets.dart';
import 'client_id_dialog.dart';
import '../../widgets/xp_reorderable_list.dart';

/// Where metadata comes from, and in what order.
///
/// Deliberately a SEPARATE category from Sources: that one is library folders
/// ("what do I own"), this one is metadata sources ("what is this show"). They
/// fail independently and mean different things, so blurring them into one
/// list would be worse than the duplication of having two.
///
/// The list is the setting — top is the source of truth, the rest are
/// fallbacks used only when the one above fails. Turning a source off skips it
/// entirely.
class MetadataPanel extends StatefulWidget {
  const MetadataPanel({
    super.key,
    required this.sources,
    required this.settings,
  });

  /// Every source this build ships, in built-in order.
  final List<MetadataSource> sources;
  final SettingsRepository settings;

  @override
  State<MetadataPanel> createState() => _MetadataPanelState();
}

class _MetadataPanelState extends State<MetadataPanel> {
  /// Null only until the first load — never cleared afterwards, so reordering
  /// doesn't flash the list through a spinner (CLAUDE.md: never clear known
  /// content to show a loading state).
  List<MetadataSource>? _ordered;
  List<SourcePreference> _prefs = const [];

  /// token -> the client ID the user has stored, for sources that need one.
  /// Read from settings rather than snapshotted at startup, so pasting a key
  /// takes effect immediately and the panel and the lookup chain can never
  /// disagree about whether a source is usable.
  Map<String, String?> _clientIds = const {};

  /// A source is usable if it needs no key, or has one.
  bool _configured(MetadataSource s) =>
      !s.requiresClientId || (_clientIds[s.token]?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await widget.settings.loadMetadataSourceOrder();
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

  /// Persist the list exactly as displayed, so what the user sees IS the saved
  /// order — no separate notion of order living anywhere else.
  Future<void> _persist(List<MetadataSource> ordered) async {
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
    await widget.settings.setMetadataSourceOrder(prefs);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final list = [...?_ordered];
    list.insert(newIndex, list.removeAt(oldIndex));
    await _persist(list);
  }

  Future<void> _toggle(MetadataSource source, bool enabled) async {
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
    await widget.settings.setMetadataSourceOrder(prefs);
  }

  Future<void> _editClientId(MetadataSource source) async {
    final entered = await showClientIdDialog(
      context,
      source: source,
      current: _clientIds[source.token],
    );
    if (entered == null) return; // cancelled — leave the stored key alone
    await widget.settings.setSourceClientId(source.token, entered);
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
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Top source is used first. The rest are tried only if it fails.',
            style: TextStyle(color: Xp.textDim, fontSize: 11),
          ),
        ),
        Expanded(
          child: XpReorderableList<MetadataSource>(
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
            dimmed: (s) => !_configured(s) || !isSourceEnabled(s.token, _prefs),
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
            leadingBuilder: (s) => Checkbox(
              value: isSourceEnabled(s.token, _prefs),
              // An unconfigured source can't be switched on — there is nothing
              // behind it yet. The row stays visible and says what is missing.
              onChanged: _configured(s) ? (v) => _toggle(s, v ?? false) : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

/// Named once so the category id and any deep-link to it can't drift apart.
const String metadataCategoryId = 'metadata';
