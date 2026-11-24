import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only, on every platform. A waiter holds this one-handed while carrying plates, and
  // every layout in the app is built for a 360–430 dp wide window. The Android manifest and the
  // iOS Info.plist lock it too; this covers the case of the app being resumed mid-rotation.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: MdStaffApp()));
}
