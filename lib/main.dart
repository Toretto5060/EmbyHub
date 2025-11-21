import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'utils/platform_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformUtils.requestHighRefreshRate();
  runApp(const ProviderScope(child: EmbyApp()));
}
