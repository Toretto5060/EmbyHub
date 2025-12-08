import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/account_history_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/emby_api_provider.dart';
import '../../widgets/fade_in_image.dart';
import '../../widgets/custom_toast.dart';
import '../../utils/theme_utils.dart';
import '../home/bottom_nav_wrapper.dart';
import '../../services/server_cache_manager.dart';
import '../../providers/local_music_provider.dart';
import '../../providers/local_music_storage_provider.dart';

// ✅ 缓存刷新触发器 Provider
final cacheRefreshTriggerProvider = StateProvider<int>((ref) => 0);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final server = ref.watch(serverSettingsProvider);
    final isDark = isDarkModeFromContext(context, ref);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: AppBar(
              title: const Text('设置'),
              elevation: 0,
              backgroundColor: isDark
                  ? const Color(0xFF1C1C1E).withOpacity(0)
                  : const Color(0xFFF2F2F7).withOpacity(0),
            ),
          ),
        ),
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
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.dns_rounded,
                                  color: Colors.purple, size: 24),
                            ),
                            title: const Text(
                              '服务器地址',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              _maskServerUrl(
                                  '${serverData.protocol}://${serverData.host}:${serverData.port}'),
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: OutlinedButton(
                              onPressed: () =>
                                  _showServerSwitcher(context, ref),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.purple,
                                side: BorderSide(
                                    color: Colors.purple.withOpacity(0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                              ),
                              child: const Text('切换'),
                            ),
                          ),
                          ListTile(
                            leading: authData.userId != null
                                ? _UserAvatarRounded(
                                    key: ValueKey(authData
                                        .userId), // ✅ 使用 userId 作为 key 强制重建
                                    userId: authData.userId,
                                    username: authData.userName ?? 'U',
                                    color: Colors.blue,
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.person_rounded,
                                        color: Colors.blue, size: 24),
                                  ),
                            title: const Text(
                              '当前用户',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              authData.userName ?? '未登录',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: OutlinedButton(
                              onPressed: () => _showAccountSwitcher(
                                  context, ref, serverData),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue,
                                side: BorderSide(
                                    color: Colors.blue.withOpacity(0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                              ),
                              child: const Text('切换'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: '主题',
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Consumer(
                        builder: (context, ref, child) {
                          final currentThemeMode = ref.watch(themeModeProvider);
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildThemeButton(
                                  context,
                                  ref,
                                  AppThemeMode.dark,
                                  '深色',
                                  Icons.dark_mode_rounded,
                                  currentThemeMode == AppThemeMode.dark,
                                ),
                                _buildThemeButton(
                                  context,
                                  ref,
                                  AppThemeMode.light,
                                  '浅色',
                                  Icons.light_mode_rounded,
                                  currentThemeMode == AppThemeMode.light,
                                ),
                                _buildThemeButton(
                                  context,
                                  ref,
                                  AppThemeMode.system,
                                  '跟随系统',
                                  Icons.brightness_auto_rounded,
                                  currentThemeMode == AppThemeMode.system,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: '启动页面',
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const _StartupPageSelector(),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: '播放设置',
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const _QualityStrategySelector(),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: '缓存管理',
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const _CacheManager(),
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
                        // ✅ 使所有 provider 失效
                        ref.invalidate(viewsProvider);
                        ref.invalidate(resumeProvider);
                        ref.invalidate(latestByViewProvider);

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

    // ✅ 保存外层 context 和 ref
    final outerContext = context;
    final outerRef = ref;

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
          final freshAccounts =
              allAccounts.where((a) => a.serverUrl == serverUrl).toList();

          String? loadingAccount; // ✅ 当前正在切换的账号（放在外面作为闭包变量）

          return StatefulBuilder(
            builder: (context, setModalState) {
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
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: loadingAccount == null
                                ? () => Navigator.pop(context)
                                : null, // ✅ 切换中禁用关闭按钮
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
                            final isCurrent =
                                account.username == currentUsername;
                            return ListTile(
                              leading: _UserAvatar(
                                key: ValueKey(
                                    '${account.serverUrl}_${account.username}_${account.userId}'), // ✅ 使用唯一key
                                userId: account.userId,
                                username: account.username,
                                isCurrent: isCurrent,
                              ),
                              title: Text(account.username),
                              subtitle: Text(isCurrent
                                  ? '当前登录账号'
                                  : loadingAccount == account.username
                                      ? '正在切换...'
                                      : '点击切换'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // ✅ loading圈
                                  if (loadingAccount == account.username)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  // ✅ "当前"标识
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
                                  // ✅ 删除按钮（只在有多个账号时显示）
                                  if (freshAccounts.length > 1 && !isCurrent)
                                    Transform.translate(
                                      offset: const Offset(
                                          8, 0), // ✅ 向右偏移8px，抵消ListTile的右边距
                                      child: IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 20),
                                        color: Colors.red,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('删除账号记录'),
                                              content: Text(
                                                  '确定要删除 ${account.username} 的登录记录吗？'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child: const Text('取消'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  style: FilledButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.red),
                                                  child: const Text('删除'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            // ✅ 清除该用户的缓存（图片和数据）
                                            if (account.userId != null &&
                                                account.userId!.isNotEmpty) {
                                              final uri = Uri.parse(serverUrl);
                                              await ServerCacheManager
                                                  .deleteUserCache(
                                                      account.userId!,
                                                      uri.host);
                                            }

                                            // 删除账号记录
                                            await ref
                                                .read(accountHistoryProvider
                                                    .notifier)
                                                .removeAccount(serverUrl,
                                                    account.username);
                                            if (context.mounted)
                                              Navigator.pop(context);
                                          }
                                        },
                                      ),
                                    ), // Transform.translate
                                ],
                              ),
                              onTap: isCurrent || loadingAccount != null
                                  ? null // ✅ 当前账号或正在切换时禁用
                                  : () async {
                                      // ✅ 显示loading状态
                                      setModalState(() {
                                        loadingAccount = account.username;
                                      });

                                      // 调用切换账号方法
                                      final result = await _switchToAccount(
                                          outerContext, outerRef, account);

                                      // ✅ 切换成功
                                      if (result['success'] == true) {
                                        // 关闭账号切换弹窗
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                        }

                                        // 等待弹窗完全关闭
                                        await Future.delayed(
                                            const Duration(milliseconds: 300));

                                        // ✅ 在设置页显示成功弹窗
                                        if (outerContext.mounted) {
                                          showDialog(
                                            context: outerContext,
                                            barrierDismissible: false,
                                            builder: (ctx) => AlertDialog(
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                    size: 48,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                      '已切换到 ${result['username']}'),
                                                ],
                                              ),
                                            ),
                                          );

                                          // 1秒后自动关闭成功弹窗
                                          await Future.delayed(
                                              const Duration(seconds: 1));

                                          if (outerContext.mounted) {
                                            // ✅ 使用 rootNavigator: true 确保关闭的是对话框
                                            Navigator.of(outerContext,
                                                    rootNavigator: true)
                                                .pop();

                                            // 等待对话框关闭动画
                                            await Future.delayed(const Duration(
                                                milliseconds: 200));

                                            // ✅ 弹窗消失后切换到媒体库 tab

                                            final bottomNav =
                                                BottomNavWrapper.of(
                                                    outerContext);
                                            if (bottomNav != null) {
                                              bottomNav.switchToTab(0);
                                            } else {}
                                          }
                                        }
                                      } else {
                                        // 失败或取消，重置loading状态
                                        setModalState(() {
                                          loadingAccount = null;
                                        });
                                      }
                                    },
                            );
                          }),
                          const Divider(),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade100,
                              child:
                                  Icon(Icons.add, color: Colors.green.shade700),
                            ),
                            title: const Text('添加新账号'),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () async {
                              Navigator.of(context).pop(); // 关闭 bottom sheet
                              // Wait for bottom sheet animation to complete
                              await Future.delayed(
                                  const Duration(milliseconds: 400));
                              // ✅ 使用 outerContext 导航，因为 bottom sheet 关闭后 context 可能失效
                              if (outerContext.mounted) {
                                outerContext.go('/connect?startAtLogin=true');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ), // Column
              ); // DraggableScrollableSheet builder
            }, // StatefulBuilder builder
          ); // StatefulBuilder
        }, // Consumer builder
      ), // Consumer
    ); // showModalBottomSheet
  }

  Future<Map<String, dynamic>> _switchToAccount(
      BuildContext context, WidgetRef ref, AccountRecord account) async {
    try {
      // ✅ 优先使用保存的 token 和 userId
      if (account.lastToken != null &&
          account.lastToken!.isNotEmpty &&
          account.userId != null &&
          account.userId!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();

        // 保存到 SharedPreferences
        await prefs.setString('emby_token', account.lastToken!);
        await prefs.setString('emby_user_id', account.userId!);
        await prefs.setString('emby_user_name', account.username);

        // 验证 token 是否有效
        final api = await EmbyApi.create();
        try {
          await api.getUserViews(account.userId!);

          // ✅ 使所有 provider 失效，强制重新加载
          ref.invalidate(viewsProvider);
          ref.invalidate(resumeProvider);
          ref.invalidate(latestByViewProvider);

          // 等待 authStateProvider 重新加载
          await ref.read(authStateProvider.notifier).load();

          // 等待状态更新完成
          await Future.delayed(const Duration(milliseconds: 300));

          // ✅ 验证完成，返回成功
          return {'success': true, 'username': account.username};
        } catch (e) {
          // Token 失效，继续执行下面的密码登录逻辑
        }
      } else {}

      // ✅ Token 失效或不存在，要求输入密码
      if (context.mounted) {
        final password = await _showPasswordDialog(context, account.username);

        if (password == null || password.isEmpty) {
          return {
            'success': false,
            'username': account.username
          }; // ✅ 返回失败（用户取消）
        }

        final api = await EmbyApi.create();
        final loginResult = await api.authenticate(
            username: account.username, password: password);

        // ✅ 更新账号历史中的 token 和 userId
        await ref.read(accountHistoryProvider.notifier).addAccount(
              account.serverUrl,
              loginResult.userName,
              loginResult.token,
              userId: loginResult.userId,
            );

        // ✅ 使所有 provider 失效，强制重新加载
        ref.invalidate(viewsProvider);
        ref.invalidate(resumeProvider);
        ref.invalidate(latestByViewProvider);

        // 等待 authStateProvider 重新加载
        await ref.read(authStateProvider.notifier).load();

        // 等待状态更新完成
        await Future.delayed(const Duration(milliseconds: 300));

        // ✅ 验证完成，返回成功
        return {'success': true, 'username': loginResult.userName};
      }

      // ✅ context not mounted
      return {'success': false, 'username': account.username};
    } catch (e) {
      // ✅ 显示居中错误提示
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('切换失败'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }

      return {'success': false, 'username': account.username}; // ✅ 返回失败
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

    // ✅ 保存外层 context
    final outerContext = context;

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
          final freshServers =
              freshAllAccounts.map((a) => a.serverUrl).toSet().toList();

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
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
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
                          subtitle: Text('${accounts.length} 个账号'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (freshServers.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
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
                                      // ✅ 清除该服务器的所有缓存（图片和数据）
                                      final uri = Uri.parse(serverUrl);
                                      await ServerCacheManager
                                          .deleteServerCache(uri.host);

                                      // 删除账号记录
                                      final accountsToDelete = freshAllAccounts
                                          .where(
                                              (a) => a.serverUrl == serverUrl)
                                          .toList();
                                      for (final account in accountsToDelete) {
                                        await ref
                                            .read(
                                                accountHistoryProvider.notifier)
                                            .removeAccount(
                                                serverUrl, account.username);
                                      }
                                      if (context.mounted)
                                        Navigator.pop(context);
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
                                  await Future.delayed(
                                      const Duration(milliseconds: 400));
                                  if (context.mounted) {
                                    final accountsForServer = freshAllAccounts
                                        .where((a) => a.serverUrl == serverUrl)
                                        .toList();
                                    _switchToServer(context, ref, serverUrl,
                                        accountsForServer);
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
                          Navigator.of(context).pop(); // 关闭 bottom sheet
                          // Wait for bottom sheet animation to complete
                          await Future.delayed(
                              const Duration(milliseconds: 400));
                          // ✅ 使用 outerContext 导航，因为 bottom sheet 关闭后 context 可能失效
                          if (outerContext.mounted) {
                            outerContext.go('/connect');
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
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
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

  // ✅ 构建主题选择按钮
  Widget _buildThemeButton(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode mode,
    String label,
    IconData icon,
    bool isSelected,
  ) {
    final isDark = isDarkModeFromContext(context, ref);
    final selectedColor = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          onPressed: () {
            ref.read(themeModeProvider.notifier).setThemeMode(mode);
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: isSelected
                ? selectedColor.withOpacity(0.1)
                : Colors.transparent,
            foregroundColor: isSelected ? selectedColor : null,
            side: BorderSide(
              color: isSelected
                  ? selectedColor
                  : (isDark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.2)),
              width: isSelected ? 2 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ✅ 用户头像组件 - 圆形（用于账号切换列表）
class _UserAvatar extends ConsumerWidget {
  const _UserAvatar({
    super.key,
    required this.username,
    required this.isCurrent,
    this.userId,
  });

  final String? userId;
  final String username;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 如果没有 userId，直接显示默认头像
    if (userId == null || userId!.isEmpty) {
      return _buildDefaultAvatar();
    }

    final apiAsync = ref.watch(embyApiProvider);

    // ✅ 立即显示默认头像，避免闪烁
    return apiAsync.when(
      data: (api) {
        final avatarUrl = api.buildUserImageUrl(userId!);

        return ClipOval(
          child: SizedBox(
            width: 40,
            height: 40,
            child: EmbyFadeInImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              placeholder: _buildDefaultAvatar(),
              fadeDuration: const Duration(milliseconds: 200),
            ),
          ),
        );
      },
      loading: () => _buildDefaultAvatar(),
      error: (_, __) => _buildDefaultAvatar(),
    );
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      backgroundColor: isCurrent ? Colors.green.shade100 : Colors.blue.shade100,
      child: Text(
        username[0].toUpperCase(),
        style: TextStyle(
          color: isCurrent ? Colors.green.shade700 : Colors.blue.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ✅ 用户头像组件 - 圆角矩形（用于设置页"当前用户"）
class _UserAvatarRounded extends ConsumerWidget {
  const _UserAvatarRounded({
    super.key,
    required this.username,
    required this.color,
    this.userId,
  });

  final String? userId;
  final String username;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 如果没有 userId，直接显示默认图标
    if (userId == null || userId!.isEmpty) {
      return _buildDefaultIcon();
    }

    final apiAsync = ref.watch(embyApiProvider);

    // ✅ 立即显示默认图标，避免闪烁
    return apiAsync.when(
      data: (api) {
        final avatarUrl = api.buildUserImageUrl(userId!);

        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: EmbyFadeInImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              placeholder: _buildDefaultIcon(),
              fadeDuration: const Duration(milliseconds: 200),
            ),
          ),
        );
      },
      loading: () => _buildDefaultIcon(),
      error: (_, __) => _buildDefaultIcon(),
    );
  }

  Widget _buildDefaultIcon() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.person_rounded, color: color, size: 24),
    );
  }
}

// ✅ 启动页面选择器
class _StartupPageSelector extends StatefulWidget {
  const _StartupPageSelector();

  @override
  State<_StartupPageSelector> createState() => _StartupPageSelectorState();
}

class _StartupPageSelectorState extends State<_StartupPageSelector> {
  StartupPageMode _currentMode = StartupPageMode.defaultMode;

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    final mode = await StartupPageManager.getMode();
    if (mounted) {
      setState(() {
        _currentMode = mode;
      });
    }
  }

  Future<void> _changeMode(StartupPageMode newMode) async {
    if (_currentMode == newMode) return;

    await StartupPageManager.setMode(newMode);

    if (mounted) {
      setState(() {
        _currentMode = newMode;
      });
    }
  }

  String _getModeLabel(StartupPageMode mode) {
    switch (mode) {
      case StartupPageMode.defaultMode:
        return '默认';
      case StartupPageMode.music:
        return '音乐';
      case StartupPageMode.live:
        return '直播';
    }
  }

  String _getModeDescription(StartupPageMode mode) {
    switch (mode) {
      case StartupPageMode.defaultMode:
        return '正常进入首页，如果上次退出时在音乐页面则恢复';
      case StartupPageMode.music:
        return '每次启动直接进入音乐播放器，跳过开屏动画';
      case StartupPageMode.live:
        return '每次启动直接进入电视直播（暂未实现）';
    }
  }

  IconData _getModeIcon(StartupPageMode mode) {
    switch (mode) {
      case StartupPageMode.defaultMode:
        return Icons.home_rounded;
      case StartupPageMode.music:
        return Icons.music_note_rounded;
      case StartupPageMode.live:
        return Icons.live_tv_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选项列表
          ...StartupPageMode.values.map((mode) {
            final isSelected = _currentMode == mode;
            // 直播功能暂未实现，显示为禁用状态
            final isDisabled = mode == StartupPageMode.live;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: isDisabled ? null : () => _changeMode(mode),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.teal.withOpacity(0.1)
                        : (isDisabled
                            ? Colors.grey.withOpacity(0.05)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.teal.withOpacity(0.5)
                          : (isDisabled
                              ? Colors.grey.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2)),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getModeIcon(mode),
                        color: isDisabled
                            ? Colors.grey.withOpacity(0.5)
                            : (isSelected ? Colors.teal : Colors.grey),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _getModeLabel(mode),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isDisabled
                                        ? Colors.grey.withOpacity(0.5)
                                        : (isSelected ? Colors.teal : null),
                                  ),
                                ),
                                if (isDisabled) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '待开发',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getModeDescription(mode),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDisabled
                                    ? Colors.grey.withOpacity(0.4)
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.teal, size: 22),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ✅ 画质策略选择器（StatefulWidget）
class _QualityStrategySelector extends StatefulWidget {
  const _QualityStrategySelector();

  @override
  State<_QualityStrategySelector> createState() =>
      _QualityStrategySelectorState();
}

class _QualityStrategySelectorState extends State<_QualityStrategySelector> {
  String _currentStrategy = 'quality';

  @override
  void initState() {
    super.initState();
    _loadStrategy();
  }

  Future<void> _loadStrategy() async {
    final prefs = await SharedPreferences.getInstance();
    final strategy = prefs.getString('playback_quality_strategy') ?? 'quality';
    if (mounted) {
      setState(() {
        _currentStrategy = strategy;
      });
    }
  }

  Future<void> _changeStrategy(String newStrategy, String label) async {
    final prefs = await SharedPreferences.getInstance();
    final oldStrategy =
        prefs.getString('playback_quality_strategy') ?? 'quality';

    // ✅ 如果策略相同，不做任何操作
    if (oldStrategy == newStrategy) return;

    // ✅ 显示确认对话框（类似切换用户的样式）
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换画质策略'),
        content: Text(
          '切换到「$label」后：\n\n'
          '• 将清空所有视频的手动画质选择\n'
          '• 正在播放的视频需要重新播放才能生效\n'
          '• 新播放的视频将自动使用新策略\n\n'
          '确定要切换吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // ✅ 保存新策略
    await prefs.setString('playback_quality_strategy', newStrategy);

    // ✅ 清空所有 selected_quality_* 和 manual_quality_* 的保存
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('selected_quality_') ||
          key.startsWith('manual_quality_')) {
        await prefs.remove(key);
      }
    }

    // ✅ 更新状态
    if (mounted) {
      setState(() {
        _currentStrategy = newStrategy;
      });
    }
  }

  String _getDescription(String strategy) {
    switch (strategy) {
      case 'quality':
        return '总是选择最高画质，适合高速网络环境';
      case 'speed':
        return '优先保证流畅播放，适合网络较慢时使用';
      case 'auto':
        return '使用视频原始画质，平衡质量与速度';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '画质策略',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStrategyButton(
                'quality',
                '质量优先',
                Icons.hd_rounded,
                _currentStrategy == 'quality',
              ),
              _buildStrategyButton(
                'auto',
                '自动',
                Icons.auto_awesome_rounded,
                _currentStrategy == 'auto',
              ),
              _buildStrategyButton(
                'speed',
                '速度优先',
                Icons.speed_rounded,
                _currentStrategy == 'speed',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getDescription(_currentStrategy),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyButton(
    String strategy,
    String label,
    IconData icon,
    bool isSelected,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _changeStrategy(strategy, label),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black.withOpacity(0.2)),
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ 缓存管理器组件
class _CacheManager extends ConsumerStatefulWidget {
  const _CacheManager();

  @override
  ConsumerState<_CacheManager> createState() => _CacheManagerState();
}

class _CacheManagerState extends ConsumerState<_CacheManager> {
  String _imageCacheSize = '计算中...';
  String _dataCacheSize = '计算中...';
  String _musicCacheInfo = '计算中...';
  bool _isLoading = false;
  bool _isLoadingCacheSize = false;
  int _lastTriggerValue = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    // ✅ 防止重复加载
    if (_isLoadingCacheSize) return;
    _isLoadingCacheSize = true;

    try {
      // ✅ 获取当前用户ID
      final auth = ref.read(authStateProvider).value;
      final userId = auth?.userId;

      // ✅ 图片缓存是服务器级别的（所有用户共享），不需要传userId
      final imageSize = await ServerCacheManager.getImageCacheSize();
      // ✅ 数据缓存是用户级别的，需要传userId
      final dataSize =
          await ServerCacheManager.getDataCacheSize(userId: userId);
      // ✅ 获取当前服务器的音乐缓存大小
      final musicCacheSize = await _getCurrentServerMusicCacheSize();

      if (mounted) {
        setState(() {
          _imageCacheSize = ServerCacheManager.formatCacheSize(imageSize);
          _dataCacheSize = ServerCacheManager.formatCacheSize(dataSize);
          _musicCacheInfo = ServerCacheManager.formatCacheSize(musicCacheSize);
        });
      }
    } finally {
      _isLoadingCacheSize = false;
    }
  }

  /// 获取当前服务器的音乐缓存大小（字节）
  Future<int> _getCurrentServerMusicCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverId = prefs.getString('emby_server_id') ?? 'default';
      final keys = prefs.getKeys();
      int totalSize = 0;

      for (final key in keys) {
        // key 格式: server_music_{serverId}_{libraryId}
        if (key.startsWith('server_music_${serverId}_')) {
          final cacheJson = prefs.getString(key);
          if (cacheJson != null && cacheJson.isNotEmpty) {
            // 计算 JSON 字符串的字节大小
            totalSize += cacheJson.length * 2; // UTF-16 编码，每个字符约2字节
          }
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// 检查当前用户是否有音乐媒体库
  bool _hasMusicLibrary(WidgetRef ref) {
    // 优先使用 serverMusicLibraryProvider（如果已经初始化）
    final serverMusicLib = ref.watch(serverMusicLibraryProvider);
    if (serverMusicLib.isAvailable) {
      return true;
    }

    // 如果 serverMusicLibraryProvider 未初始化，直接检查 viewsProvider
    final viewsAsync = ref.watch(viewsProvider);
    return viewsAsync.maybeWhen(
      data: (views) => views.any((v) => v.collectionType == 'music'),
      orElse: () => false,
    );
  }

  Future<void> _clearImageCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除图片缓存'),
        content: const Text(
            '确定要清除当前服务器的图片缓存吗？\n\n清除后图片将重新从服务器加载。\n注意：此操作会清除当前设备该服务器所有用户的图片缓存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    // ✅ 图片缓存是服务器级别的，所有用户共享
    await ServerCacheManager.clearImageCache();

    // ✅ 同时清除内存中的图片缓存
    clearImageMemoryCache();

    if (mounted) {
      setState(() => _isLoading = false);
      await _loadCacheSize();

      CustomToast.showSuccess(context, '图片缓存已清除');
    }
  }

  Future<void> _clearDataCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除数据缓存'),
        content: const Text('确定要清除当前用户的数据缓存吗？\n\n清除后页面数据将重新从服务器加载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    // ✅ 获取当前用户ID
    final auth = ref.read(authStateProvider).value;
    final userId = auth?.userId;

    await ServerCacheManager.clearDataCache(userId: userId);

    if (mounted) {
      setState(() => _isLoading = false);
      await _loadCacheSize();

      CustomToast.showSuccess(context, '数据缓存已清除');
    }
  }

  /// 清除媒体库音乐缓存（只清除服务器音乐缓存，不影响本地音乐）
  Future<void> _clearMusicCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('音乐缓存'),
        content: const Text(
            '确定要清除当前服务器的媒体库音乐缓存吗？\n\n• 只会清除当前服务器的音乐列表缓存\n• 不会影响本地音乐数据\n• 清除后将重新从服务器加载音乐列表'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    // ✅ 只清除服务器音乐缓存（server_music_ 开头的键）
    await ref.read(localMusicStorageProvider.notifier).clearServerMusicCache();

    if (mounted) {
      setState(() => _isLoading = false);
      await _loadCacheSize();

      CustomToast.showSuccess(context, '媒体库音乐缓存已清除');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 监听缓存刷新触发器
    final triggerValue = ref.watch(cacheRefreshTriggerProvider);

    // ✅ 当触发器值变化时，刷新缓存大小
    if (triggerValue != _lastTriggerValue) {
      _lastTriggerValue = triggerValue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadCacheSize();
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图片缓存
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.image_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '图片缓存',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _imageCacheSize,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _isLoading ? null : _clearImageCache,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('清除'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // 数据缓存
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.storage_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '数据缓存',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dataCacheSize,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _isLoading ? null : _clearDataCache,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('清除'),
              ),
            ],
          ),
          // 媒体库音乐缓存 - 仅在当前用户有音乐媒体库时显示
          if (_hasMusicLibrary(ref)) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '音乐缓存',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _musicCacheInfo,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _isLoading ? null : _clearMusicCache,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('清除'),
                ),
              ],
            ),
          ],
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
