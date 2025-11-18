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
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.AudioAttributes
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.media.audiofx.BassBoost
import android.media.audiofx.Virtualizer
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val pipChannelName = "app.pip"
    private val platformChannelName = "com.embyhub/platform"
    private val brightnessChannelName = "com.embyhub/brightness"
    private var pipChannel: MethodChannel? = null
    private var isPipExpanded = false // PiP 窗口是否放大
    private var currentPlayingState = true // 当前播放状态
    
    // ✅ MediaSession 相关
    private var mediaSession: MediaSessionCompat? = null
    private var currentVideoTitle: String = "EmbyHub"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "media_playback_channel"
    
    // ✅ 音频焦点管理
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    
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
        
        // ✅ 设置音量控制为媒体音量流（使用系统音效）
        // 这样按音量键时调节的是媒体音量，而非铃声音量
        volumeControlStream = AudioManager.STREAM_MUSIC
        android.util.Log.d("MainActivity", "🔊 Volume control stream set to STREAM_MUSIC")
        
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
        
        // ✅ 亮度/音量控制 channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, brightnessChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBrightness" -> {
                    val brightness = call.argument<Double>("brightness") ?: 0.5
                    setBrightness(brightness)
                    result.success(true)
                }
                "getBrightness" -> {
                    val brightness = getBrightness()
                    result.success(brightness)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume") ?: 50.0
                    setSystemVolume(volume)
                    result.success(true)
                }
                "getVolume" -> {
                    val volume = getSystemVolume()
                    result.success(volume)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    // ✅ 设置屏幕亮度
    private fun setBrightness(brightness: Double) {
        val window = window
        val layoutParams = window.attributes
        layoutParams.screenBrightness = brightness.toFloat().coerceIn(0f, 1f)
        window.attributes = layoutParams
    }
    
    // ✅ 获取当前屏幕亮度
    private fun getBrightness(): Double {
        return try {
            val brightness = Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
            (brightness / 255.0).toDouble().coerceIn(0.0, 1.0)
        } catch (e: Exception) {
            // 如果无法获取系统亮度，返回窗口亮度
            val window = window
            val layoutParams = window.attributes
            layoutParams.screenBrightness.coerceIn(0f, 1f).toDouble()
        }
    }
    
    // ✅ 设置系统音量
    private fun setSystemVolume(volume: Double) {
        audioManager?.let { am ->
            val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val targetVolume = (volume / 100.0 * maxVolume).toInt().coerceIn(0, maxVolume)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        }
    }
    
    // ✅ 获取当前系统音量
    private fun getSystemVolume(): Double {
        return audioManager?.let { am ->
            val currentVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            (currentVolume.toDouble() / maxVolume * 100.0).coerceIn(0.0, 100.0)
        } ?: 50.0
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
        android.util.Log.d("MainActivity", "📺 PiP mode changed: $isInPictureInPictureMode")
        
        // 退出 PiP 模式时重置窗口大小状态
        if (!isInPictureInPictureMode) {
            isPipExpanded = false
            android.util.Log.d("MainActivity", "📺 Exiting PiP mode, reset expanded state")
        } else {
            android.util.Log.d("MainActivity", "📺 Entering PiP mode")
        }
        
        // 通知 Flutter 端 PiP 状态变化
        try {
            pipChannel?.invokeMethod("onPipModeChanged", mapOf("isInPipMode" to isInPictureInPictureMode))
            android.util.Log.d("MainActivity", "📺 Notified Flutter: isInPipMode=$isInPictureInPictureMode")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Failed to notify Flutter about PiP change: $e")
        }
    }
    
    // ✅ 初始化 MediaSession
    private fun initMediaSession() {
        try {
            android.util.Log.d("MainActivity", "📱 Initializing MediaSession")
            
            // ✅ 初始化 AudioManager 并配置音频模式
            audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager?.apply {
                // 设置为媒体播放模式，启用系统音效增强
                mode = AudioManager.MODE_NORMAL
                // 确保使用扬声器输出（非通话模式）
                isSpeakerphoneOn = false
                
                // ✅ 检查当前媒体音量并记录
                val currentVolume = getStreamVolume(AudioManager.STREAM_MUSIC)
                val maxVolume = getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                android.util.Log.d("MainActivity", "🔊 Current media volume: $currentVolume/$maxVolume")
                
                // 如果音量太小，提示用户
                if (currentVolume < maxVolume * 0.3) {
                    android.util.Log.w("MainActivity", "⚠️ Media volume is low ($currentVolume/$maxVolume), please increase system volume")
                }
                
                android.util.Log.d("MainActivity", "🔊 AudioManager configured: mode=NORMAL")
            }
            
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
                        requestAudioFocus()
                        pipChannel?.invokeMethod("togglePlayPause", null)
                    }
                    
                    override fun onPause() {
                        android.util.Log.d("MainActivity", "📱 MediaSession: onPause")
                        pipChannel?.invokeMethod("togglePlayPause", null)
                    }
                    
                    override fun onStop() {
                        android.util.Log.d("MainActivity", "📱 MediaSession: onStop")
                        abandonAudioFocus()
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
            
            // ✅ 请求音频焦点，这会自动暂停其他应用的音频播放
            requestAudioFocus()
            
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
    // ✅ 请求音频焦点
    private fun requestAudioFocus() {
        try {
            val audioMgr = audioManager ?: return
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0+ 使用 AudioFocusRequest
                // ✅ 配置音频属性，确保系统音效（均衡器、低音增强、杜比音效等）自动应用
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Android 10+ 添加深度缓冲标志（FLAG_DEEP_BUFFER = 1）
                    // 支持高质量音频，包括杜比音效
                    AudioAttributes.FLAG_HW_AV_SYNC or 1
                } else {
                    AudioAttributes.FLAG_HW_AV_SYNC
                }
                
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA) // 媒体播放用途
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE) // 电影内容类型（支持杜比音效）
                    .setFlags(flags)
                    .build()
                
                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(audioAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setWillPauseWhenDucked(true)
                    .setOnAudioFocusChangeListener { focusChange ->
                        when (focusChange) {
                            AudioManager.AUDIOFOCUS_LOSS -> {
                                android.util.Log.d("MainActivity", "🔊 Audio focus lost")
                                pipChannel?.invokeMethod("togglePlayPause", null)
                            }
                            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                android.util.Log.d("MainActivity", "🔊 Audio focus lost transient")
                                pipChannel?.invokeMethod("togglePlayPause", null)
                            }
                        }
                    }
                    .build()
                
                audioFocusRequest = focusRequest
                val result = audioMgr.requestAudioFocus(focusRequest)
                android.util.Log.d("MainActivity", "🔊 Audio focus requested: ${if(result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) "GRANTED" else "DENIED"}")
                
                // ✅ 检查系统音效是否可用
                val effects = AudioEffect.queryEffects()
                android.util.Log.d("MainActivity", "🔊 System audio effects available: ${effects.size}")
                effects.forEach { effect ->
                    android.util.Log.d("MainActivity", "  - ${effect.name} (${effect.type})")
                }
            } else {
                // Android 8.0 以下使用旧API
                @Suppress("DEPRECATION")
                val result = audioMgr.requestAudioFocus(
                    { focusChange ->
                        when (focusChange) {
                            AudioManager.AUDIOFOCUS_LOSS, 
                            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                pipChannel?.invokeMethod("togglePlayPause", null)
                            }
                        }
                    },
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN
                )
                android.util.Log.d("MainActivity", "🔊 Audio focus requested (legacy): ${if(result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) "GRANTED" else "DENIED"}")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Request audio focus failed: $e")
        }
    }
    
    // ✅ 释放音频焦点
    private fun abandonAudioFocus() {
        try {
            val audioMgr = audioManager ?: return
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let {
                    audioMgr.abandonAudioFocusRequest(it)
                    android.util.Log.d("MainActivity", "🔊 Audio focus abandoned")
                }
            } else {
                @Suppress("DEPRECATION")
                audioMgr.abandonAudioFocus(null)
                android.util.Log.d("MainActivity", "🔊 Audio focus abandoned (legacy)")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Abandon audio focus failed: $e")
        }
    }
    
    private fun hideMediaNotification() {
        try {
            android.util.Log.d("MainActivity", "📱 Hiding media notification")
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
            mediaSession?.isActive = false
            // ✅ 隐藏通知时释放音频焦点
            abandonAudioFocus()
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

