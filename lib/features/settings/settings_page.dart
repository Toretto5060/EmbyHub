import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/account_history_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final server = ref.watch(serverSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: auth.when(
        data: (authData) {
          if (!authData.isLoggedIn) {
            return _buildNotLoggedInView(context);
          }
          return server.when(
            data: (serverData) => ListView(
              children: [
                _buildSection(
                  context,
                  title: '账户',
                  children: [
                    _buildActionTile(
                      context,
                      icon: Icons.person_rounded,
                      title: '当前用户',
                      subtitle: authData.userName ?? '未登录',
                      color: Colors.blue,
                      actionLabel: '切换',
                      onTap: () =>
                          _showAccountSwitcher(context, ref, serverData),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: '服务器',
                  children: [
                    _buildActionTile(
                      context,
                      icon: Icons.dns_rounded,
                      title: '服务器地址',
                      subtitle: _maskServerUrl(
                          '${serverData.protocol}://${serverData.host}:${serverData.port}'),
                      color: Colors.purple,
                      actionLabel: '切换',
                      onTap: () => _showServerSwitcher(context, ref),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: '关于',
                  children: [
                    _buildInfoTile(
                      context,
                      icon: Icons.info_rounded,
                      title: '版本',
                      subtitle: '1.0.0',
                      color: Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('退出登录'),
                          content: const Text('确定要退出当前账号吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('退出'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        await ref.read(authStateProvider.notifier).clear();
                        context.go('/connect');
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade700,
                    ),
                    child: const Text(
                      '退出登录',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('错误: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('错误: $e')),
      ),
    );
  }

  String _maskServerUrl(String url) {
    final uri = Uri.parse(url);
    final host = uri.host;
    if (host.length <= 8) return url;
    final start = host.substring(0, 3);
    final end = host.substring(host.length - 3);
    return '${uri.scheme}://$start***$end:${uri.port}';
  }

  Future<void> _showAccountSwitcher(
      BuildContext context, WidgetRef ref, ServerSettings server) async {
    final serverUrl = '${server.protocol}://${server.host}:${server.port}';
    final auth = ref.read(authStateProvider).value;
    final currentUsername = auth?.userName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => Consumer(
        builder: (context, ref, child) {
          // Get fresh data inside the modal
          final allAccounts = ref.watch(accountHistoryProvider);
          final freshAccounts = allAccounts
              .where((a) => a.serverUrl == serverUrl)
              .toList();
          
          print('Modal: Found ${freshAccounts.length} accounts for $serverUrl');
          print('Total accounts: ${allAccounts.length}');
          
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Text(
                        '切换账号',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (freshAccounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('暂无历史账号',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      ...freshAccounts.map((account) {
                    final isCurrent = account.username == currentUsername;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrent
                            ? Colors.green.shade100
                            : Colors.blue.shade100,
                        child: Text(
                          account.username[0].toUpperCase(),
                          style: TextStyle(
                            color: isCurrent
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(account.username)),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(isCurrent ? '当前登录账号' : '点击登录'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (freshAccounts.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: Colors.red,
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除账号记录'),
                                    content: Text(
                                        '确定要删除 ${account.username} 的登录记录吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ref
                                      .read(accountHistoryProvider.notifier)
                                      .removeAccount(
                                          serverUrl, account.username);
                                  if (context.mounted) Navigator.pop(context);
                                }
                              },
                            ),
                          if (!isCurrent)
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: isCurrent
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await Future.delayed(const Duration(milliseconds: 400));
                              if (context.mounted) {
                                await _switchToAccount(context, ref, account);
                              }
                            },
                    );
                  }),
                  const Divider(),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Icon(Icons.add, color: Colors.green.shade700),
                    ),
                    title: const Text('添加新账号'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      Navigator.of(context).pop();
                      // Wait for bottom sheet animation to complete
                      await Future.delayed(const Duration(milliseconds: 400));
                      if (context.mounted) {
                        print('Navigating to login page...');
                        context.go('/connect?startAtLogin=true');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        );
        },
      ),
    );
  }

  Future<void> _switchToAccount(
      BuildContext context, WidgetRef ref, AccountRecord account) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show loading
    scaffoldMessenger.showSnackBar(
      const SnackBar(
          content: Text('正在切换账号...'), duration: Duration(seconds: 2)),
    );

    try {
      // Try to use saved token first
      if (account.lastToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('emby_token', account.lastToken!);
        await prefs.setString('emby_user_name', account.username);

        // Verify token is still valid
        final api = await EmbyApi.create();
        try {
          final userId = prefs.getString('emby_user_id') ?? '';
          await api.getUserViews(userId);
          await ref.read(authStateProvider.notifier).load();
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('已切换到 ${account.username}')),
          );
          return;
        } catch (e) {
          // Token invalid, need re-login
        }
      }

      // Need to login with password
      if (context.mounted) {
        final password = await _showPasswordDialog(context, account.username);
        if (password != null && password.isNotEmpty) {
          final api = await EmbyApi.create();
          await api.authenticate(
              username: account.username, password: password);
          await ref.read(authStateProvider.notifier).load();
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('已切换到 ${account.username}')),
          );
        }
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('切换失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _showPasswordDialog(
      BuildContext context, String username) async {
    final usernameController = TextEditingController(text: username);
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: usernameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }


  Future<void> _showServerSwitcher(BuildContext context, WidgetRef ref) async {
    final serverSettingsAsync = ref.read(serverSettingsProvider);
    final serverSettings = serverSettingsAsync.value;
    if (serverSettings == null) return;
    final currentServerUrl =
        '${serverSettings.protocol}://${serverSettings.host}:${serverSettings.port}';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => Consumer(
        builder: (context, ref, child) {
          // Get fresh data inside the modal
          final freshAllAccounts = ref.watch(accountHistoryProvider);
          final freshServers = freshAllAccounts
              .map((a) => a.serverUrl)
              .toSet()
              .toList();
          
          print('Modal: Found ${freshServers.length} servers');
          print('Total accounts: ${freshAllAccounts.length}');
          
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Text(
                        '切换服务器',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (freshServers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('暂无历史服务器',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      ...freshServers.map((serverUrl) {
                        final isCurrent = serverUrl == currentServerUrl;
                        final accounts = freshAllAccounts
                            .where((a) => a.serverUrl == serverUrl)
                            .toList();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrent
                            ? Colors.green.shade100
                            : Colors.purple.shade100,
                        child: Icon(
                          Icons.dns,
                          color: isCurrent
                              ? Colors.green.shade700
                              : Colors.purple.shade700,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(_maskServerUrl(serverUrl))),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('${freshAllAccounts.where((a) => a.serverUrl == serverUrl).length} 个账号'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (freshServers.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: Colors.red,
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除服务器记录'),
                                    content: Text(
                                        '确定要删除 ${_maskServerUrl(serverUrl)} 及其所有账号记录吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  final accountsToDelete = freshAllAccounts
                                      .where((a) => a.serverUrl == serverUrl)
                                      .toList();
                                  for (final account in accountsToDelete) {
                                    await ref
                                        .read(accountHistoryProvider.notifier)
                                        .removeAccount(
                                            serverUrl, account.username);
                                  }
                                  if (context.mounted) Navigator.pop(context);
                                }
                              },
                            ),
                          if (!isCurrent)
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: isCurrent
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await Future.delayed(const Duration(milliseconds: 400));
                              if (context.mounted) {
                                final accountsForServer = freshAllAccounts
                                    .where((a) => a.serverUrl == serverUrl)
                                    .toList();
                                _switchToServer(
                                    context, ref, serverUrl, accountsForServer);
                              }
                            },
                    );
                  }),
                  const Divider(),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Icon(Icons.add, color: Colors.green.shade700),
                    ),
                    title: const Text('添加新服务器'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      Navigator.of(context).pop();
                      // Wait for bottom sheet animation to complete
                      await Future.delayed(const Duration(milliseconds: 400));
                      if (context.mounted) {
                        print('Navigating to connect page...');
                        context.go('/connect');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        );
        },
      ),
    );
  }

  Future<void> _switchToServer(BuildContext context, WidgetRef ref,
      String serverUrl, List<AccountRecord> accounts) async {
    // Parse server URL and save
    final uri = Uri.parse(serverUrl);
    await ref.read(serverSettingsProvider.notifier).save(ServerSettings(
          protocol: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port.toString() : '8096',
        ));

    // Try to login with last account
    if (accounts.isNotEmpty) {
      final lastAccount = accounts.first;
      await _switchToAccount(context, ref, lastAccount);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已切换服务器，请登录')),
        );
      }
    }
  }

  Widget _buildNotLoggedInView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off_rounded,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            const Text(
              '未登录',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '连接 Emby 服务器后即可查看设置\n您也可以继续使用本地下载功能',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/connect'),
              icon: const Icon(Icons.login_rounded),
              label: const Text('去连接服务器'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context,
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: Text(actionLabel),
        ),
      ),
    );
  }
}
