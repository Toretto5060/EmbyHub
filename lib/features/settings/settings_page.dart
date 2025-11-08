import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../providers/account_history_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/fade_in_image.dart';
import '../home/bottom_nav_wrapper.dart';

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
                      leadingWidget: authData.userId != null
                          ? _UserAvatarRounded(
                              key: ValueKey(authData.userId),  // ✅ 使用 userId 作为 key 强制重建
                              userId: authData.userId,
                              username: authData.userName ?? 'U',
                              color: Colors.blue,
                            )
                          : null,
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
          final freshAccounts = allAccounts
              .where((a) => a.serverUrl == serverUrl)
              .toList();
          
          print('Modal: Found ${freshAccounts.length} accounts for $serverUrl');
          print('Total accounts: ${allAccounts.length}');
          
          String? loadingAccount;  // ✅ 当前正在切换的账号（放在外面作为闭包变量）
          
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
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: loadingAccount == null
                            ? () => Navigator.pop(context)
                            : null,  // ✅ 切换中禁用关闭按钮
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
                      leading: _UserAvatar(
                        key: ValueKey('${account.serverUrl}_${account.username}_${account.userId}'),  // ✅ 使用唯一key
                        userId: account.userId,
                        username: account.username,
                        isCurrent: isCurrent,
                      ),
                      title: Text(account.username),
                      subtitle: Text(isCurrent ? '当前登录账号' : loadingAccount == account.username ? '正在切换...' : '点击切换'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ✅ loading圈
                          if (loadingAccount == account.username)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                              offset: const Offset(8, 0),  // ✅ 向右偏移8px，抵消ListTile的右边距
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                color: Colors.red,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
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
                          ),  // Transform.translate
                        ],
                      ),
                      onTap: isCurrent || loadingAccount != null
                          ? null  // ✅ 当前账号或正在切换时禁用
                          : () async {
                              print('👆 Account tile tapped: ${account.username}');
                              
                              // ✅ 显示loading状态
                              setModalState(() {
                                loadingAccount = account.username;
                              });
                              
                              // 调用切换账号方法
                              print('👆 Calling _switchToAccount for ${account.username}');
                              final result = await _switchToAccount(outerContext, outerRef, account);
                              
                              // ✅ 切换成功
                              if (result['success'] == true) {
                                print('✅ Switch successful');
                                
                                // 关闭账号切换弹窗
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                                
                                // 等待弹窗完全关闭
                                await Future.delayed(const Duration(milliseconds: 300));
                                
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
                                          Text('已切换到 ${result['username']}'),
                                        ],
                                      ),
                                    ),
                                  );
                                  
                                  // 1秒后自动关闭成功弹窗
                                  await Future.delayed(const Duration(seconds: 1));
                                  
                                  if (outerContext.mounted) {
                                    // ✅ 使用 rootNavigator: true 确保关闭的是对话框
                                    Navigator.of(outerContext, rootNavigator: true).pop();
                                    
                                    // 等待对话框关闭动画
                                    await Future.delayed(const Duration(milliseconds: 200));
                                    
                                    // ✅ 弹窗消失后切换到媒体库 tab
                                    print('🏠 Switching to library tab (index 0)');
                                    final bottomNav = BottomNavWrapper.of(outerContext);
                                    if (bottomNav != null) {
                                      bottomNav.switchToTab(0);
                                      print('✅ Tab switched to library');
                                    } else {
                                      print('❌ BottomNavWrapper not found');
                                    }
                                  }
                                }
                              } else {
                                // 失败或取消，重置loading状态
                                print('❌ Switch failed or cancelled, resetting loading state');
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
                      child: Icon(Icons.add, color: Colors.green.shade700),
                    ),
                    title: const Text('添加新账号'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      Navigator.of(context).pop();  // 关闭 bottom sheet
                      // Wait for bottom sheet animation to complete
                      await Future.delayed(const Duration(milliseconds: 400));
                      // ✅ 使用 outerContext 导航，因为 bottom sheet 关闭后 context 可能失效
                      if (outerContext.mounted) {
                        print('Navigating to login page...');
                        outerContext.go('/connect?startAtLogin=true');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),  // Column
              );  // DraggableScrollableSheet builder
            },  // StatefulBuilder builder
          );  // StatefulBuilder
        },  // Consumer builder
      ),  // Consumer
    );  // showModalBottomSheet
  }

  Future<Map<String, dynamic>> _switchToAccount(
      BuildContext context, WidgetRef ref, AccountRecord account) async {
    print('🔄 [Switch] Starting switch to account: ${account.username}');
    print('🔄 [Switch] Server URL: ${account.serverUrl}');
    print('🔄 [Switch] Saved token: ${account.lastToken != null ? "exists" : "null"}');
    print('🔄 [Switch] Saved userId: ${account.userId}');

    try {
      // ✅ 优先使用保存的 token 和 userId
      if (account.lastToken != null && account.lastToken!.isNotEmpty &&
          account.userId != null && account.userId!.isNotEmpty) {
        print('🔑 [Switch] Trying saved token and userId for ${account.username}');
        
        final prefs = await SharedPreferences.getInstance();
        
        // 保存到 SharedPreferences
        await prefs.setString('emby_token', account.lastToken!);
        await prefs.setString('emby_user_id', account.userId!);
        await prefs.setString('emby_user_name', account.username);
        
        print('💾 [Switch] Saved to SharedPreferences: userId=${account.userId}, userName=${account.username}');

        // 验证 token 是否有效
        final api = await EmbyApi.create();
        try {
          print('📡 [Switch] Verifying token by calling getUserViews...');
          await api.getUserViews(account.userId!);
          
          print('✅ [Switch] Token valid! Switching account successfully');
          
          // ✅ 使所有 provider 失效，强制重新加载
          print('🔄 [Switch] Invalidating all providers...');
          ref.invalidate(viewsProvider);
          ref.invalidate(resumeProvider);
          ref.invalidate(latestByViewProvider);
          
          // 等待 authStateProvider 重新加载
          print('🔄 [Switch] Reloading authStateProvider...');
          await ref.read(authStateProvider.notifier).load();
          
          // 等待状态更新完成
          await Future.delayed(const Duration(milliseconds: 300));
          
          // 验证 authStateProvider 的状态
          final authState = ref.read(authStateProvider).value;
          print('✅ [Switch] AuthStateProvider reloaded:');
          print('✅ [Switch]   userId: ${authState?.userId}');
          print('✅ [Switch]   userName: ${authState?.userName}');
          print('✅ [Switch]   isLoggedIn: ${authState?.isLoggedIn}');
          
          return {'success': true, 'username': account.username};  // ✅ 返回成功
        } catch (e) {
          print('❌ [Switch] Token invalid or expired: $e');
          print('🔐 [Switch] Will require password login');
          // Token 失效，继续执行下面的密码登录逻辑
        }
      } else {
        print('⚠️ [Switch] No saved token or userId, need password login');
      }

      // ✅ Token 失效或不存在，要求输入密码
      if (context.mounted) {
        print('🔐 [Switch] Showing password dialog for ${account.username}');
        final password = await _showPasswordDialog(context, account.username);
        
        print('🔐 [Switch] Password dialog returned: ${password != null ? "password entered (length: ${password.length})" : "null (cancelled)"}');
        
        if (password == null || password.isEmpty) {
          print('❌ [Switch] User cancelled password input');
          return {'success': false, 'username': account.username};  // ✅ 返回失败（用户取消）
        }
        
        print('📡 [Switch] Calling api.authenticate() with username: ${account.username}');
        
        final api = await EmbyApi.create();
        final loginResult = await api.authenticate(
            username: account.username, password: password);
        
        print('✅ [Switch] Authentication successful!');
        print('✅ [Switch] Returned userName: ${loginResult.userName}');
        print('✅ [Switch] Returned userId: ${loginResult.userId}');
        print('✅ [Switch] Returned token: ${loginResult.token.substring(0, 10)}...');
        
        // ✅ 更新账号历史中的 token 和 userId
        await ref.read(accountHistoryProvider.notifier).addAccount(
          account.serverUrl,
          loginResult.userName,
          loginResult.token,
          userId: loginResult.userId,
        );
        print('💾 [Switch] Updated account history with new token and userId');
        
        // ✅ 使所有 provider 失效，强制重新加载
        print('🔄 [Switch] Invalidating all providers...');
        ref.invalidate(viewsProvider);
        ref.invalidate(resumeProvider);
        ref.invalidate(latestByViewProvider);
        
        // 等待 authStateProvider 重新加载
        print('🔄 [Switch] Reloading authStateProvider...');
        await ref.read(authStateProvider.notifier).load();
        
        // 等待状态更新完成
        await Future.delayed(const Duration(milliseconds: 300));
        
        // 验证 authStateProvider 的状态
        final authState = ref.read(authStateProvider).value;
        print('✅ [Switch] AuthStateProvider reloaded:');
        print('✅ [Switch]   userId: ${authState?.userId}');
        print('✅ [Switch]   userName: ${authState?.userName}');
        print('✅ [Switch]   isLoggedIn: ${authState?.isLoggedIn}');
        
        return {'success': true, 'username': loginResult.userName};  // ✅ 返回成功
      }
      
      // ✅ context not mounted
      return {'success': false, 'username': account.username};
    } catch (e, stackTrace) {
      print('❌ [Switch] Switch account failed: $e');
      print('❌ [Switch] Stack trace: $stackTrace');
      
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
      
      return {'success': false, 'username': account.username};  // ✅ 返回失败
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
                      subtitle: Text('${accounts.length} 个账号'),
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
                      Navigator.of(context).pop();  // 关闭 bottom sheet
                      // Wait for bottom sheet animation to complete
                      await Future.delayed(const Duration(milliseconds: 400));
                      // ✅ 使用 outerContext 导航，因为 bottom sheet 关闭后 context 可能失效
                      if (outerContext.mounted) {
                        print('Navigating to connect page...');
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity( 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity( 0.1),
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
    Widget? leadingWidget,  // ✅ 可选的自定义 leading widget
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity( 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: leadingWidget ?? Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity( 0.1),
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
            side: BorderSide(color: color.withOpacity( 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: Text(actionLabel),
        ),
      ),
    );
  }
}

// ✅ 用户头像组件 - 圆形（用于账号切换列表）
class _UserAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 如果没有 userId，直接显示默认头像
    if (userId == null || userId!.isEmpty) {
      return _buildDefaultAvatar();
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildDefaultAvatar();
        }

        final api = snapshot.data!;
        final avatarUrl = api.buildUserImageUrl(userId!);

        return ClipOval(
          child: SizedBox(
            width: 40,
            height: 40,
            child: EmbyFadeInImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              placeholder: _buildDefaultAvatar(),
              fadeDuration: const Duration(milliseconds: 300),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      backgroundColor: isCurrent
          ? Colors.green.shade100
          : Colors.blue.shade100,
      child: Text(
        username[0].toUpperCase(),
        style: TextStyle(
          color: isCurrent
              ? Colors.green.shade700
              : Colors.blue.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ✅ 用户头像组件 - 圆角矩形（用于设置页"当前用户"）
class _UserAvatarRounded extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 如果没有 userId，直接显示默认图标
    if (userId == null || userId!.isEmpty) {
      return _buildDefaultIcon();
    }

    return FutureBuilder<EmbyApi>(
      future: EmbyApi.create(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildDefaultIcon();
        }

        final api = snapshot.data!;
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
              fadeDuration: const Duration(milliseconds: 300),
            ),
          ),
        );
      },
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
