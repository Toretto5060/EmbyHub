import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    state = AsyncValue.data(AuthState(
      userId: prefs.getString('emby_user_id'),
      userName: prefs.getString('emby_user_name'),
      token: prefs.getString('emby_token'),
    ));
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
