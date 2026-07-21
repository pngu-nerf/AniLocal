import 'package:flutter/material.dart';

import '../theme/vfd_readout.dart';
import '../theme/xp_widgets.dart';

/// A zone header: a CHROME section label ("NOW PLAYING", "EPISODES") beside an
/// optional lit dot-matrix COUNTER — mirroring the reference device's pairing
/// of a printed chassis label with a lit readout. The label matches every other
/// chrome title/header; the count matches the playback timer.
class ZoneEyebrow extends StatelessWidget {
  const ZoneEyebrow({super.key, required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          // Printed chrome label, left; lit dot-matrix count hard-right (compact
          // pitch so it sits inline with the small label).
          Expanded(child: ChromeLabel(label)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            VfdReadout(trailing!, dotPitch: 2),
          ],
        ],
      ),
    );
  }
}
