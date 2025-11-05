import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/emby_api.dart';
import '../../providers/settings_provider.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  String _protocol = 'http';
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '8096');
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(serverSettingsProvider);
    settings.whenData((value) {
      setState(() {
        _protocol = value.protocol;
        _host.text = value.host;
        _port.text = value.port;
      });
    });
  }

  Future<void> _connect() async {
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
      await api.systemInfo();
      // if username & password provided -> login
      if (_user.text.trim().isNotEmpty && _pwd.text.isNotEmpty) {
        await api.authenticate(
            username: _user.text.trim(), password: _pwd.text);
      }
      if (!mounted) return;
      context.go('/');
    } on DioException catch (e) {
      setState(() {
        _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('连接 Emby 服务器')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('协议', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            CupertinoSegmentedControl<String>(
              groupValue: _protocol,
              children: const {
                'http': Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('HTTP')),
                'https': Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('HTTPS')),
              },
              onValueChanged: (v) => setState(() => _protocol = v),
            ),
            const SizedBox(height: 16),
            const Text('域名 / IP', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            CupertinoTextField(
                controller: _host, placeholder: 'example.com 或 192.168.x.x'),
            const SizedBox(height: 16),
            const Text('端口', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            CupertinoTextField(
                controller: _port,
                placeholder: '8096 / 8920',
                keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            const Text('用户名（可选）', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            CupertinoTextField(controller: _user, placeholder: '如需认证请输入'),
            const SizedBox(height: 16),
            const Text('密码（可选）', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            CupertinoTextField(
                controller: _pwd, placeholder: '不会保存明文到服务器', obscureText: true),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(_error!,
                  style: const TextStyle(color: CupertinoColors.systemRed)),
              const SizedBox(height: 8),
            ],
            CupertinoButton.filled(
              onPressed: _loading ? null : _connect,
              child: _loading
                  ? const CupertinoActivityIndicator()
                  : const Text('连接'),
            ),
          ],
        ),
      ),
    );
  }
}
