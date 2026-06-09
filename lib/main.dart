import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv via media_kit before any Player is constructed.
  MediaKit.ensureInitialized();
  runApp(const AniLocalApp());
}
