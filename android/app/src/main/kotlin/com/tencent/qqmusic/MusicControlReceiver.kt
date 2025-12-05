package com.tencent.qqmusic

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.tencent.qqmusic.exoplayer.ExoPlayerMusicPlugin

/**
 * 音乐控制广播接收器
 * 供 Macrodroid、Tasker 等自动化应用调用
 * 
 * 使用方法（以 Macrodroid 为例）：
 * 1. 创建一个宏
 * 2. 添加动作 → 应用 → 发送 Intent
 * 3. 设置：
 *    - 目标：广播接收器
 *    - 动作：${包名}.ACTION_TOGGLE（或 ACTION_PLAY / ACTION_PAUSE / ACTION_NEXT / ACTION_PREVIOUS）
 *    - 包名：${包名}（可选）
 *    - 组件：${包名}/.MusicControlReceiver
 * 
 * 支持的 Action：
 * - ${包名}.ACTION_PLAY      播放
 * - ${包名}.ACTION_PAUSE     暂停
 * - ${包名}.ACTION_TOGGLE    切换播放/暂停
 * - ${包名}.ACTION_NEXT      下一首
 * - ${包名}.ACTION_PREVIOUS  上一首
 * 
 * adb 测试命令：
 * adb shell am broadcast -a com.tencent.qqmusic.ACTION_TOGGLE -n com.tencent.qqmusic/.MusicControlReceiver
 * 
 * 特性：
 * - 如果应用没运行，会自动启动应用
 * - 启动后会自动执行收到的命令
 * - 需要 SYSTEM_ALERT_WINDOW（悬浮窗）权限才能后台启动
 */
class MusicControlReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "MusicControlReceiver"
        
        // 重试次数
        private const val MAX_RETRY_COUNT = 10
        private const val RETRY_DELAY_MS = 500L
        
        // 保存待执行的命令（应用启动后执行）
        @Volatile
        var pendingAction: String? = null
        
        /**
         * 检查是否有悬浮窗权限
         */
        fun canDrawOverlays(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }
        }
        
        /**
         * 打开悬浮窗权限设置页面
         */
        fun requestOverlayPermission(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:${context.packageName}")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            }
        }
        
        /**
         * 执行待处理的命令（由 MainActivity 调用）
         */
        fun executePendingAction() {
            val action = pendingAction ?: return
            pendingAction = null
            
            Log.d(TAG, "🔄 Will execute pending action: $action")
            
            // 延迟执行，等待 Flutter 初始化和播放状态恢复
            executeActionWithRetry(action, 0)
        }
        
        private fun executeActionWithRetry(action: String, retryCount: Int) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (ExoPlayerMusicPlugin.isPlayerReady()) {
                    Log.d(TAG, "✅ Player ready, executing: $action (retry: $retryCount)")
                    executeAction(action)
                } else if (retryCount < MAX_RETRY_COUNT) {
                    Log.d(TAG, "⏳ Player not ready, retrying... ($retryCount/$MAX_RETRY_COUNT)")
                    executeActionWithRetry(action, retryCount + 1)
                } else {
                    Log.w(TAG, "❌ Player still not ready after $MAX_RETRY_COUNT retries, giving up")
                }
            }, RETRY_DELAY_MS)
        }
        
        private fun executeAction(action: String) {
            when {
                action.endsWith(".ACTION_PLAY") -> {
                    Log.d(TAG, "▶️ Executing: PLAY")
                    ExoPlayerMusicPlugin.externalPlay()
                }
                action.endsWith(".ACTION_PAUSE") -> {
                    Log.d(TAG, "⏸️ Executing: PAUSE")
                    ExoPlayerMusicPlugin.externalPause()
                }
                action.endsWith(".ACTION_TOGGLE") -> {
                    Log.d(TAG, "⏯️ Executing: TOGGLE")
                    ExoPlayerMusicPlugin.externalToggle()
                }
                action.endsWith(".ACTION_NEXT") -> {
                    Log.d(TAG, "⏭️ Executing: NEXT")
                    ExoPlayerMusicPlugin.externalNext()
                }
                action.endsWith(".ACTION_PREVIOUS") -> {
                    Log.d(TAG, "⏮️ Executing: PREVIOUS")
                    ExoPlayerMusicPlugin.externalPrevious()
                }
                else -> {
                    Log.w(TAG, "⚠️ Unknown action: $action")
                }
            }
        }
    }
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        val action = intent.action ?: return
        
        Log.d(TAG, "📱 Received action: $action")
        
        // 检查播放器是否就绪
        if (!ExoPlayerMusicPlugin.isPlayerReady()) {
            Log.w(TAG, "⚠️ Player not ready, launching app first...")
            
            // 保存待执行的命令
            pendingAction = action
            
            // 启动应用
            launchApp(context)
            return
        }
        
        // 根据 Action 后缀判断操作类型，直接调用播放器
        executeAction(action)
    }
    
    private fun launchApp(context: Context) {
        // 检查是否有悬浮窗权限（SYSTEM_ALERT_WINDOW）
        val canDrawOverlays = canDrawOverlays(context)
        
        Log.d(TAG, "🚀 Launching app... canDrawOverlays: $canDrawOverlays, SDK: ${Build.VERSION.SDK_INT}")
        
        try {
            val launchIntent = Intent().apply {
                setClassName(context.packageName, "${context.packageName}.MainActivity")
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
                putExtra("from_broadcast", true)
                putExtra("pending_action", pendingAction)
            }
            
            context.startActivity(launchIntent)
            Log.d(TAG, "✅ startActivity called")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Launch failed: ${e.message}")
            e.printStackTrace()
        }
    }
}
