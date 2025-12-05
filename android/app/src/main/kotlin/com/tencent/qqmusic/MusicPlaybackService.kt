package com.tencent.qqmusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 音乐播放前台服务
 * 
 * 功能：
 * 1. 保持应用在后台存活，防止被系统杀死
 * 2. 接收广播控制命令（播放/暂停/上一首/下一首）
 * 3. 应用被杀死后可以通过广播重新启动
 * 
 * 使用方法：
 * - 播放音乐时会自动启动此服务
 * - 服务会显示一个持久通知，防止被系统杀死
 */
class MusicPlaybackService : Service() {
    
    companion object {
        private const val TAG = "MusicPlaybackService"
        private const val NOTIFICATION_ID = 2002
        private const val CHANNEL_ID = "music_service_channel"
        
        // 服务 Action
        const val ACTION_START_SERVICE = "START_SERVICE"
        const val ACTION_STOP_SERVICE = "STOP_SERVICE"
        
        // 控制 Action 后缀
        private const val ACTION_SUFFIX_PLAY = ".ACTION_PLAY"
        private const val ACTION_SUFFIX_PAUSE = ".ACTION_PAUSE"
        private const val ACTION_SUFFIX_TOGGLE = ".ACTION_TOGGLE"
        private const val ACTION_SUFFIX_NEXT = ".ACTION_NEXT"
        private const val ACTION_SUFFIX_PREVIOUS = ".ACTION_PREVIOUS"
        
        @Volatile
        private var isRunning = false
        
        fun isServiceRunning() = isRunning
        
        /**
         * 启动服务
         */
        fun start(context: Context) {
            val intent = Intent(context, MusicPlaybackService::class.java).apply {
                action = ACTION_START_SERVICE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        /**
         * 停止服务
         */
        fun stop(context: Context) {
            val intent = Intent(context, MusicPlaybackService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            context.startService(intent)
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🎵 Service created")
        createNotificationChannel()
        isRunning = true
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🎵 onStartCommand: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START_SERVICE -> {
                startForeground(NOTIFICATION_ID, createNotification())
                Log.d(TAG, "🎵 Service started in foreground")
            }
            ACTION_STOP_SERVICE -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Log.d(TAG, "🎵 Service stopped")
            }
            else -> {
                // 处理音乐控制命令
                handleMusicControl(intent?.action)
            }
        }
        
        // START_STICKY: 服务被杀死后会自动重启
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        Log.d(TAG, "🎵 Service destroyed")
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "🎵 Task removed, service will restart")
        // 任务被移除时（用户划掉应用），服务会因为 START_STICKY 自动重启
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "音乐服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持音乐服务在后台运行"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        // 点击通知打开应用
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("音乐服务运行中")
            .setContentText("点击打开应用")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    private fun handleMusicControl(action: String?) {
        if (action == null) return
        
        Log.d(TAG, "🎵 Handling music control: $action")
        
        // 尝试启动 Flutter 引擎（如果还没启动）
        ensureFlutterEngineStarted()
        
        // 转发给 MusicControlReceiver 处理
        val broadcastIntent = Intent(action).apply {
            setPackage(packageName)
            setClass(this@MusicPlaybackService, MusicControlReceiver::class.java)
        }
        sendBroadcast(broadcastIntent)
    }
    
    private fun ensureFlutterEngineStarted() {
        // 如果 Flutter 引擎没启动，启动 MainActivity
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // 不要真的显示 Activity，只是触发 Flutter 引擎初始化
                // 实际上这里可能需要更复杂的逻辑
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to ensure Flutter engine started: $e")
        }
    }
}

