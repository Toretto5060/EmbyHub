package com.tencent.qqmusic

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
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
 */
class MusicControlReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "MusicControlReceiver"
    }
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        val action = intent.action ?: return
        
        Log.d(TAG, "📱 Received action: $action")
        
        // 检查播放器是否就绪
        if (!ExoPlayerMusicPlugin.isPlayerReady()) {
            Log.w(TAG, "⚠️ Player not ready, ignoring action: $action")
            return
        }
        
        // 根据 Action 后缀判断操作类型，直接调用播放器
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

