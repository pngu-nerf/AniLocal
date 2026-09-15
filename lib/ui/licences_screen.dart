import 'package:flutter/material.dart';

import '../diagnostics/diagnostics.dart';
import 'shell/header_scope.dart';
import 'shell/header_spec.dart';
import 'shell/instant_page_route.dart';

/// Settings › About › Licences, as one of OUR pages.
///
/// `showLicensePage` pushes a `MaterialPageRoute` with no [HeaderSpec], so the
/// hoisted header saw a top page it knew nothing about: the readout fell to
/// its spinner and every action vanished. This wraps Flutter's `LicensePage`
/// (the same content, every package's licence plus the registered notices) in
/// a page that publishes a spec like every other screen. Back derives from
/// the Navigator, as always.
class LicencesScreen extends StatefulWidget {
  const LicencesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(InstantPageRoute<void>(builder: (_) => const LicencesScreen()));

  @override
  State<LicencesScreen> createState() => _LicencesScreenState();
}

class _LicencesScreenState extends State<LicencesScreen> with HeaderPublisher {
  @override
  HeaderSpec buildHeaderSpec() => const HeaderSpec(title: 'Licences');

  @override
  Widget build(BuildContext context) {
    publishHeader();
    return LicensePage(
      applicationName: 'AniLocal',
      applicationVersion: Diagnostics.appVersion,
    );
  }
}
