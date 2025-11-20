import 'package:flutter/services.dart';

class DeviceName {
  static const platform = MethodChannel('device_name_channel');

  static Future<String> getMarketName() async {
    try {
      final name = await platform.invokeMethod<String>('getMarketName');
      return name ?? "Unknown";
    } catch (e) {
      return "Unknown";
    }
  }
}

