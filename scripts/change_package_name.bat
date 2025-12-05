@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ============================================================
:: 🔧 只需要修改这里的包名！
:: ============================================================
set NEW_PACKAGE=com.toretto.embyhub
:: ============================================================

set OLD_PACKAGE=com.toretto.embyhub

echo.
echo ========================================
echo   Android 包名修改工具
echo ========================================
echo.
echo 当前包名: %OLD_PACKAGE%
echo 新包名:   %NEW_PACKAGE%
echo.

if "%NEW_PACKAGE%"=="%OLD_PACKAGE%" (
    echo [警告] 新包名与旧包名相同，无需修改
    pause
    exit /b 0
)

:: 切换到项目目录
cd /d "%~dp0.."

echo [1/3] 运行 Dart 脚本修改包名...
dart scripts/change_package_name.dart

if errorlevel 1 (
    echo [错误] 包名修改失败！
    pause
    exit /b 1
)

echo.
echo [2/3] 清理项目...
call flutter clean

echo.
echo [3/3] 获取依赖...
call flutter pub get

echo.
echo ========================================
echo ✅ 包名修改完成！
echo.
echo 现在可以运行:
echo   flutter build apk --release
echo ========================================
pause

