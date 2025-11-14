import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/account_history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/status_bar_manager.dart';

class ModernConnectPage extends ConsumerStatefulWidget {
  const ModernConnectPage({super.key, this.startAtLogin = false});

  final bool startAtLogin;

  @override
  ConsumerState<ModernConnectPage> createState() => _ModernConnectPageState();
}

class _ModernConnectPageState extends ConsumerState<ModernConnectPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  String _protocol = 'http';
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pwd = TextEditingController();

  bool _serverConnected = false;
  bool _loading = false;
  String? _serverName;
  bool _rememberMe = false; // ✅ 记住我选项，默认勾选

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ));
    _animController.forward();

    final settings = ref.read(serverSettingsProvider);
    settings.whenData((value) {
      setState(() {
        _protocol = value.protocol;
        _host.text = value.host;
        // 只有当用户之前保存过端口时才填充，否则保持空白
        if (value.port.isNotEmpty) {
          _port.text = value.port;
        }
        // If startAtLogin is true and we have server settings, go directly to login
        if (widget.startAtLogin && value.host.isNotEmpty) {
          _serverConnected = true;
          final displayPort = value.port.isEmpty ? '8096' : value.port;
          _serverName = '${value.protocol}://${value.host}:$displayPort';
        }
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    // 让所有输入框失去焦点，避免键盘闪烁和焦点传递问题
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });
    try {
      final port = _port.text.trim().isEmpty ? '8096' : _port.text.trim();
      await ref.read(serverSettingsProvider.notifier).save(ServerSettings(
          protocol: _protocol, host: _host.text.trim(), port: port));
      final api = await EmbyApi.create();
      final info = await api.systemInfo();
      setState(() {
        _serverConnected = true;
        _serverName = info['ServerName'] as String? ?? 'Emby Server';
        _loading = false;
      });
    } on dio.DioException catch (e) {
      final errorMsg = e.response?.statusMessage ?? e.message ?? '连接失败';
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pwd.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入用户名和密码'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final api = await EmbyApi.create();
      final result = await api.authenticate(
          username: _user.text.trim(), password: _pwd.text);

      // ✅ 只有勾选了"记住我"才保存到账号历史
      if (_rememberMe) {
        final serverSettingsAsync = ref.read(serverSettingsProvider);
        final serverSettings = serverSettingsAsync.value;
        if (serverSettings != null) {
          final serverUrl =
              '${serverSettings.protocol}://${serverSettings.host}:${serverSettings.port}';
          await ref.read(accountHistoryProvider.notifier).addAccount(
                serverUrl,
                result.userName,
                result.token,
                userId: result.userId,
              );
        }
      } else {}

      await ref.read(authStateProvider.notifier).load();
      if (!mounted) return;
      context.go('/');
    } on dio.DioException catch (e) {
      String errorMsg = '登录失败';
      if (e.response?.statusCode == 401) {
        errorMsg = '用户名或密码错误';
      } else if (e.response?.data != null && e.response!.data is Map) {
        errorMsg = e.response!.data['Message'] ?? e.message ?? errorMsg;
      } else {
        errorMsg = e.message ?? errorMsg;
      }
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录失败：$e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  void _resetConnection() {
    setState(() {
      _serverConnected = false;
      _serverName = null;
      _user.clear();
      _pwd.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    );

    return StatusBarStyleScope(
      style: overlay,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.deepPurple.shade900,
                Colors.purple.shade700,
                Colors.pink.shade600,
              ],
            ),
          ),
          child: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 40),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildLogo(),
                            const SizedBox(height: 40),
                            if (!_serverConnected)
                              _buildServerCard()
                            else
                              _buildLoginCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!_serverConnected)
                Positioned(
                  top: 50,
                  right: 20,
                  child: SafeArea(
                    child: TextButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.home_rounded,
                          color: Colors.white, size: 20),
                      label: const Text('跳过',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        backgroundColor: Colors.white.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.movie_filter_rounded,
            size: 56,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'EmbyHub',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w300,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '让娱乐触手可及',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.8),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildServerCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Card(
        elevation: 24,
        shadowColor: Colors.black.withOpacity(0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey.shade50,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '连接服务器',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '输入 Emby 服务器地址',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Colors.deepPurple,
                    selectedForegroundColor: Colors.white,
                    foregroundColor: Colors.grey.shade800,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 'http',
                      label: Text('HTTP'),
                      icon: Icon(Icons.http, size: 18),
                    ),
                    ButtonSegment(
                      value: 'https',
                      label: Text('HTTPS'),
                      icon: Icon(Icons.https, size: 18),
                    ),
                  ],
                  selected: {_protocol},
                  onSelectionChanged: (Set<String> selected) {
                    setState(() => _protocol = selected.first);
                  },
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _host,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'example.com 或 192.168.1.100',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  prefixIcon: const Icon(Icons.dns_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _port,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: InputDecoration(
                  labelText: '端口（可选）',
                  hintText: '留空则使用 8096',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: const Icon(Icons.settings_ethernet_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _loading ? null : _testConnection,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: Colors.deepPurple,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 4,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '连接服务器',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Card(
        elevation: 24,
        shadowColor: Colors.black.withOpacity(0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey.shade50,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: _resetConnection,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '登录',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _serverName ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _user,
                autofocus: true,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: InputDecoration(
                  labelText: '用户名',
                  hintText: '输入用户名',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 16),
                  prefixIcon: const Icon(Icons.person_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pwd,
                obscureText: true,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '输入密码',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 16),
                  prefixIcon: const Icon(Icons.lock_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 16),
              // ✅ 记住我选项
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() {
                        _rememberMe = value ?? true;
                      });
                    },
                    activeColor: Colors.deepPurple,
                  ),
                  const Text(
                    '记住我',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '勾选后，账号信息将被保存，下次可快速切换',
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _login,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: Colors.deepPurple,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 4,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '登录',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
