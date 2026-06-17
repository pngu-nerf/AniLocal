import 'package:flutter/material.dart';

/// A small uppercase, letter-spaced section label — the theater's quiet,
/// consistent way of titling a zone ("NOW PLAYING", "EPISODES"). Shared so the
/// zones read as one room.
class ZoneEyebrow extends StatelessWidget {
  const ZoneEyebrow({super.key, required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: style),
          if (trailing != null) ...[
            const Spacer(),
            Text(trailing!, style: style),
          ],
        ],
      ),
    );
  }
}
