import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../widgets/fade_in_image.dart';

class ServerSettings {
  ServerSettings(
      {required this.protocol, required this.host, required this.port});
  final String protocol; // http or https
  final String host;
  final String port;
}

final serverSettingsProvider =
    StateNotifierProvider<ServerSettingsController, AsyncValue<ServerSettings>>(
        (ref) {
  return ServerSettingsController()..load();
});

class ServerSettingsController
    extends StateNotifier<AsyncValue<ServerSettings>> {
  ServerSettingsController() : super(const AsyncValue.loading());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final protocol = prefs.getString('server_protocol') ?? 'http';
    final host = prefs.getString('server_host') ?? '';
    final port = prefs.getString('server_port') ?? '';
    state = AsyncValue.data(
        ServerSettings(protocol: protocol, host: host, port: port));
  }

  Future<void> save(ServerSettings settings) async {
    state = const AsyncValue.loading();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_protocol', settings.protocol);
    await prefs.setString('server_host', settings.host);
    await prefs.setString('server_port', settings.port);
    state = AsyncValue.data(settings);
  }
}

final authStateProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthState>>((ref) {
  return AuthController()..load();
});

class AuthState {
  AuthState(
      {required this.userId, required this.userName, required this.token});
  final String? userId;
  final String? userName;
  final String? token;
  bool get isLoggedIn => (userId ?? '').isNotEmpty && (token ?? '').isNotEmpty;
}

class AuthController extends StateNotifier<AsyncValue<AuthState>> {
  AuthController() : super(const AsyncValue.loading());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('emby_user_id');
    final serverHost = prefs.getString('server_host');

    // ✅ 计算服务器ID（与ServerCacheManager保持一致）
    String? serverId;
    if (serverHost != null && serverHost.isNotEmpty) {
      serverId = await _getServerId(serverHost);
    }

    // ✅ 设置图片缓存的用户ID和服务器ID（用于缓存隔离）
    setImageCacheUserAndServer(userId, serverId);

    state = AsyncValue.data(AuthState(
      userId: userId,
      userName: prefs.getString('emby_user_name'),
      token: prefs.getString('emby_token'),
    ));
  }

  // ✅ 计算服务器ID（与ServerCacheManager保持一致）
  Future<String> _getServerId(String host) async {
    // 移除端口号
    String hostWithoutPort = host;
    if (host.startsWith('[')) {
      final closeBracket = host.indexOf(']');
      if (closeBracket != -1) {
        hostWithoutPort = host.substring(0, closeBracket + 1);
      }
    } else {
      final colonIndex = host.lastIndexOf(':');
      if (colonIndex != -1) {
        final colonCount = ':'.allMatches(host).length;
        if (colonCount == 1) {
          hostWithoutPort = host.substring(0, colonIndex);
        }
      }
    }

    // 使用MD5生成服务器ID
    final bytes = utf8.encode(hostWithoutPort.toLowerCase());
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<void> clear() async {
    state = const AsyncValue.loading();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('emby_user_id');
    await prefs.remove('emby_user_name');
    await prefs.remove('emby_token');
    state =
        AsyncValue.data(AuthState(userId: null, userName: null, token: null));
  }
}

// ✅ 主题模式枚举
enum AppThemeMode {
  dark('dark', '深色'),
  light('light', '浅色'),
  system('system', '跟随系统');

  const AppThemeMode(this.value, this.label);
  final String value;
  final String label;
}

// ✅ 主题模式 Provider
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, AppThemeMode>((ref) {
  return ThemeModeController()..load();
});

class ThemeModeController extends StateNotifier<AppThemeMode> {
  ThemeModeController() : super(AppThemeMode.dark); // ✅ 默认深色

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('theme_mode') ?? 'dark';
      state = AppThemeMode.values.firstWhere(
        (mode) => mode.value == value,
        orElse: () => AppThemeMode.dark,
      );
    } catch (e) {
      state = AppThemeMode.dark;
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', mode.value);
    } catch (e) {
      // 保存失败不影响状态更新
    }
  }
}
