package com.toretto.embyhub

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val pipChannelName = "app.pip"
    private val platformChannelName = "com.embyhub/platform"
    private var pipChannel: MethodChannel? = null
    private var isPipExpanded = false // PiP 窗口是否放大
    private var currentPlayingState = true // 当前播放状态
    
    // ✅ MediaSession 相关
    private var mediaSession: MediaSessionCompat? = null
    private var currentVideoTitle: String = "EmbyHub"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "media_playback_channel"
    
    companion object {
        const val ACTION_PLAY_PAUSE = "com.toretto.embyhub.PLAY_PAUSE"
        const val ACTION_NEXT = "com.toretto.embyhub.NEXT"
        const val ACTION_PREVIOUS = "com.toretto.embyhub.PREVIOUS"
    }
    
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            android.util.Log.d("MainActivity", "📡 PiP broadcast received: action=${intent?.action}, pipChannel=${if(pipChannel != null) "available" else "NULL"}")
            when (intent?.action) {
                ACTION_PLAY_PAUSE -> {
                    android.util.Log.d("MainActivity", "▶️ Calling togglePlayPause")
                    pipChannel?.invokeMethod("togglePlayPause", null, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            android.util.Log.d("MainActivity", "✅ togglePlayPause success")
                        }
                        override fun error(code: String, message: String?, details: Any?) {
                            android.util.Log.e("MainActivity", "❌ togglePlayPause error: $code - $message")
                        }
                        override fun notImplemented() {
                            android.util.Log.e("MainActivity", "⚠️ togglePlayPause not implemented")
                        }
                    })
                }
                ACTION_NEXT -> {
                    android.util.Log.d("MainActivity", "⏭ Calling next")
                    pipChannel?.invokeMethod("next", null)
                }
                ACTION_PREVIOUS -> {
                    android.util.Log.d("MainActivity", "⏮ Calling previous")
                    pipChannel?.invokeMethod("previous", null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ✅ 初始化 MediaSession
        initMediaSession()
        
        // 注册广播接收器
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val filter = IntentFilter().apply {
                addAction(ACTION_PLAY_PAUSE)
                addAction(ACTION_NEXT)
                addAction(ACTION_PREVIOUS)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(pipReceiver, filter)
            }
        }
        
        // PIP 功能通道
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        val title = call.argument<String>("title") ?: ""
                        enterPip(isPlaying, title)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "updatePipParams" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        updatePipActions(isPlaying)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "updateMediaSession" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val title = call.argument<String>("title") ?: "EmbyHub"
                    val posterUrl = call.argument<String>("posterUrl")
                    updateMediaSession(isPlaying, title, posterUrl)
                    result.success(true)
                }
                "showMediaNotification" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val title = call.argument<String>("title") ?: "EmbyHub"
                    val posterUrl = call.argument<String>("posterUrl")
                    showMediaNotification(isPlaying, title, posterUrl)
                    result.success(true)
                }
                "hideMediaNotification" -> {
                    hideMediaNotification()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // 平台功能通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBackground" -> {
                    // 将应用移到后台（不退出）
                    moveTaskToBack(true)
                    result.success(true)
                }
                "setHighRefreshRate" -> {
                    setHighRefreshRate()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun enterPip(isPlaying: Boolean, title: String) {
        android.util.Log.d("MainActivity", "Entering PiP mode, isPlaying=$isPlaying, title=$title")
        isPipExpanded = false // 重置为小窗状态
        currentPlayingState = isPlaying // 保存播放状态
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(getPipAspectRatio())
            .setActions(createPipActions(isPlaying))
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setTitle(title)
                    setAutoEnterEnabled(true)
                }
            }
            .build()
        val result = enterPictureInPictureMode(params)
        android.util.Log.d("MainActivity", "PiP mode entered: $result")
    }
    
    @RequiresApi(Build.VERSION_CODES.O)
    private fun getPipAspectRatio(): Rational {
        // 小窗：16:9，大窗：更大的窗口（通过 setSourceRectHint 实现）
        return Rational(16, 9)
    }
    
    @RequiresApi(Build.VERSION_CODES.O)
    private fun togglePipSize() {
        if (isInPictureInPictureMode) {
            isPipExpanded = !isPipExpanded
            android.util.Log.d("MainActivity", "Toggling PiP size to: ${if (isPipExpanded) "expanded" else "normal"}")
            
            val aspectRatio = if (isPipExpanded) {
                // 放大：使用更宽的比例
                Rational(21, 9)
            } else {
                // 正常：标准 16:9
                Rational(16, 9)
            }
            
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(aspectRatio)
                .setActions(createPipActions(currentPlayingState))
                .build()
            setPictureInPictureParams(params)
        }
    }
    
    @RequiresApi(Build.VERSION_CODES.O)
    private fun updatePipActions(isPlaying: Boolean) {
        android.util.Log.d("MainActivity", "Updating PiP actions, isPlaying=$isPlaying, inPipMode=$isInPictureInPictureMode")
        currentPlayingState = isPlaying // 保存播放状态
        if (isInPictureInPictureMode) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(getPipAspectRatio())
                .setActions(createPipActions(isPlaying))
                .build()
            setPictureInPictureParams(params)
            android.util.Log.d("MainActivity", "PiP actions updated successfully")
        }
    }
    
    @RequiresApi(Build.VERSION_CODES.O)
    private fun createPipActions(isPlaying: Boolean): ArrayList<RemoteAction> {
        val actions = ArrayList<RemoteAction>()
        
        // 播放/暂停按钮
        val playPauseIcon = if (isPlaying) {
            Icon.createWithResource(this, android.R.drawable.ic_media_pause)
        } else {
            Icon.createWithResource(this, android.R.drawable.ic_media_play)
        }
        
        val playPauseIntent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(ACTION_PLAY_PAUSE).setPackage(packageName),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        
        val playPauseAction = RemoteAction(
            playPauseIcon,
            if (isPlaying) "暂停" else "播放",
            if (isPlaying) "暂停播放" else "继续播放",
            playPauseIntent
        )
        
        actions.add(playPauseAction)
        
        return actions
    }
    
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        android.util.Log.d("MainActivity", "PiP mode changed: $isInPictureInPictureMode")
        
        // 退出 PiP 模式时重置窗口大小状态
        if (!isInPictureInPictureMode) {
            isPipExpanded = false
        }
        
        // 通知 Flutter 端 PiP 状态变化
        pipChannel?.invokeMethod("onPipModeChanged", mapOf("isInPipMode" to isInPictureInPictureMode))
    }
    
    // ✅ 初始化 MediaSession
    private fun initMediaSession() {
        try {
            android.util.Log.d("MainActivity", "📱 Initializing MediaSession")
            
            // 创建通知渠道
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "媒体播放",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "显示正在播放的媒体"
                    setShowBadge(false)
                }
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(channel)
            }
            
            // 创建 MediaSession
            mediaSession = MediaSessionCompat(this, "EmbyHubMediaSession").apply {
                isActive = true
                
                // 设置回调，处理媒体控制按钮
                setCallback(object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        android.util.Log.d("MainActivity", "📱 MediaSession: onPlay")
                        pipChannel?.invokeMethod("togglePlayPause", null)
                    }
                    
                    override fun onPause() {
                        android.util.Log.d("MainActivity", "📱 MediaSession: onPause")
                        pipChannel?.invokeMethod("togglePlayPause", null)
                    }
                    
                    override fun onStop() {
                        android.util.Log.d("MainActivity", "📱 MediaSession: onStop")
                        hideMediaNotification()
                    }
                })
            }
            
            android.util.Log.d("MainActivity", "✅ MediaSession initialized successfully")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ MediaSession init failed: $e")
        }
    }
    
    // ✅ 显示媒体通知
    private fun showMediaNotification(isPlaying: Boolean, title: String, posterUrl: String?) {
        try {
            currentVideoTitle = title
            android.util.Log.d("MainActivity", "📱 Showing media notification: $title, playing=$isPlaying, poster=$posterUrl")
            
            val session = mediaSession ?: return
            
            // 构建通知
            val playPauseAction = if (isPlaying) {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_pause,
                    "暂停",
                    PendingIntent.getBroadcast(
                        this, 0,
                        Intent(ACTION_PLAY_PAUSE).setPackage(packageName),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            } else {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play,
                    "播放",
                    PendingIntent.getBroadcast(
                        this, 0,
                        Intent(ACTION_PLAY_PAUSE).setPackage(packageName),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }
            
            // ✅ 异步加载海报图片（如果有）
            val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText("EmbyHub")
                .setSmallIcon(R.mipmap.ic_launcher) // ✅ 使用 APP 图标
                .setStyle(MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0))
                .addAction(playPauseAction)
                .setOngoing(isPlaying)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            
            // ✅ 如果有海报 URL，异步加载并更新通知
            if (!posterUrl.isNullOrEmpty()) {
                Thread {
                    try {
                        val url = java.net.URL(posterUrl)
                        val bitmap = android.graphics.BitmapFactory.decodeStream(url.openConnection().getInputStream())
                        notificationBuilder.setLargeIcon(bitmap)
                        
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())
                        android.util.Log.d("MainActivity", "✅ Media notification updated with poster")
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "❌ Failed to load poster: $e")
                        // 即使加载失败，也显示基本通知
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())
                    }
                }.start()
            } else {
                // 没有海报，直接显示
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())
            }
            
            // 更新 MediaSession 状态
            updateMediaSession(isPlaying, title, posterUrl)
            
            android.util.Log.d("MainActivity", "✅ Media notification shown")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Show notification failed: $e")
        }
    }
    
    // ✅ 隐藏媒体通知
    private fun hideMediaNotification() {
        try {
            android.util.Log.d("MainActivity", "📱 Hiding media notification")
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
            mediaSession?.isActive = false
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Hide notification failed: $e")
        }
    }
    
    // ✅ 更新 MediaSession 状态
    private fun updateMediaSession(isPlaying: Boolean, title: String, posterUrl: String?) {
        try {
            currentVideoTitle = title
            val session = mediaSession ?: return
            
            session.isActive = true
            
            val stateBuilder = PlaybackStateCompat.Builder()
                .setState(
                    if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                    1.0f
                )
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_STOP
                )
            
            session.setPlaybackState(stateBuilder.build())
            
            val metadataBuilder = android.support.v4.media.MediaMetadataCompat.Builder()
                .putString(android.support.v4.media.MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(android.support.v4.media.MediaMetadataCompat.METADATA_KEY_ARTIST, "EmbyHub")
            
            // ✅ 异步加载海报作为 MediaMetadata 的专辑封面
            if (!posterUrl.isNullOrEmpty()) {
                Thread {
                    try {
                        val url = java.net.URL(posterUrl)
                        val bitmap = android.graphics.BitmapFactory.decodeStream(url.openConnection().getInputStream())
                        metadataBuilder.putBitmap(android.support.v4.media.MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
                        session.setMetadata(metadataBuilder.build())
                        android.util.Log.d("MainActivity", "✅ MediaSession metadata updated with poster")
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "❌ Failed to load poster for MediaSession: $e")
                        session.setMetadata(metadataBuilder.build())
                    }
                }.start()
            } else {
                session.setMetadata(metadataBuilder.build())
            }
            
            android.util.Log.d("MainActivity", "✅ MediaSession updated: $title, playing=$isPlaying")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Update MediaSession failed: $e")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // 释放 MediaSession
        try {
            hideMediaNotification()
            mediaSession?.release()
            mediaSession = null
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ MediaSession release failed: $e")
        }
        
        // 注销广播接收器
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (e: Exception) {
                // 忽略重复注销的异常
            }
        }
    }

    private fun setHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

        val displayCompat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }

        if (displayCompat == null) {
            return
        }

        val bestMode = displayCompat.supportedModes.maxByOrNull { it.refreshRate }
        if (bestMode != null) {
            val params = window.attributes
            if (params.preferredDisplayModeId != bestMode.modeId) {
                params.preferredDisplayModeId = bestMode.modeId
                window.attributes = params
            }
        }
    }
}

