import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/emby_api.dart';
import '../../utils/status_bar_manager.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  Timer? _timeoutTimer;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    // 创建动画控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true); // 循环播放，往返

    // 缩放动画：0.9 到 1.1
    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // 旋转动画：轻微旋转
    _rotationAnimation = Tween<double>(
      begin: -0.05,
      end: 0.05,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _initApp();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查是否有保存的服务器信息
      final protocol = prefs.getString('server_protocol');
      final host = prefs.getString('server_host');
      final port = prefs.getString('server_port');

      // 如果没有保存的服务器信息，进入连接页
      if (protocol == null ||
          protocol.isEmpty ||
          host == null ||
          host.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          context.pushReplacement('/connect');
        }
        return;
      }

      // 有保存的服务器信息，检测服务器连通性
      await _testServerConnection();
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = '初始化失败: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _testServerConnection() async {
    // 设置60秒超时（与 API 超时时间一致）
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && _isLoading) {
        setState(() {
          _hasError = true;
          _errorMessage = '连接超时（60秒）';
          _isLoading = false;
        });
      }
    });

    try {
      // 预加载首页需要的数据

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('emby_user_id');

      // 如果没有登录，只检测服务器连通性
      if (userId == null || userId.isEmpty) {
        final api = await EmbyApi.create();
        await api.systemInfo();

        _timeoutTimer?.cancel();
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          context.pushReplacement('/');
        }
        return;
      }

      // 有登录信息，预加载数据

      final api = await EmbyApi.create();

      // ✅ 并行预加载：媒体库列表 + 继续观看 + 服务器信息
      final viewsFuture = api.getUserViews(userId);
      final resumeFuture = api.getResumeItems(userId);
      final serverInfoFuture = api.systemInfo();

      final results = await Future.wait([
        viewsFuture,
        resumeFuture,
        serverInfoFuture,
      ]);

      final views = results[0] as List<ViewInfo>;
      final resumeItems = results[1] as List<ItemInfo>;
      final serverInfo = results[2] as Map<String, dynamic>;

      final serverName = serverInfo['ServerName'] as String?;

      // ✅ 保存服务器名称
      if (serverName != null && serverName.isNotEmpty) {
        await prefs.setString('server_name', serverName);
      }

      // 取消超时定时器
      _timeoutTimer?.cancel();

      // 等待一小段时间再跳转
      await Future.delayed(const Duration(milliseconds: 500));

      // 数据预加载成功，跳转到首页
      // 首页 ref.watch 时会直接使用缓存的数据
      if (mounted) {
        context.pushReplacement('/');
      }
    } catch (e) {
      _timeoutTimer?.cancel();

      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = _parseErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  String _parseErrorMessage(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('Failed host lookup') ||
        errorStr.contains('Network is unreachable')) {
      return '无法连接到服务器\n请检查网络连接';
    } else if (errorStr.contains('Connection timed out')) {
      return '连接超时\n服务器无响应';
    } else if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
      return '用户名或密码错误';
    } else if (errorStr.contains('404')) {
      return '服务器地址错误';
    } else {
      return '登录失败\n$errorStr';
    }
  }

  void _retry() {
    _initApp();
  }

  void _skip() {
    // 取消所有正在进行的请求
    _timeoutTimer?.cancel();

    // 直接进入首页
    context.pushReplacement('/');
  }

  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );

    return StatusBarStyleScope(
        style: overlay,
        child: Scaffold(
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
                // 主要内容 - 全屏居中的动态图标
                if (_isLoading)
                  Center(
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Transform.rotate(
                            angle: _rotationAnimation.value,
                            child: const Icon(
                              Icons.movie_filter_rounded,
                              size: 120,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // 底部跳过按钮（加载中时显示）
                if (_isLoading)
                  Positioned(
                    bottom: 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CupertinoButton(
                        onPressed: _skip,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const DefaultTextStyle(
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            child: Text('跳过'),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 错误显示（全屏居中）
                if (_hasError && _errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_triangle_fill,
                            size: 80,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 32),
                          DefaultTextStyle(
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              height: 1.6,
                            ),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 48),

                          // 重试和跳过按钮
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  color: Colors.white.withValues(alpha: 0.2),
                                  onPressed: _skip,
                                  child: const DefaultTextStyle(
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    child: Text('跳过'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: CupertinoButton(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  color: Colors.white,
                                  onPressed: _retry,
                                  child: DefaultTextStyle(
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.purple.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    child: const Text('重试'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
  }
}
