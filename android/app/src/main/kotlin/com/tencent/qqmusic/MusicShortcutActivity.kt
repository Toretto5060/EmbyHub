package com.tencent.qqmusic

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.tencent.qqmusic.exoplayer.ExoPlayerMusicPlugin

/**
 * 音乐快捷方式 Activity
 * 用于处理桌面快捷方式的播放/暂停操作
 * 无需启动前台页面，直接在后台控制音乐后立即关闭
 */
class MusicShortcutActivity : Activity() {
    
    companion object {
        private const val TAG = "MusicShortcutActivity"
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val action = intent?.action
        
        Log.d(TAG, "📱 Received shortcut action: $action")
        
        // 检查播放器是否就绪
        if (!ExoPlayerMusicPlugin.isPlayerReady()) {
            Log.w(TAG, "⚠️ Player not ready, ignoring action: $action")
            finish()
            return
        }
        
        // 根据 Action 后缀判断操作类型，直接调用播放器
        when {
            action?.endsWith(".SHORTCUT_PLAY") == true -> {
                Log.d(TAG, "▶️ Executing: PLAY")
                ExoPlayerMusicPlugin.externalPlay()
            }
            action?.endsWith(".SHORTCUT_PAUSE") == true -> {
                Log.d(TAG, "⏸️ Executing: PAUSE")
                ExoPlayerMusicPlugin.externalPause()
            }
            action?.endsWith(".SHORTCUT_TOGGLE") == true -> {
                Log.d(TAG, "⏯️ Executing: TOGGLE")
                ExoPlayerMusicPlugin.externalToggle()
            }
            else -> {
                Log.w(TAG, "⚠️ Unknown action: $action")
            }
        }
        
        // 处理完成后立即关闭，不显示任何界面
        finish()
    }
}

