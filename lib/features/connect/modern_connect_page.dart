import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/account_history_provider.dart';
import '../../providers/settings_provider.dart';

class ModernConnectPage extends ConsumerStatefulWidget {
  const ModernConnectPage({super.key});

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
  final TextEditingController _port = TextEditingController(text: '8096');
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pwd = TextEditingController();

  bool _serverConnected = false;
  bool _loading = false;
  String? _error;
  String? _serverName;

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
        _port.text = value.port;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(serverSettingsProvider.notifier).save(ServerSettings(
          protocol: _protocol,
          host: _host.text.trim(),
          port: _port.text.trim()));
      final api = await EmbyApi.create();
      final info = await api.systemInfo();
      setState(() {
        _serverConnected = true;
        _serverName = info['ServerName'] as String? ?? 'Emby Server';
      });
    } on dio.DioException catch (e) {
      setState(() {
        _error = e.response?.statusMessage ?? e.message ?? '连接失败';
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pwd.text.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await EmbyApi.create();
      final result = await api.authenticate(username: _user.text.trim(), password: _pwd.text);
      
      // Save to account history
      final serverSettingsAsync = ref.read(serverSettingsProvider);
      final serverSettings = serverSettingsAsync.value;
      if (serverSettings != null) {
        final serverUrl = '${serverSettings.protocol}://${serverSettings.host}:${serverSettings.port}';
        await ref.read(accountHistoryProvider.notifier).addAccount(
          serverUrl,
          result.userName,
          result.token,
        );
      }
      
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
      setState(() {
        _error = errorMsg;
      });
    } catch (e) {
      setState(() {
        _error = '登录失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _resetConnection() {
    setState(() {
      _serverConnected = false;
      _serverName = null;
      _error = null;
      _user.clear();
      _pwd.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_serverConnected)
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_rounded, color: Colors.white),
              label: const Text('跳过', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            )
          else
            TextButton.icon(
              onPressed: _loading ? null : _login,
              icon: const Icon(Icons.login_rounded, color: Colors.white),
              label: const Text('登录', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
        ],
      ),
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 60),
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
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
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
            size: 64,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'EmbyHub',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '让娱乐触手可及',
          style: TextStyle(
            fontSize: 16,
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
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'example.com 或 192.168.1.100',
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
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: '端口',
                  hintText: '8096',
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
              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: '用户名',
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
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: '密码',
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
              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '点击右上角"登录"按钮',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
