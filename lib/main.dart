import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'utils/platform_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformUtils.requestHighRefreshRate();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: EmbyApp()));
}
