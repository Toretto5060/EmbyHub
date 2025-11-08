import 'dart:io';
import 'package:flutter/services.dart';

class PlatformUtils {
  static const _channel = MethodChannel('com.embyhub/platform');

  /// Android: 将应用移到后台（不退出）
  /// iOS: 不支持（iOS 不允许程序化退出）
  static Future<void> moveToBackground() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('moveToBackground');
        print('📱 应用已移到后台');
      } catch (e) {
        print('❌ 移到后台失败，使用 SystemNavigator.pop(): $e');
        // 降级方案：退出应用
        SystemNavigator.pop();
      }
    }
    // iOS 不做任何操作
  }

  /// Android: 请求系统切换到最高可用刷新率（若设备支持）
  static Future<void> requestHighRefreshRate() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod('setHighRefreshRate');
      print('⚡ 已请求高刷新率显示模式');
    } catch (e) {
      print('❌ 请求高刷新率失败: $e');
    }
  }
}

