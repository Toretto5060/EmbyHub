package com.tencent.qqmusic

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.tencent.qqmusic.exoplayer.ExoPlayerMusicPlugin
import android.content.Intent

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
        
        // 根据 Action 后缀判断操作类型，设置对应的广播 Action
        val broadcastAction = when {
            action?.endsWith(".SHORTCUT_PLAY") == true -> "ACTION_PLAY"
            action?.endsWith(".SHORTCUT_PAUSE") == true -> "ACTION_PAUSE"
            action?.endsWith(".SHORTCUT_TOGGLE") == true -> "ACTION_TOGGLE"
            else -> null
        }
        
        if (broadcastAction != null) {
            val fullAction = "$packageName.$broadcastAction"
            Log.d(TAG, "📡 Sending broadcast: $fullAction")
            
            val broadcastIntent = Intent(fullAction).apply {
                setClassName(packageName, "${packageName}.MusicControlReceiver")
            }
            sendBroadcast(broadcastIntent)
        } else {
            Log.w(TAG, "⚠️ Unknown action: $action")
        }
        
        // 处理完成后立即关闭，不显示任何界面
        finish()
    }
}

