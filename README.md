# EmbyHub

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Android-10+-3DDC84?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

一个现代化的 Emby 客户端，专为 Android 平台打造，提供流畅的媒体浏览和播放体验。

## ✨ 特性

### 🎬 媒体管理
- **多服务器支持**：连接并管理多个 Emby 服务器
- **多账户切换**：快速切换不同账户，支持账户历史记录
- **媒体库浏览**：按类型（电影、电视剧、动漫等）浏览媒体内容
- **继续观看**：显示正在观看的内容，快速继续播放
- **最新内容**：查看每个媒体库的最新添加内容

### 🎥 播放器
- **现代化播放器**：基于 media_kit 的强大播放引擎
- **HLS 自适应流**：全速缓冲，流畅播放
- **播放控制**：
  - 播放/暂停、快进/快退
  - 剧集导航（上一集/下一集）
  - 倍速播放（支持记忆）
  - 进度条拖动
  - 音频/字幕选择
  - 画中画（PiP）模式
  - 视频源信息显示

### 🎨 用户界面
- **Material Design 3**：现代化 UI 设计
- **深色模式支持**：自动适配系统主题
- **沉浸式体验**：透明状态栏，全屏体验
- **优雅动画**：流畅的页面转场和交互动画
- **渐变主题**：美观的紫粉渐变配色

### 🔐 安全与隐私
- **服务器地址脱敏**：保护隐私信息
- **本地存储**：账户信息安全存储
- **HTTPS 支持**：安全连接选项

### 📥 离线功能
- **收藏/下载**：支持本地下载功能（开发中）
- **离线访问**：未登录也能访问本地内容

## 📱 系统要求

- **Android**: 10 (API 29) 及以上
- **架构支持**: 
  - ARM64 (arm64-v8a)
  - ARMv7 (armeabi-v7a)
  - x86_64
  - x86

## 🚀 开始使用

### 安装

1. 从 [Releases](../../releases) 页面下载对应架构的 APK
2. 安装到您的 Android 设备
3. 首次启动时输入 Emby 服务器信息
4. 登录并开始享受！

### 服务器连接

1. 选择协议（HTTP/HTTPS）
2. 输入服务器地址（域名或 IP）
3. 输入端口（默认 8096）
4. 点击"连接服务器"
5. 输入用户名和密码登录

## 🛠️ 开发

### 环境要求

- Flutter SDK 3.x
- Dart SDK
- Android Studio / VS Code
- Android SDK 29+

### 构建

```bash
# 获取依赖
flutter pub get

# 运行调试版本
flutter run

# 构建发布版本（分架构）
flutter build apk --release --split-per-abi

# 构建发布版本（通用）
flutter build apk --release
```

### 项目结构

```
lib/
├── core/              # 核心功能
│   └── emby_api.dart # Emby API 封装
├── features/          # 功能模块
│   ├── connect/      # 服务器连接
│   ├── home/         # 首页
│   ├── library/      # 媒体库
│   ├── item/         # 媒体详情
│   ├── player/       # 播放器
│   └── settings/     # 设置
├── providers/         # 状态管理
│   ├── settings_provider.dart
│   └── account_history_provider.dart
├── router.dart       # 路由配置
├── app.dart          # 应用入口
└── main.dart         # 主函数
```

## 📦 主要依赖

- **flutter_riverpod**: 状态管理
- **go_router**: 路由管理
- **dio**: HTTP 网络请求
- **media_kit**: 视频播放
- **shared_preferences**: 本地存储

## 🎯 路线图

- [x] 基础媒体库浏览
- [x] 视频播放功能
- [x] 多服务器/多账户管理
- [x] 继续观看功能
- [x] 深色模式支持
- [ ] 下载功能
- [ ] 搜索功能
- [ ] 字幕下载
- [ ] Chromecast 支持
- [ ] iOS 版本

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [Emby](https://emby.media/) - 优秀的媒体服务器软件
- [Flutter](https://flutter.dev/) - 跨平台 UI 框架
- [media_kit](https://pub.dev/packages/media_kit) - 强大的媒体播放库

## 📧 联系

如有问题或建议，请提交 Issue。

---

**注意**: 本项目为非官方客户端，与 Emby 官方无关。
