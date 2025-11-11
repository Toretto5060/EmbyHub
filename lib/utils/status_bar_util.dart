import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StatusBarUtil {
  static const SystemUiOverlayStyle _lightIcons = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  static const SystemUiOverlayStyle _darkIcons = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static void setLightIcons() {
    SystemChrome.setSystemUIOverlayStyle(_lightIcons);
  }

  static void setDarkIcons() {
    SystemChrome.setSystemUIOverlayStyle(_darkIcons);
  }

  static void setByColor(Color color) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    if (brightness == Brightness.dark) {
      setLightIcons();
    } else {
      setDarkIcons();
    }
  }

  static void applyStyle(SystemUiOverlayStyle style) {
    SystemChrome.setSystemUIOverlayStyle(style);
  }

  static SystemUiOverlayStyle styleForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _lightIcons : _darkIcons;
  }
}
