/// 修改 Android 包名的自动化脚本
///
/// 使用方法：
/// 1. 修改下方的 newPackageName 变量为你想要的新包名
/// 2. 在 emby_client 目录下运行: dart scripts/change_package_name.dart
/// 3. 运行 flutter clean && flutter pub get && flutter build apk --release

import 'dart:io';

// ============================================================
// 🔧 只需要修改这里的包名！
// ============================================================
const String newPackageName = 'com.tencent.qqmusic'; // ← 修改为你的新包名
// ============================================================

const String oldPackageName = 'com.toretto.embyhub';
// const String oldPackageName = 'com.toretto.embyhub';

void main() async {
  print('🚀 开始修改包名: $oldPackageName → $newPackageName\n');

  if (newPackageName == oldPackageName) {
    print('⚠️  新包名与旧包名相同，无需修改');
    return;
  }

  // 验证包名格式
  if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$')
      .hasMatch(newPackageName)) {
    print('❌ 包名格式不正确！');
    print('   包名必须是小写字母开头，由小写字母、数字、下划线组成，用点号分隔');
    print('   例如: com.example.myapp');
    exit(1);
  }

  final scriptDir = File(Platform.script.toFilePath()).parent;
  final projectDir = scriptDir.parent;

  print('📁 项目目录: ${projectDir.path}\n');

  // 1. 修改 build.gradle
  await _updateBuildGradle(projectDir);

  // 2. 修改 Kotlin 文件
  await _updateKotlinFiles(projectDir);

  // 3. 重命名目录结构
  await _renameDirectories(projectDir);

  print('\n✅ 包名修改完成！');
  print('\n📋 接下来请执行:');
  print('   cd ${projectDir.path}');
  print('   flutter clean');
  print('   flutter pub get');
  print('   flutter build apk --release');
}

Future<void> _updateBuildGradle(Directory projectDir) async {
  final file = File('${projectDir.path}/android/app/build.gradle');
  if (!file.existsSync()) {
    print('❌ 找不到 build.gradle');
    return;
  }

  var content = await file.readAsString();

  // 替换 namespace
  content = content.replaceAll(
    RegExp(r'namespace\s*=\s*"' + RegExp.escape(oldPackageName) + '"'),
    'namespace = "$newPackageName"',
  );

  // 替换 applicationId
  content = content.replaceAll(
    RegExp(r'applicationId\s*=\s*"' + RegExp.escape(oldPackageName) + '"'),
    'applicationId = "$newPackageName"',
  );

  await file.writeAsString(content);
  print('✅ 已更新 build.gradle');
}

Future<void> _updateKotlinFiles(Directory projectDir) async {
  final oldPath = oldPackageName.replaceAll('.', '/');

  final kotlinDir =
      Directory('${projectDir.path}/android/app/src/main/kotlin/$oldPath');

  if (!kotlinDir.existsSync()) {
    print('⚠️  Kotlin 目录不存在: ${kotlinDir.path}');
    return;
  }

  // 递归处理所有 .kt 文件
  await for (final entity in kotlinDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.kt')) {
      var content = await entity.readAsString();

      // 替换 package 声明（使用 replaceAllMapped 处理带后缀的情况）
      final packageRegex = RegExp(
          r'package\s+' + RegExp.escape(oldPackageName) + r'(\.[a-z_]+)?');
      content = content.replaceAllMapped(packageRegex, (match) {
        final suffix = match.group(1) ?? '';
        return 'package $newPackageName$suffix';
      });

      // 替换 import 语句
      content = content.replaceAll(
        RegExp(r'import\s+' + RegExp.escape(oldPackageName) + r'\.'),
        'import $newPackageName.',
      );

      await entity.writeAsString(content);
      print('✅ 已更新 ${entity.path.split('/').last}');
    }
  }
}

Future<void> _renameDirectories(Directory projectDir) async {
  final oldPath = oldPackageName.replaceAll('.', '/');
  final newPath = newPackageName.replaceAll('.', '/');

  final kotlinBaseDir =
      Directory('${projectDir.path}/android/app/src/main/kotlin');
  final oldDir = Directory('${kotlinBaseDir.path}/$oldPath');
  final newDir = Directory('${kotlinBaseDir.path}/$newPath');

  if (!oldDir.existsSync()) {
    print('⚠️  源目录不存在: ${oldDir.path}');
    return;
  }

  if (oldPath == newPath) {
    return;
  }

  // 创建新目录结构
  await newDir.create(recursive: true);

  // 复制所有文件到新目录
  await _copyDirectory(oldDir, newDir);

  // 删除旧目录（整个旧包名目录树）
  await _deleteOldPackageDir(kotlinBaseDir, oldPackageName, newPackageName);

  print('✅ 已重命名目录结构');
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: false)) {
    final newPath =
        '${destination.path}/${entity.path.split(Platform.pathSeparator).last}';

    if (entity is Directory) {
      final newDir = Directory(newPath);
      await newDir.create(recursive: true);
      await _copyDirectory(entity, newDir);
    } else if (entity is File) {
      await entity.copy(newPath);
    }
  }
}

Future<void> _deleteOldPackageDir(
    Directory kotlinBaseDir, String oldPackage, String newPackage) async {
  final oldParts = oldPackage.split('.');
  final newParts = newPackage.split('.');

  // 找到新旧包名的公共前缀长度
  int commonPrefixLength = 0;
  for (int i = 0; i < oldParts.length && i < newParts.length; i++) {
    if (oldParts[i] == newParts[i]) {
      commonPrefixLength = i + 1;
    } else {
      break;
    }
  }

  // 删除旧包名中不属于公共前缀的部分
  // 例如: com.toretto.embyhub → com.tencent.qqmusic
  // 公共前缀是 com，所以要删除 com/toretto 整个目录
  if (commonPrefixLength < oldParts.length) {
    // 要删除的目录是公共前缀后的第一个不同的目录
    final deleteFromIndex = commonPrefixLength;
    final pathToDelete =
        '${kotlinBaseDir.path}/${oldParts.sublist(0, deleteFromIndex + 1).join('/')}';
    final dirToDelete = Directory(pathToDelete);

    if (dirToDelete.existsSync()) {
      try {
        await dirToDelete.delete(recursive: true);
        print(
            '🗑️  已删除旧目录: ${oldParts.sublist(0, deleteFromIndex + 1).join('/')}');
      } catch (e) {
        print('⚠️  删除旧目录失败: $e');
      }
    }
  }
}
