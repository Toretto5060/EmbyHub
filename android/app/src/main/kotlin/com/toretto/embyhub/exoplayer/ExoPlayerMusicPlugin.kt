package com.toretto.embyhub.exoplayer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.PlaybackParameters
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.source.DefaultMediaSourceFactory
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.toretto.embyhub.R
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * ExoPlayer 音乐播放器插件
 * 支持：
 * - 音乐播放控制（播放、暂停、跳转、上一首、下一首）
 * - 系统媒体通知（锁屏/通知栏显示）
 * - MediaSession 集成（蓝牙耳机、车载系统控制）
 * - 音频焦点管理
 * - 播放列表管理
 */
class ExoPlayerMusicPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null
    private var player: ExoPlayer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    
    // MediaSession 相关
    private var mediaSession: MediaSessionCompat? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    
    // 通知相关
    private val NOTIFICATION_ID = 2001  // 与视频播放器使用不同的 ID
    private val CHANNEL_ID = "music_playback_channel"
    private var isNotificationActive: Boolean = false  // 通知是否激活（播放过才激活）
    
    // 当前播放信息
    private var currentTitle: String = ""
    private var currentArtist: String = ""
    private var currentAlbum: String = ""
    private var currentCoverUrl: String? = null
    private var currentCoverBitmap: Bitmap? = null
    
    // 播放列表
    private var playlist: MutableList<MediaItem> = mutableListOf()
    private var playlistMetadata: MutableList<Map<String, Any?>> = mutableListOf()
    private var currentIndex: Int = 0
    
    // 封面加载线程池
    private val coverExecutor = Executors.newSingleThreadExecutor()
    
    // 广播接收器（用于通知栏按钮）
    private var mediaReceiver: BroadcastReceiver? = null
    
    // ✅ 音频淡入淡出相关
    private var fadeAnimator: android.animation.ValueAnimator? = null
    private var crossfadeAnimator: android.animation.ValueAnimator? = null
    private var targetVolume: Float = 1.0f  // 目标音量
    private var isFadingOut: Boolean = false  // 是否正在淡出
    
    // ✅ Crossfade 交叉淡化：使用第二个播放器实现真正的交叉淡化
    private var crossfadePlayer: ExoPlayer? = null
    private var fadingOutPlayerRef: ExoPlayer? = null  // 保存淡出播放器的引用
    private var isCrossfading: Boolean = false
    
    companion object {
        const val ACTION_PLAY = "com.toretto.embyhub.music.PLAY"
        const val ACTION_PAUSE = "com.toretto.embyhub.music.PAUSE"
        const val ACTION_NEXT = "com.toretto.embyhub.music.NEXT"
        const val ACTION_PREVIOUS = "com.toretto.embyhub.music.PREVIOUS"
        const val ACTION_STOP = "com.toretto.embyhub.music.STOP"
        
        // 淡入淡出时长（毫秒）- 播放/暂停使用较短时间
        const val FADE_DURATION_MS = 300L
        
        // Crossfade 交叉淡化时长（毫秒）- 切换歌曲使用
        const val CROSSFADE_DURATION_MS = 1500L
    }
    
    // 进度更新是否正在运行
    private var isProgressRunnableRunning = false
    
    private val progressRunnable = object : Runnable {
        override fun run() {
            sendStateUpdate()
            // 同时更新 MediaSession 进度，让媒体通知的进度条正确显示
            updateMediaSessionState()
            if (isProgressRunnableRunning) {
                handler.postDelayed(this, 500)
            }
        }
    }
    
    private fun startProgressUpdates() {
        if (!isProgressRunnableRunning) {
            isProgressRunnableRunning = true
            handler.post(progressRunnable)
        }
    }
    
    private fun stopProgressUpdates() {
        if (isProgressRunnableRunning) {
            isProgressRunnableRunning = false
            handler.removeCallbacks(progressRunnable)
        }
    }
    
    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            sendStateUpdate()
            updateNotification()
            updateMediaSessionState()
            
            // 当播放器准备好时，更新 MediaSession 元数据（此时 duration 才有效）
            if (playbackState == Player.STATE_READY) {
                updateMediaSessionMetadata()
            }
            
            // 播放结束时自动播放下一首（但 crossfade 过程中不处理，避免冲突）
            if (playbackState == Player.STATE_ENDED && !isCrossfading) {
                if (currentIndex < playlist.size - 1) {
                    playNextWithFade()
                } else {
                    // 播放列表结束
                    eventSink?.success(hashMapOf(
                        "event" to "playlistEnded"
                    ))
                }
            }
        }
        
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            sendStateUpdate()
            updateNotification()
            updateMediaSessionState()
        }
        
        override fun onPlayerError(error: PlaybackException) {
            eventSink?.success(hashMapOf(
                "event" to "error",
                "message" to (error.localizedMessage ?: "Unknown playback error")
            ))
        }
        
        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // 在 crossfade 过程中，元数据已经在 startRealCrossfade 中更新了，不需要再次更新
            // 避免重复更新导致的问题
            if (mediaItem != null && !isCrossfading) {
                // 同步 currentIndex 与播放器的实际索引
                val p = player
                if (p != null) {
                    currentIndex = p.currentMediaItemIndex
                }
                updateCurrentMetadata()
                updateMediaSessionMetadata()
                updateMediaSessionState()
                updateNotification()
            }
        }
    }
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        
        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "com.embyhub/exoplayer_music"
        )
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(
            binding.binaryMessenger,
            "com.embyhub/exoplayer_music/events"
        )
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // 启动进度更新（如果还没启动）
                startProgressUpdates()
                sendStateUpdate()
            }
            
            override fun onCancel(arguments: Any?) {
                // 注意：不要停止进度更新，因为媒体通知仍然需要更新进度
                eventSink = null
            }
        })
        
        // 初始化 AudioManager
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        
        // 创建通知渠道
        createNotificationChannel()
        
        // 注册广播接收器
        registerMediaReceiver()
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopProgressUpdates()
        methodChannel.setMethodCallHandler(null)
        disposePlayer()
        releaseMediaSession()
        hideNotification()
        unregisterMediaReceiver()
        coverExecutor.shutdown()
        eventSink = null
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                initializePlayer()
                result.success(true)
            }
            
            "open" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("invalid_args", "url is required.", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val title = call.argument<String>("title") ?: ""
                val artist = call.argument<String>("artist") ?: ""
                val album = call.argument<String>("album") ?: ""
                val coverUrl = call.argument<String>("coverUrl")
                val startPositionMs = call.argument<Number>("startPositionMs")?.toLong()
                val autoPlay = call.argument<Boolean>("autoPlay") ?: true
                
                openMedia(url, headers, title, artist, album, coverUrl, startPositionMs, autoPlay)
                result.success(null)
            }
            
            "setPlaylist" -> {
                @Suppress("UNCHECKED_CAST")
                val items = call.argument<List<Map<String, Any?>>>("items")
                if (items == null) {
                    result.error("invalid_args", "items is required.", null)
                    return
                }
                val startIndex = call.argument<Int>("startIndex") ?: 0
                val autoPlay = call.argument<Boolean>("autoPlay") ?: true
                val startPositionMs = call.argument<Number>("startPositionMs")?.toLong() ?: 0L
                
                setPlaylist(items, startIndex, autoPlay, startPositionMs)
                result.success(null)
            }
            
            "play" -> {
                // 先请求音频焦点，再播放（带淡入效果）
                requestAudioFocus()
                playWithFadeIn()
                result.success(null)
            }
            
            "pause" -> {
                // 带淡出效果的暂停
                pauseWithFadeOut()
                result.success(null)
            }
            
            "stop" -> {
                // 带淡出效果的停止
                stopWithFadeOut()
                result.success(null)
            }
            
            "seekTo" -> {
                val position = call.argument<Number>("positionMs")?.toLong() ?: 0L
                // 在 crossfade 过程中，seek 操作应该作用于新播放器
                val targetPlayer = if (isCrossfading) crossfadePlayer else player
                targetPlayer?.seekTo(position)
                // 更新 MediaSession 状态，确保进度条正确显示
                updateMediaSessionState()
                result.success(null)
            }
            
            "next" -> {
                // 带淡出淡入效果的下一首
                playNextWithFade()
                result.success(null)
            }
            
            "previous" -> {
                // 带淡出淡入效果的上一首
                playPreviousWithFade()
                result.success(null)
            }
            
            "skipToIndex" -> {
                val index = call.argument<Int>("index") ?: 0
                skipToIndex(index)
                result.success(null)
            }
            
            "setRate" -> {
                val rate = (call.argument<Double>("rate") ?: 1.0).toFloat().coerceAtLeast(0.1f)
                val current = player?.playbackParameters
                player?.playbackParameters = PlaybackParameters(rate, current?.pitch ?: 1.0f)
                result.success(null)
            }
            
            "setVolume" -> {
                val volume = (call.argument<Double>("volume") ?: 1.0).toFloat().coerceIn(0f, 1f)
                targetVolume = volume  // 保存目标音量
                player?.volume = volume
                result.success(null)
            }
            
            "setRepeatMode" -> {
                val mode = call.argument<String>("mode") ?: "off"
                player?.repeatMode = when (mode) {
                    "one" -> Player.REPEAT_MODE_ONE
                    "all" -> Player.REPEAT_MODE_ALL
                    else -> Player.REPEAT_MODE_OFF
                }
                result.success(null)
            }
            
            "setShuffleMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                player?.shuffleModeEnabled = enabled
                result.success(null)
            }
            
            "updateMetadata" -> {
                val title = call.argument<String>("title") ?: currentTitle
                val artist = call.argument<String>("artist") ?: currentArtist
                val album = call.argument<String>("album") ?: currentAlbum
                val coverUrl = call.argument<String>("coverUrl")
                
                currentTitle = title
                currentArtist = artist
                currentAlbum = album
                if (coverUrl != null) {
                    currentCoverUrl = coverUrl
                    loadCoverAsync(coverUrl)
                }
                
                updateMediaSessionMetadata()
                updateNotification()
                result.success(null)
            }
            
            "dispose" -> {
                disposePlayer()
                releaseMediaSession()
                hideNotification()
                result.success(null)
            }
            
            "isPlayerReady" -> {
                // 检查播放器是否准备好（有媒体源且可以播放）
                val p = player
                val isReady = p != null && p.playbackState == Player.STATE_READY
                result.success(isReady)
            }
            
            else -> result.notImplemented()
        }
    }
    
    private fun initializePlayer() {
        if (player != null) return
        
        val ctx = context ?: return
        
        val exoPlayer = ExoPlayer.Builder(ctx).build()
        
        // 设置音频属性
        // 注意：handleAudioFocus 设为 false，我们手动管理音频焦点
        // 这样可以避免与手动请求的音频焦点冲突
        exoPlayer.setAudioAttributes(
            com.google.android.exoplayer2.audio.AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(),
            false  // 不让 ExoPlayer 自动管理音频焦点
        )
        
        exoPlayer.setHandleAudioBecomingNoisy(true)  // 耳机拔出时暂停
        exoPlayer.repeatMode = Player.REPEAT_MODE_OFF
        exoPlayer.addListener(playerListener)
        
        player = exoPlayer
        
        // 初始化 MediaSession
        initMediaSession()
        
        // 启动进度更新（用于更新媒体通知的进度条）
        startProgressUpdates()
        
        sendStateUpdate()
    }
    
    private fun openMedia(
        url: String,
        headers: Map<String, String>,
        title: String,
        artist: String,
        album: String,
        coverUrl: String?,
        startPositionMs: Long?,
        autoPlay: Boolean
    ) {
        initializePlayer()
        
        // 更新当前播放信息
        currentTitle = title
        currentArtist = artist
        currentAlbum = album
        currentCoverUrl = coverUrl
        
        // 清空播放列表
        playlist.clear()
        playlistMetadata.clear()
        currentIndex = 0
        
        // 异步加载封面
        if (!coverUrl.isNullOrEmpty()) {
            loadCoverAsync(coverUrl)
        } else {
            currentCoverBitmap = null
        }
        
        val ctx = context ?: return
        
        // 创建数据源工厂（支持本地文件和网络 URL）
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(30000)
            .setReadTimeoutMs(60000)
            .apply {
                if (headers.isNotEmpty()) {
                    setDefaultRequestProperties(headers)
                }
            }
        
        // DefaultDataSource 会根据 URI scheme 自动选择合适的数据源
        // 支持 file://, content://, http://, https:// 等
        val dataSourceFactory = DefaultDataSource.Factory(ctx, httpDataSourceFactory)
        
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
        
        // 处理本地文件路径
        val uri = if (url.startsWith("/") && !url.startsWith("file://")) {
            "file://$url"
        } else {
            url
        }
        val mediaItem = MediaItem.fromUri(uri)
        
        playlist.add(mediaItem)
        playlistMetadata.add(mapOf(
            "url" to url,
            "title" to title,
            "artist" to artist,
            "album" to album,
            "coverUrl" to coverUrl
        ))
        
        val p = player ?: return
        
        if (startPositionMs != null && startPositionMs > 0) {
            p.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem), startPositionMs)
        } else {
            p.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem))
        }
        
        // 先请求音频焦点，再准备播放
        if (autoPlay) {
            requestAudioFocus()
        }
        
        p.prepare()
        p.playWhenReady = autoPlay
        
        // 更新 MediaSession 元数据和状态
        updateMediaSessionMetadata()
        updateMediaSessionState()
        
        // 只在自动播放时激活通知
        if (autoPlay) {
            showNotification()
        }
        
        sendStateUpdate()
    }
    
    private fun setPlaylist(items: List<Map<String, Any?>>, startIndex: Int, autoPlay: Boolean, startPositionMs: Long = 0L) {
        initializePlayer()
        
        playlist.clear()
        playlistMetadata.clear()
        
        val p = player ?: return
        
        val mediaItems = mutableListOf<MediaItem>()
        
        for (item in items) {
            val url = item["url"] as? String ?: continue
            @Suppress("UNCHECKED_CAST")
            val headers = item["headers"] as? Map<String, String> ?: emptyMap()
            
            // 处理本地文件路径
            val uri = if (url.startsWith("/") && !url.startsWith("file://")) {
                "file://$url"
            } else {
                url
            }
            
            val mediaItem = MediaItem.Builder()
                .setUri(uri)
                .build()
            
            mediaItems.add(mediaItem)
            playlist.add(mediaItem)
            playlistMetadata.add(item)
        }
        
        if (mediaItems.isEmpty()) return
        
        currentIndex = startIndex.coerceIn(0, mediaItems.size - 1)
        
        // 更新当前播放信息
        updateCurrentMetadata()
        
        // 先请求音频焦点，再设置播放列表
        if (autoPlay) {
            requestAudioFocus()
        }
        
        // 设置播放列表（支持从指定位置开始播放）
        p.setMediaItems(mediaItems, currentIndex, startPositionMs)
        p.prepare()
        p.playWhenReady = autoPlay
        
        // 更新 MediaSession 元数据和状态
        updateMediaSessionMetadata()
        updateMediaSessionState()
        
        // 只在自动播放时激活通知
        if (autoPlay) {
            showNotification()
        }
        
        sendStateUpdate()
    }
    
    private fun updateCurrentMetadata() {
        if (currentIndex >= 0 && currentIndex < playlistMetadata.size) {
            val metadata = playlistMetadata[currentIndex]
            currentTitle = metadata["title"] as? String ?: ""
            currentArtist = metadata["artist"] as? String ?: ""
            currentAlbum = metadata["album"] as? String ?: ""
            currentCoverUrl = metadata["coverUrl"] as? String
            
            if (!currentCoverUrl.isNullOrEmpty()) {
                loadCoverAsync(currentCoverUrl!!)
            } else {
                currentCoverBitmap = null
            }
            
            // 通知 Flutter 曲目变化
            eventSink?.success(hashMapOf(
                "event" to "trackChanged",
                "index" to currentIndex,
                "title" to currentTitle,
                "artist" to currentArtist,
                "album" to currentAlbum,
                "coverUrl" to currentCoverUrl
            ))
        }
    }
    
    private fun playNext() {
        val p = player ?: return
        if (p.hasNextMediaItem()) {
            p.seekToNextMediaItem()
            currentIndex = p.currentMediaItemIndex
            updateCurrentMetadata()
            updateMediaSessionMetadata()
            updateNotification()
        }
    }
    
    private fun playPrevious() {
        val p = player ?: return
        // 如果当前播放超过 3 秒，则重新播放当前曲目
        if (p.currentPosition > 3000) {
            p.seekTo(0)
        } else if (p.hasPreviousMediaItem()) {
            p.seekToPreviousMediaItem()
            currentIndex = p.currentMediaItemIndex
            updateCurrentMetadata()
            updateMediaSessionMetadata()
            updateNotification()
        } else {
            p.seekTo(0)
        }
    }
    
    private fun skipToIndex(index: Int) {
        val p = player ?: return
        if (index >= 0 && index < playlist.size) {
            p.seekTo(index, 0)
            currentIndex = index
            updateCurrentMetadata()
            updateMediaSessionMetadata()
            updateMediaSessionState()
            updateNotification()
            sendStateUpdate()
        }
    }
    
    // ==================== 淡入淡出控制 ====================
    
    /**
     * 带淡入效果的播放
     */
    private fun playWithFadeIn() {
        // 如果正在 crossfade，立即完成
        if (isCrossfading) {
            finishCrossfadeImmediately()
        }
        
        val p = player ?: return
        
        // 取消之前的淡入淡出动画
        cancelFadeAnimation()
        
        // 先设置音量为0，然后开始播放
        p.volume = 0f
        p.play()
        
        // 播放时激活通知
        showNotification()
        
        // 立即发送状态更新，让 UI 响应更快
        sendStateUpdate()
        // 更新 MediaSession 状态，确保进度条正确显示
        updateMediaSessionState()
        
        // 淡入到目标音量
        fadeAnimator = android.animation.ValueAnimator.ofFloat(0f, targetVolume).apply {
            duration = FADE_DURATION_MS
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener { animator ->
                player?.volume = animator.animatedValue as Float
            }
            start()
        }
    }
    
    /**
     * 带淡出效果的暂停
     */
    private fun pauseWithFadeOut() {
        // 如果正在 crossfade，立即完成并暂停新播放器
        if (isCrossfading) {
            finishCrossfadeImmediately()
        }
        
        val p = player ?: return
        
        // 取消之前的淡入淡出动画
        cancelFadeAnimation()
        
        // 立即发送状态更新，让 UI 响应更快
        isFadingOut = true
        sendStateUpdate()
        
        val currentVolume = p.volume
        
        // 淡出到0，然后暂停
        fadeAnimator = android.animation.ValueAnimator.ofFloat(currentVolume, 0f).apply {
            duration = FADE_DURATION_MS
            interpolator = android.view.animation.AccelerateInterpolator()
            addUpdateListener { animator ->
                player?.volume = animator.animatedValue as Float
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    player?.pause()
                    player?.volume = targetVolume  // 恢复音量设置
                    isFadingOut = false
                }
            })
            start()
        }
    }
    
    /**
     * 带淡出效果的停止
     */
    private fun stopWithFadeOut() {
        // 如果正在 crossfade，立即完成
        if (isCrossfading) {
            finishCrossfadeImmediately()
        }
        
        val p = player ?: return
        
        // 取消之前的淡入淡出动画
        cancelFadeAnimation()
        
        val currentVolume = p.volume
        
        // 淡出到0，然后停止
        fadeAnimator = android.animation.ValueAnimator.ofFloat(currentVolume, 0f).apply {
            duration = FADE_DURATION_MS
            interpolator = android.view.animation.AccelerateInterpolator()
            addUpdateListener { animator ->
                player?.volume = animator.animatedValue as Float
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    player?.stop()
                    player?.volume = targetVolume
                    abandonAudioFocus()
                    hideNotification()
                }
            })
            start()
        }
    }
    
    /**
     * ✅ Crossfade 交叉淡化切换下一首
     * 当前歌曲淡出的同时，下一首歌曲淡入，实现无缝切换
     */
    private fun playNextWithFade() {
        if (player == null) return
        
        // 如果正在 crossfade，立即完成之前的
        if (isCrossfading) {
            finishCrossfadeImmediately()
        }
        cancelFadeAnimation()
        
        // 计算下一首的索引
        val nextIndex = currentIndex + 1
        if (nextIndex >= playlist.size) return
        
        // 开始真正的 Crossfade
        startRealCrossfade(nextIndex)
    }
    
    /**
     * ✅ Crossfade 交叉淡化切换上一首
     */
    private fun playPreviousWithFade() {
        if (player == null) return
        
        // 如果正在 crossfade，立即完成之前的
        if (isCrossfading) {
            finishCrossfadeImmediately()
        }
        cancelFadeAnimation()
        
        // 重新获取 player 引用（因为 finishCrossfadeImmediately 可能已经切换了播放器）
        val p = player ?: return
        
        // 如果当前播放超过 3 秒，则重新播放当前曲目（带淡入淡出）
        if (p.currentPosition > 3000) {
            restartCurrentTrackWithFade()
            return
        }
        
        // 如果已经是第一首，只是重新播放
        if (currentIndex == 0) {
            restartCurrentTrackWithFade()
            return
        }
        
        // 计算上一首的索引
        val prevIndex = currentIndex - 1
        
        // 开始真正的 Crossfade
        startRealCrossfade(prevIndex)
    }
    
    /**
     * ✅ 重新播放当前曲目（带淡入淡出）
     */
    private fun restartCurrentTrackWithFade() {
        val p = player ?: return
        val currentVolume = p.volume
        
        fadeAnimator = android.animation.ValueAnimator.ofFloat(currentVolume, 0f).apply {
            duration = FADE_DURATION_MS
            interpolator = android.view.animation.AccelerateInterpolator()
            addUpdateListener { animator ->
                player?.volume = animator.animatedValue as Float
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    player?.seekTo(0)
                    // 更新 MediaSession 状态
                    updateMediaSessionState()
                    // 淡入
                    fadeAnimator = android.animation.ValueAnimator.ofFloat(0f, targetVolume).apply {
                        duration = FADE_DURATION_MS
                        interpolator = android.view.animation.DecelerateInterpolator()
                        addUpdateListener { animator ->
                            player?.volume = animator.animatedValue as Float
                        }
                        start()
                    }
                }
            })
            start()
        }
    }
    
    /**
     * ✅ 开始真正的 Crossfade 交叉淡化
     * 使用双播放器方案：当前歌曲淡出的同时，下一首歌曲淡入
     * @param targetIndex 目标歌曲索引
     */
    private fun startRealCrossfade(targetIndex: Int) {
        val ctx = context ?: return
        val fadingOutPlayer = player ?: return
        
        if (targetIndex < 0 || targetIndex >= playlist.size) return
        
        isCrossfading = true
        
        // 保存淡出播放器的引用（用于动画中安全操作）
        fadingOutPlayerRef = fadingOutPlayer
        
        // 立即更新 UI 状态（歌曲信息、封面等）
        currentIndex = targetIndex
        updateCurrentMetadata()
        updateMediaSessionMetadata()
        updateMediaSessionState()
        updateNotification()
        sendStateUpdate()
        
        // 创建第二个播放器用于播放下一首
        val newPlayer = ExoPlayer.Builder(ctx).build().apply {
            setAudioAttributes(
                com.google.android.exoplayer2.audio.AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                false  // 不自动处理音频焦点
            )
            setHandleAudioBecomingNoisy(true)
            volume = 0f  // 初始音量为0，准备淡入
        }
        
        // 获取目标媒体项的元数据以获取 headers
        val targetMetadata = playlistMetadata.getOrNull(targetIndex)
        @Suppress("UNCHECKED_CAST")
        val headers = targetMetadata?.get("headers") as? Map<String, String> ?: emptyMap()
        
        // 创建数据源
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(30000)
            .setReadTimeoutMs(60000)
            .apply {
                if (headers.isNotEmpty()) {
                    setDefaultRequestProperties(headers)
                }
            }
        val dataSourceFactory = DefaultDataSource.Factory(ctx, httpDataSourceFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
        
        // 设置完整播放列表到新播放器
        val mediaSources = playlist.map { mediaSourceFactory.createMediaSource(it) }
        newPlayer.setMediaSources(mediaSources, targetIndex, 0)
        newPlayer.prepare()
        newPlayer.playWhenReady = true
        
        crossfadePlayer = newPlayer
        
        // 当前播放器的起始音量
        val startVolume = fadingOutPlayer.volume
        
        // 开始交叉淡化动画：当前歌曲淡出，下一首歌曲淡入，同时进行
        crossfadeAnimator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = CROSSFADE_DURATION_MS
            interpolator = android.view.animation.LinearInterpolator()
            addUpdateListener { animator ->
                val progress = animator.animatedValue as Float
                
                // 当前歌曲淡出：从 startVolume 到 0（使用保存的引用）
                fadingOutPlayerRef?.volume = startVolume * (1f - progress)
                
                // 下一首歌曲淡入：从 0 到 targetVolume
                crossfadePlayer?.volume = targetVolume * progress
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    // Crossfade 完成，切换播放器
                    finishCrossfade()
                }
                
                override fun onAnimationCancel(animation: android.animation.Animator) {
                    // 注意：cancel 后不做任何处理，由调用者决定如何处理
                }
            })
            start()
        }
    }
    
    /**
     * ✅ 完成 Crossfade，切换播放器
     */
    private fun finishCrossfade() {
        val newPlayer = crossfadePlayer ?: return
        val oldPlayer = fadingOutPlayerRef  // 使用保存的淡出播放器引用
        
        // 停止并释放旧播放器
        oldPlayer?.let {
            it.removeListener(playerListener)
            it.stop()
            it.release()
        }
        
        // 清理 crossfade 状态（在添加 listener 之前，避免触发不必要的回调）
        crossfadePlayer = null
        fadingOutPlayerRef = null
        crossfadeAnimator = null
        isCrossfading = false
        
        // 新播放器成为主播放器
        player = newPlayer
        newPlayer.volume = targetVolume
        newPlayer.addListener(playerListener)
        
        // 发送最终状态更新
        sendStateUpdate()
        // 更新 MediaSession 状态，确保进度条正确显示
        updateMediaSessionState()
    }
    
    /**
     * ✅ 立即完成 Crossfade（用于快速连续切歌）
     */
    private fun finishCrossfadeImmediately() {
        // 先保存引用，再取消动画（因为 cancel 不会触发任何回调处理）
        val newPlayer = crossfadePlayer
        val oldPlayer = fadingOutPlayerRef
        
        crossfadeAnimator?.cancel()
        crossfadeAnimator = null
        
        if (newPlayer != null) {
            // 立即切换到新播放器
            oldPlayer?.let {
                it.removeListener(playerListener)
                it.stop()
                it.release()
            }
            
            // 清理 crossfade 状态（在添加 listener 之前）
            crossfadePlayer = null
            fadingOutPlayerRef = null
            isCrossfading = false
            
            // 新播放器成为主播放器
            player = newPlayer
            newPlayer.volume = targetVolume
            newPlayer.addListener(playerListener)
            // 更新 MediaSession 状态
            updateMediaSessionState()
        } else {
            // 没有新播放器，只清理状态
            crossfadePlayer = null
            fadingOutPlayerRef = null
            isCrossfading = false
        }
    }
    
    /**
     * ✅ 取消 Crossfade 并清理资源（恢复到原来的状态）
     */
    private fun cancelCrossfade() {
        crossfadeAnimator?.cancel()
        crossfadeAnimator = null
        
        // 释放新播放器（crossfadePlayer）
        crossfadePlayer?.let {
            it.stop()
            it.release()
        }
        crossfadePlayer = null
        
        // 清理淡出播放器引用（但不释放，因为它仍然是主播放器）
        fadingOutPlayerRef = null
        
        // 恢复主播放器音量
        player?.volume = targetVolume
        
        isCrossfading = false
    }
    
    /**
     * ✅ 清理 Crossfade 资源（不切换播放器）
     */
    private fun cleanupCrossfade() {
        crossfadePlayer?.let {
            it.stop()
            it.release()
        }
        crossfadePlayer = null
        fadingOutPlayerRef = null
        isCrossfading = false
    }
    
    /**
     * 取消淡入淡出动画
     */
    private fun cancelFadeAnimation() {
        fadeAnimator?.cancel()
        fadeAnimator = null
        isFadingOut = false
    }
    
    private fun loadCoverAsync(url: String) {
        coverExecutor.execute {
            try {
                val bitmap: Bitmap? = if (url.startsWith("/") || url.startsWith("file://")) {
                    // 本地文件路径
                    val filePath = if (url.startsWith("file://")) {
                        url.removePrefix("file://")
                    } else {
                        url
                    }
                    val file = java.io.File(filePath)
                    if (file.exists()) {
                        BitmapFactory.decodeFile(filePath)
                    } else {
                        null
                    }
                } else {
                    // 网络 URL
                    val connection = URL(url).openConnection()
                    connection.connectTimeout = 5000
                    connection.readTimeout = 10000
                    BitmapFactory.decodeStream(connection.getInputStream())
                }
                
                currentCoverBitmap = bitmap
                
                // 在主线程更新通知和 MediaSession
                handler.post {
                    updateMediaSessionMetadata()
                    updateNotification()
                }
            } catch (e: Exception) {
                currentCoverBitmap = null
            }
        }
    }
    
    // 默认封面缓存
    private var defaultAlbumCoverBitmap: Bitmap? = null
    
    /// 获取默认专辑封面
    private fun getDefaultAlbumCover(): Bitmap? {
        if (defaultAlbumCoverBitmap != null) {
            return defaultAlbumCoverBitmap
        }
        
        val ctx = context ?: return null
        
        try {
            // 从 drawable 资源加载默认封面
            val drawable = androidx.core.content.ContextCompat.getDrawable(ctx, R.drawable.default_album_cover)
            if (drawable != null) {
                val bitmap = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                defaultAlbumCoverBitmap = bitmap
                return bitmap
            }
        } catch (e: Exception) {
            // 忽略加载失败
        }
        
        return null
    }
    
    // ==================== MediaSession ====================
    
    private fun initMediaSession() {
        val ctx = context ?: return
        
        if (mediaSession != null) return
        
        mediaSession = MediaSessionCompat(ctx, "EmbyHubMusicSession").apply {
            isActive = true
            
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    requestAudioFocus()
                    playWithFadeIn()
                    // 通知 Flutter 端播放状态变化（由媒体通知触发）
                    handler.post {
                        eventSink?.success(mapOf("event" to "mediaButtonPlay"))
                    }
                }
                
                override fun onPause() {
                    pauseWithFadeOut()
                    // 通知 Flutter 端暂停状态变化（由媒体通知触发）
                    handler.post {
                        eventSink?.success(mapOf("event" to "mediaButtonPause"))
                    }
                }
                
                override fun onStop() {
                    stopWithFadeOut()
                    // 通知 Flutter 端停止状态变化（由媒体通知触发）
                    handler.post {
                        eventSink?.success(mapOf("event" to "mediaButtonStop"))
                    }
                }
                
                override fun onSkipToNext() {
                    // 通知 Flutter 端处理下一曲（支持随机播放模式）
                    if (eventSink != null) {
                        handler.post {
                            eventSink?.success(mapOf(
                                "event" to "mediaButtonNext"
                            ))
                        }
                    } else {
                        // 如果 eventSink 为空，直接在原生端处理
                        handler.post {
                            playNextWithFade()
                        }
                    }
                }
                
                override fun onSkipToPrevious() {
                    // 通知 Flutter 端处理上一曲（支持随机播放模式）
                    if (eventSink != null) {
                        handler.post {
                            eventSink?.success(mapOf(
                                "event" to "mediaButtonPrevious"
                            ))
                        }
                    } else {
                        // 如果 eventSink 为空，直接在原生端处理
                        handler.post {
                            playPreviousWithFade()
                        }
                    }
                }
                
                override fun onSeekTo(pos: Long) {
                    player?.seekTo(pos)
                }
                
                override fun onSkipToQueueItem(id: Long) {
                    skipToIndex(id.toInt())
                }
            })
            
            // 设置支持的操作
            setPlaybackState(PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_STOP or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_SKIP_TO_QUEUE_ITEM
                )
                .setState(PlaybackStateCompat.STATE_NONE, 0, 1.0f)
                .build()
            )
        }
    }
    
    private fun updateMediaSessionState() {
        val session = mediaSession ?: return
        
        // 在 crossfade 过程中，使用新播放器的状态
        val p = if (isCrossfading) crossfadePlayer ?: player else player
        if (p == null) {
            return
        }
        
        val state = when {
            p.isPlaying -> PlaybackStateCompat.STATE_PLAYING
            p.playbackState == Player.STATE_BUFFERING -> PlaybackStateCompat.STATE_BUFFERING
            p.playbackState == Player.STATE_ENDED -> PlaybackStateCompat.STATE_STOPPED
            else -> PlaybackStateCompat.STATE_PAUSED
        }
        
        val position = max(0L, p.currentPosition)
        val speed = p.playbackParameters.speed
        
        session.setPlaybackState(PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_SKIP_TO_QUEUE_ITEM
            )
            .setState(state, position, speed)
            .build()
        )
    }
    
    private fun updateMediaSessionMetadata() {
        val session = mediaSession ?: return
        
        // 在 crossfade 过程中，使用新播放器的时长
        val p = if (isCrossfading) crossfadePlayer ?: player else player
        if (p == null) return
        
        val duration = if (p.duration == C.TIME_UNSET) 0L else p.duration
        
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, currentAlbum)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
        
        // 使用封面或默认封面
        val coverBitmap = currentCoverBitmap ?: getDefaultAlbumCover()
        coverBitmap?.let {
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
        }
        
        session.setMetadata(builder.build())
    }
    
    private fun releaseMediaSession() {
        mediaSession?.let {
            it.isActive = false
            it.release()
        }
        mediaSession = null
    }
    
    // ==================== 音频焦点 ====================
    
    private fun requestAudioFocus() {
        val audioMgr = audioManager ?: return
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 如果已经有焦点请求，先放弃
            audioFocusRequest?.let {
                audioMgr.abandonAudioFocusRequest(it)
            }
            
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            
            val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener { focusChange ->
                    when (focusChange) {
                        AudioManager.AUDIOFOCUS_LOSS -> {
                            player?.pause()
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            player?.pause()
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            player?.volume = 0.3f
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            player?.volume = 1.0f
                            // 不自动恢复播放，让用户手动控制
                        }
                    }
                }
                .build()
            
            audioFocusRequest = focusRequest
            audioMgr.requestAudioFocus(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioMgr.requestAudioFocus(
                { focusChange ->
                    when (focusChange) {
                        AudioManager.AUDIOFOCUS_LOSS,
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            player?.pause()
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            player?.volume = 0.3f
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            player?.volume = 1.0f
                        }
                    }
                },
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
    }
    
    private fun abandonAudioFocus() {
        val audioMgr = audioManager ?: return
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let {
                audioMgr.abandonAudioFocusRequest(it)
            }
        } else {
            @Suppress("DEPRECATION")
            audioMgr.abandonAudioFocus(null)
        }
    }
    
    // ==================== 通知 ====================
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ctx = context ?: return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "音乐播放",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示正在播放的音乐"
                setShowBadge(false)
            }
            val notificationManager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun updateNotification() {
        val ctx = context ?: return
        val session = mediaSession ?: return
        
        // 在 crossfade 过程中，使用新播放器的状态
        val p = if (isCrossfading) crossfadePlayer ?: player else player
        if (p == null) return
        
        // 如果通知还没激活（还没开始播放过），不显示通知
        if (!isNotificationActive) {
            return
        }
        
        if (p.playbackState == Player.STATE_IDLE) {
            hideNotification()
            return
        }
        
        val isPlaying = p.isPlaying
        
        // 上一首按钮
        val prevAction = NotificationCompat.Action(
            android.R.drawable.ic_media_previous,
            "上一首",
            PendingIntent.getBroadcast(
                ctx, 0,
                Intent(ACTION_PREVIOUS).setPackage(ctx.packageName),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        
        // 播放/暂停按钮
        val playPauseAction = if (isPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "暂停",
                PendingIntent.getBroadcast(
                    ctx, 1,
                    Intent(ACTION_PAUSE).setPackage(ctx.packageName),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "播放",
                PendingIntent.getBroadcast(
                    ctx, 1,
                    Intent(ACTION_PLAY).setPackage(ctx.packageName),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }
        
        // 下一首按钮
        val nextAction = NotificationCompat.Action(
            android.R.drawable.ic_media_next,
            "下一首",
            PendingIntent.getBroadcast(
                ctx, 2,
                Intent(ACTION_NEXT).setPackage(ctx.packageName),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        
        // 点击通知打开应用
        val contentIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(
                ctx, 0, it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        
        // 删除通知时停止播放
        val deleteIntent = PendingIntent.getBroadcast(
            ctx, 3,
            Intent(ACTION_STOP).setPackage(ctx.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        // 使用封面或默认封面
        val notificationCover = currentCoverBitmap ?: getDefaultAlbumCover()
        
        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setContentTitle(currentTitle.ifEmpty { "未知歌曲" })
            .setContentText(currentArtist.ifEmpty { "未知艺术家" })
            .setSubText(currentAlbum)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(notificationCover)
            .setStyle(MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))  // 显示所有三个按钮
            .addAction(prevAction)
            .addAction(playPauseAction)
            .addAction(nextAction)
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .setOngoing(isPlaying)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        
        val notificationManager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
    
    private fun hideNotification() {
        val ctx = context ?: return
        val notificationManager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
        isNotificationActive = false  // 重置通知状态
    }
    
    /**
     * 显示通知（首次播放时调用）
     */
    private fun showNotification() {
        isNotificationActive = true
        // 更新 MediaSession 状态，确保进度条正确显示
        updateMediaSessionState()
        updateNotification()
    }
    
    // ==================== 广播接收器 ====================
    
    private fun registerMediaReceiver() {
        val ctx = context ?: return
        
        mediaReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    ACTION_PLAY -> {
                        requestAudioFocus()
                        playWithFadeIn()
                    }
                    ACTION_PAUSE -> {
                        pauseWithFadeOut()
                    }
                    ACTION_NEXT -> {
                        playNextWithFade()
                    }
                    ACTION_PREVIOUS -> {
                        playPreviousWithFade()
                    }
                    ACTION_STOP -> {
                        stopWithFadeOut()
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY)
            addAction(ACTION_PAUSE)
            addAction(ACTION_NEXT)
            addAction(ACTION_PREVIOUS)
            addAction(ACTION_STOP)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.registerReceiver(mediaReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            ctx.registerReceiver(mediaReceiver, filter)
        }
    }
    
    private fun unregisterMediaReceiver() {
        val ctx = context ?: return
        mediaReceiver?.let {
            try {
                ctx.unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore
            }
        }
        mediaReceiver = null
    }
    
    // ==================== 状态更新 ====================
    
    private fun sendStateUpdate() {
        val sink = eventSink ?: return
        
        // 在 crossfade 过程中，使用新播放器（crossfadePlayer）的状态
        // 这样 UI 显示的是新歌曲的进度
        val p = if (isCrossfading) crossfadePlayer ?: player else player
        
        if (p == null) {
            sink.success(hashMapOf(
                "event" to "state",
                "position_ms" to 0L,
                "duration_ms" to 0L,
                "buffered_ms" to 0L,
                "isBuffering" to false,
                "isPlaying" to false,
                "isReady" to false,
                "currentIndex" to 0,
                "playlistLength" to 0,
                "repeatMode" to "off",
                "shuffleMode" to false
            ))
            return
        }
        
        val duration = if (p.duration == C.TIME_UNSET) -1 else p.duration
        val position = max(0L, p.currentPosition)
        val buffered = max(position, p.bufferedPosition)
        
        val repeatMode = when (p.repeatMode) {
            Player.REPEAT_MODE_ONE -> "one"
            Player.REPEAT_MODE_ALL -> "all"
            else -> "off"
        }
        
        // 如果正在淡出，立即报告为暂停状态，让 UI 响应更快
        val isPlaying = if (isFadingOut) false else p.isPlaying
        
        val state = hashMapOf(
            "event" to "state",
            "position_ms" to position,
            "duration_ms" to duration,
            "buffered_ms" to buffered,
            "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
            "isPlaying" to isPlaying,
            "isReady" to (p.playbackState == Player.STATE_READY),
            "currentIndex" to currentIndex,  // 使用我们维护的 currentIndex，而不是播放器的
            "playlistLength" to playlist.size,
            "repeatMode" to repeatMode,
            "shuffleMode" to p.shuffleModeEnabled
        )
        sink.success(state)
    }
    
    private fun disposePlayer() {
        // 停止进度更新
        stopProgressUpdates()
        
        // 取消淡入淡出动画和 Crossfade
        cancelFadeAnimation()
        cancelCrossfade()
        
        val toRelease = player ?: return
        player = null
        handler.post {
            toRelease.removeListener(playerListener)
            toRelease.release()
            sendStateUpdate()
        }
    }
}

