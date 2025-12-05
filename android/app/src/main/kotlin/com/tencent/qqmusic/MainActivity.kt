package com.tencent.qqmusic

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
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
import java.io.BufferedReader
import java.io.InputStreamReader
import com.tencent.qqmusic.exoplayer.ExoPlayerTexturePlugin
import com.tencent.qqmusic.exoplayer.ExoPlayerMusicPlugin
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
    private val pipChannelName = "app.pip"
    private val platformChannelName = "com.embyhub/platform"
    private val brightnessChannelName = "com.embyhub/brightness"
    private val deviceNameChannelName = "device_name_channel"
    private var pipChannel: MethodChannel? = null
    private var isPipExpanded = false // PiP 窗口是否放大
    private var currentPlayingState = true // 当前播放状态
    private var shouldAutoEnterPip = false // ✅ 是否应该自动进入 PiP（在播放时为 true）
    
    // ✅ MediaSession 相关
    private var mediaSession: MediaSessionCompat? = null
    private var currentVideoTitle: String = "EmbyHub"
    
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.d("MainActivity", "🎵 onCreate called, intent: $intent")
        android.util.Log.d("MainActivity", "🎵 from_broadcast: ${intent?.getBooleanExtra("from_broadcast", false)}")
        android.util.Log.d("MainActivity", "🎵 pendingAction: ${MusicControlReceiver.pendingAction}")
        
        // 检查悬浮窗权限（用于后台启动）
        checkOverlayPermission()
        
        // 动态创建快捷方式（解决 XML 占位符问题）
        createShortcuts()
        
        // 处理来自广播的启动
        handleBroadcastLaunch()
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        android.util.Log.d("MainActivity", "🎵 onNewIntent called")
        handleBroadcastLaunch()
    }
    
    private fun checkOverlayPermission() {
        if (!MusicControlReceiver.canDrawOverlays(this)) {
            android.util.Log.w("MainActivity", "⚠️ 没有悬浮窗权限，后台启动可能无法工作")
            // 可以在这里提示用户授权，但不强制
        }
    }
    
    /**
     * 动态创建快捷方式（运行时创建，避免 XML 占位符问题）
     */
    private fun createShortcuts() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            try {
                val shortcutManager = getSystemService(ShortcutManager::class.java)
                val shortcuts = mutableListOf<ShortcutInfo>()
                
                // 播放快捷方式
                val playIntent = Intent("$packageName.SHORTCUT_PLAY").apply {
                    setClassName(packageName, "${packageName}.MusicShortcutActivity")
                }
                shortcuts.add(
                    ShortcutInfo.Builder(this, "play_music")
                        .setShortLabel(getString(resources.getIdentifier("shortcut_play", "string", packageName)))
                        .setLongLabel(getString(resources.getIdentifier("shortcut_play_long", "string", packageName)))
                        .setIcon(Icon.createWithResource(this, android.R.drawable.ic_media_play))
                        .setIntent(playIntent)
                        .build()
                )
                
                // 暂停快捷方式
                val pauseIntent = Intent("$packageName.SHORTCUT_PAUSE").apply {
                    setClassName(packageName, "${packageName}.MusicShortcutActivity")
                }
                shortcuts.add(
                    ShortcutInfo.Builder(this, "pause_music")
                        .setShortLabel(getString(resources.getIdentifier("shortcut_pause", "string", packageName)))
                        .setLongLabel(getString(resources.getIdentifier("shortcut_pause_long", "string", packageName)))
                        .setIcon(Icon.createWithResource(this, android.R.drawable.ic_media_pause))
                        .setIntent(pauseIntent)
                        .build()
                )
                
                // 切换快捷方式
                val toggleIntent = Intent("$packageName.SHORTCUT_TOGGLE").apply {
                    setClassName(packageName, "${packageName}.MusicShortcutActivity")
                }
                shortcuts.add(
                    ShortcutInfo.Builder(this, "toggle_music")
                        .setShortLabel(getString(resources.getIdentifier("shortcut_toggle", "string", packageName)))
                        .setLongLabel(getString(resources.getIdentifier("shortcut_toggle_long", "string", packageName)))
                        .setIcon(Icon.createWithResource(this, android.R.drawable.ic_media_play))
                        .setIntent(toggleIntent)
                        .build()
                )
                
                shortcutManager.setDynamicShortcuts(shortcuts)
                android.util.Log.d("MainActivity", "✅ Shortcuts created dynamically: ${shortcuts.size} shortcuts")
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "❌ Failed to create shortcuts: ${e.message}")
                e.printStackTrace()
            }
        }
    }
    
    private fun handleBroadcastLaunch() {
        val fromBroadcast = intent?.getBooleanExtra("from_broadcast", false) ?: false
        val actionFromIntent = intent?.getStringExtra("pending_action")
        
        android.util.Log.d("MainActivity", "🎵 handleBroadcastLaunch: fromBroadcast=$fromBroadcast, actionFromIntent=$actionFromIntent")
        
        // 如果有来自 Intent 的 action，保存到静态变量
        if (fromBroadcast && actionFromIntent != null) {
            MusicControlReceiver.pendingAction = actionFromIntent
            android.util.Log.d("MainActivity", "🎵 Saved pending action from intent: $actionFromIntent")
        }
        
        // 执行待处理的命令
        if (MusicControlReceiver.pendingAction != null) {
            android.util.Log.d("MainActivity", "🎵 Executing pending action...")
            MusicControlReceiver.executePendingAction()
            
            // 如果是从广播启动的，立即将应用移到后台（不显示界面）
            if (fromBroadcast) {
                android.util.Log.d("MainActivity", "🎵 Moving app to background...")
                moveTaskToBack(true)
            }
        }
    }
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "media_playback_channel"
    
    // ✅ 音频焦点管理
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    
    // ✅ 音效实例（用于手动启用特定音效）
    private var activeAudioEffects = mutableListOf<AudioEffect>()
    private val exoPlayerPlugin = ExoPlayerTexturePlugin()
    private val exoPlayerMusicPlugin = ExoPlayerMusicPlugin()  // ✅ 音乐播放器插件
    
    companion object {
        // 使用相对 Action 后缀，避免硬编码包名
        private const val ACTION_SUFFIX_PLAY_PAUSE = ".PLAY_PAUSE"
        private const val ACTION_SUFFIX_NEXT = ".NEXT"
        private const val ACTION_SUFFIX_PREVIOUS = ".PREVIOUS"
        
        // 根据包名生成完整的 Action 名称
        fun getActionPlayPause(packageName: String) = "$packageName$ACTION_SUFFIX_PLAY_PAUSE"
        fun getActionNext(packageName: String) = "$packageName$ACTION_SUFFIX_NEXT"
        fun getActionPrevious(packageName: String) = "$packageName$ACTION_SUFFIX_PREVIOUS"
    }
    
    // 缓存当前包名对应的 Action（延迟初始化）
    private val actionPlayPause: String by lazy { getActionPlayPause(packageName) }
    private val actionNext: String by lazy { getActionNext(packageName) }
    private val actionPrevious: String by lazy { getActionPrevious(packageName) }
    
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            android.util.Log.d("MainActivity", "📡 PiP broadcast received: action=${intent?.action}, pipChannel=${if(pipChannel != null) "available" else "NULL"}")
            when (intent?.action) {
                actionPlayPause -> {
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
                actionNext -> {
                    android.util.Log.d("MainActivity", "⏭ Calling next")
                    pipChannel?.invokeMethod("next", null)
                }
                actionPrevious -> {
                    android.util.Log.d("MainActivity", "⏮ Calling previous")
                    pipChannel?.invokeMethod("previous", null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(exoPlayerPlugin)
        flutterEngine.plugins.add(exoPlayerMusicPlugin)  // ✅ 注册音乐播放器插件
        
        // ✅ 设置音量控制为媒体音量流（使用系统音效）
        // 这样按音量键时调节的是媒体音量，而非铃声音量
        volumeControlStream = AudioManager.STREAM_MUSIC
        android.util.Log.d("MainActivity", "🔊 Volume control stream set to STREAM_MUSIC")
        
        // ✅ 初始化 MediaSession
        initMediaSession()
        
        // 注册广播接收器
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val filter = IntentFilter().apply {
                addAction(actionPlayPause)
                addAction(actionNext)
                addAction(actionPrevious)
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
                        
                        android.util.Log.d("MainActivity", "Manual entering PiP via button, isPlaying=$isPlaying, title=$title")
                        
                        // ✅ 使用和 onUserLeaveHint 完全相同的逻辑，避免闪烁
                        isPipExpanded = false
                        currentPlayingState = isPlaying
                        currentVideoTitle = title
                        
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(getPipAspectRatio())
                            .setActions(createPipActions(isPlaying))
                            .apply {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    setTitle(title)
                                    // ✅ 启用无缝调整大小，避免白屏闪烁
                                    setSeamlessResizeEnabled(true)
                                }
                            }
                            .build()
                        
                        try {
                            val enterResult = enterPictureInPictureMode(params)
                            android.util.Log.d("MainActivity", "✅ Manual PiP mode entered via button: $enterResult")
                            result.success(enterResult)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "❌ Failed to enter PiP via button: $e")
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "exit" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        exitPip()
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
                "setPlayingState" -> {
                    // ✅ 设置播放状态，用于 onUserLeaveHint 自动进入 PiP
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val title = call.argument<String>("title") ?: "EmbyHub"
                    shouldAutoEnterPip = isPlaying
                    currentPlayingState = isPlaying
                    currentVideoTitle = title
                    android.util.Log.d("MainActivity", "Set playing state: isPlaying=$isPlaying, title=$title, shouldAutoEnterPip=$shouldAutoEnterPip")
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
        
        // ✅ 获取真实设备商用名称 channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceNameChannelName).setMethodCallHandler { call, result ->
            if (call.method == "getMarketName") {
                val name = getMarketName()
                result.success(name)
            } else {
                result.notImplemented()
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

    // ✅ 退出 PiP 模式
    @RequiresApi(Build.VERSION_CODES.N)
    private fun exitPip() {
        android.util.Log.d("MainActivity", "Exit PiP requested, isInPipMode=$isInPictureInPictureMode, shouldAutoEnterPip=$shouldAutoEnterPip")
        
        // ✅ 重置自动进入 PiP 标志，防止其他页面也进入小窗
        shouldAutoEnterPip = false
        android.util.Log.d("MainActivity", "✅ Reset shouldAutoEnterPip to false")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // ✅ 禁用自动进入 PiP（Android 12+）
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .apply {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            setAutoEnterEnabled(false) // ✅ 禁用自动进入
                        }
                    }
                    .build()
                setPictureInPictureParams(params)
                android.util.Log.d("MainActivity", "✅ Disabled auto-enter PiP (Android 12+)")
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "❌ Failed to disable auto-enter PiP: $e")
            }
        }
        
        // ✅ 如果当前在 PiP 模式，尝试退出
        // 注意：Android 没有直接的 API 退出 PiP，只能通过 moveTaskToBack 或让用户点击小窗
        if (isInPictureInPictureMode) {
            android.util.Log.d("MainActivity", "Currently in PiP, will exit on user action or app resume")
        }
    }
    
    // ✅ 用户主动离开应用时触发（按Home键、切换应用等）
    // 注意：下拉通知栏不会触发此方法
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        android.util.Log.d("MainActivity", "onUserLeaveHint called, shouldAutoEnterPip=$shouldAutoEnterPip, isInPipMode=$isInPictureInPictureMode")
        
        // ✅ 只有在视频播放时且不在 PiP 模式下才自动进入 PiP
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (shouldAutoEnterPip && !isInPictureInPictureMode) {
                android.util.Log.d("MainActivity", "Auto-entering PiP on user leave")
                
                // ✅ 立即通知 Flutter 即将进入 PiP，防止 paused 状态暂停播放
                try {
                    pipChannel?.invokeMethod("onPipModeChanged", mapOf("isInPipMode" to true))
                    android.util.Log.d("MainActivity", "✅ Pre-notified Flutter: isInPipMode=true (before enterPip)")
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ Failed to pre-notify Flutter PiP state: $e")
                }
                
                // ✅ 在 onUserLeaveHint 中，直接调用 enterPictureInPictureMode
                // 这是 Android 官方推荐的自动进入 PiP 的方式
                isPipExpanded = false // 重置为小窗状态
                currentPlayingState = currentPlayingState // 保存播放状态
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(getPipAspectRatio())
                    .setActions(createPipActions(currentPlayingState))
                    .apply {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            setTitle(currentVideoTitle)
                            // ✅ 启用无缝调整大小，避免白屏闪烁
                            setSeamlessResizeEnabled(true)
                        }
                    }
                    .build()
                
                try {
                    val result = enterPictureInPictureMode(params)
                    android.util.Log.d("MainActivity", "✅ PiP mode entered in onUserLeaveHint: $result")
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ Failed to enter PiP in onUserLeaveHint: $e")
                }
            }
        }
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
            Intent(actionPlayPause).setPackage(packageName),
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
                // 设置为媒体播放模式，使用系统音效
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
                        Intent(actionPlayPause).setPackage(packageName),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            } else {
                NotificationCompat.Action(
                    android.R.drawable.ic_media_play,
                    "播放",
                    PendingIntent.getBroadcast(
                        this, 0,
                        Intent(actionPlayPause).setPackage(packageName),
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
                // ✅ 配置音频属性，确保系统音效（均衡器、低音增强、杜比全景声等）自动应用
                var flags = AudioAttributes.FLAG_HW_AV_SYNC // 硬件音视频同步
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Android 10+ 添加深度缓冲标志（FLAG_DEEP_BUFFER = 1）
                    // 支持高质量音频，包括杜比全景声和音效增强
                    flags = flags or 1 // FLAG_DEEP_BUFFER
                    
                    // Android 10+ 添加低延迟标志（如果需要）
                    // flags = flags or AudioAttributes.FLAG_LOW_LATENCY
                }
                
                // ✅ 配置音频属性，使用系统音效
                // USAGE_MEDIA + CONTENT_TYPE_MOVIE 会自动应用设备的音效设置
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA) // 媒体播放用途，启用系统音效
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE) // 电影内容类型，系统会自动应用相应音效
                    .setFlags(flags) // 硬件同步 + 深度缓冲（支持高质量音频处理）
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
                
                // ✅ 启用指定的音效（索引：1, 2, 3, 4, 5, 7, 8, 12，基于可用音效列表）
                // 注意：需要使用 Audio Session ID = 0（全局应用），因为 media_kit/MPV 可能不提供音频会话 ID
                val effectsToEnable = listOf(1, 2, 3, 4, 5, 7, 8, 12) // 索引从 1 开始（转换为 0 基索引需要 -1）
                val availableEffects = AudioEffect.queryEffects()
                
                // 先释放之前的音效实例
                activeAudioEffects.forEach { it.release() }
                activeAudioEffects.clear()
                
                // 启用指定的音效
                effectsToEnable.forEach { index ->
                    val effectIndex = index - 1 // 转换为 0 基索引
                    if (effectIndex >= 0 && effectIndex < availableEffects.size) {
                        val effect = availableEffects[effectIndex]
                        try {
                            // 尝试创建音效实例（使用 Audio Session ID = 0，表示应用到全局音频输出）
                            // priority = 0 表示正常优先级
                            val audioEffect = when (effect.type) {
                                AudioEffect.EFFECT_TYPE_EQUALIZER -> {
                                    Equalizer(0, 0) // priority, audioSession
                                }
                                AudioEffect.EFFECT_TYPE_BASS_BOOST -> {
                                    BassBoost(0, 0) // priority, audioSession
                                }
                                AudioEffect.EFFECT_TYPE_VIRTUALIZER -> {
                                    Virtualizer(0, 0) // priority, audioSession
                                }
                                else -> {
                                    // 对于其他类型的音效，使用类型和 UUID 创建
                                    // 注意：AudioEffect 的通用构造函数需要特定的参数
                                    null
                                }
                            }
                            
                            if (audioEffect != null && audioEffect.hasControl()) {
                                audioEffect.setEnabled(true)
                                activeAudioEffects.add(audioEffect)
                            } else if (audioEffect != null) {
                                audioEffect.release()
                            }
                        } catch (e: Exception) {
                            // 某些音效可能无法手动启用（需要特定的音频会话 ID 或权限）
                        }
                    }
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
            
            // ✅ 释放所有音效实例
            activeAudioEffects.forEach { it.release() }
            activeAudioEffects.clear()
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let {
                    audioMgr.abandonAudioFocusRequest(it)
                }
            } else {
                @Suppress("DEPRECATION")
                audioMgr.abandonAudioFocus(null)
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
    
    // ✅ 获取设备商用名称
    private fun getMarketName(): String {
        // 优先使用系统属性 ro.product.marketname
        val prop = getSystemProperty("ro.product.marketname")
        if (prop.isNotEmpty()) {
            return prop
        }
        
        // 备选：manufacturer + model
        return "${Build.MANUFACTURER} ${Build.MODEL}"
    }
    
    // ✅ 读取系统属性
    private fun getSystemProperty(propName: String): String {
        return try {
            val process = Runtime.getRuntime().exec("getprop $propName")
            process.inputStream.bufferedReader().use(BufferedReader::readText).trim()
        } catch (e: Exception) {
            ""
        }
    }
    
}

