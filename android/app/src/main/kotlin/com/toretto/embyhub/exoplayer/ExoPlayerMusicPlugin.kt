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
    
    companion object {
        const val ACTION_PLAY = "com.toretto.embyhub.music.PLAY"
        const val ACTION_PAUSE = "com.toretto.embyhub.music.PAUSE"
        const val ACTION_NEXT = "com.toretto.embyhub.music.NEXT"
        const val ACTION_PREVIOUS = "com.toretto.embyhub.music.PREVIOUS"
        const val ACTION_STOP = "com.toretto.embyhub.music.STOP"
    }
    
    private val progressRunnable = object : Runnable {
        override fun run() {
            sendStateUpdate()
            handler.postDelayed(this, 500)
        }
    }
    
    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val stateStr = when (playbackState) {
                Player.STATE_IDLE -> "IDLE"
                Player.STATE_BUFFERING -> "BUFFERING"
                Player.STATE_READY -> "READY"
                Player.STATE_ENDED -> "ENDED"
                else -> "UNKNOWN($playbackState)"
            }
            android.util.Log.d("ExoPlayerMusicPlugin", "Playback state changed: $stateStr")
            
            sendStateUpdate()
            updateNotification()
            updateMediaSessionState()
            
            // 播放结束时自动播放下一首
            if (playbackState == Player.STATE_ENDED) {
                if (currentIndex < playlist.size - 1) {
                    playNext()
                } else {
                    // 播放列表结束
                    eventSink?.success(hashMapOf(
                        "event" to "playlistEnded"
                    ))
                }
            }
        }
        
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            android.util.Log.d("ExoPlayerMusicPlugin", "isPlaying changed: $isPlaying")
            sendStateUpdate()
            updateNotification()
            updateMediaSessionState()
        }
        
        override fun onPlayerError(error: PlaybackException) {
            android.util.Log.e("ExoPlayerMusicPlugin", "Player error: ${error.errorCode} - ${error.message}", error)
            eventSink?.success(hashMapOf(
                "event" to "error",
                "message" to (error.localizedMessage ?: "Unknown playback error")
            ))
        }
        
        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            android.util.Log.d("ExoPlayerMusicPlugin", "Media item transition: ${mediaItem?.mediaId}, reason=$reason")
            // 切换到新的媒体项时更新元数据
            if (mediaItem != null) {
                updateCurrentMetadata()
                updateMediaSessionMetadata()
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
                handler.post(progressRunnable)
                sendStateUpdate()
            }
            
            override fun onCancel(arguments: Any?) {
                handler.removeCallbacks(progressRunnable)
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
        handler.removeCallbacks(progressRunnable)
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
                
                android.util.Log.d("ExoPlayerMusicPlugin", "open called: url=$url, title=$title, coverUrl=$coverUrl, autoPlay=$autoPlay")
                
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
                
                setPlaylist(items, startIndex, autoPlay)
                result.success(null)
            }
            
            "play" -> {
                // 先请求音频焦点，再播放
                requestAudioFocus()
                player?.play()
                result.success(null)
            }
            
            "pause" -> {
                player?.pause()
                result.success(null)
            }
            
            "stop" -> {
                player?.stop()
                abandonAudioFocus()
                hideNotification()
                result.success(null)
            }
            
            "seekTo" -> {
                val position = call.argument<Number>("positionMs")?.toLong() ?: 0L
                player?.seekTo(position)
                result.success(null)
            }
            
            "next" -> {
                playNext()
                result.success(null)
            }
            
            "previous" -> {
                playPrevious()
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
                val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                player?.volume = volume.coerceIn(0f, 1f)
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
            
            else -> result.notImplemented()
        }
    }
    
    private fun initializePlayer() {
        if (player != null) {
            android.util.Log.d("ExoPlayerMusicPlugin", "Player already initialized")
            return
        }
        
        val ctx = context ?: return
        
        android.util.Log.d("ExoPlayerMusicPlugin", "Initializing ExoPlayer for music")
        
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
        
        android.util.Log.d("ExoPlayerMusicPlugin", "ExoPlayer initialized successfully")
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
        
        android.util.Log.d("ExoPlayerMusicPlugin", "Opening media: $uri, autoPlay=$autoPlay")
        
        if (startPositionMs != null && startPositionMs > 0) {
            p.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem), startPositionMs)
        } else {
            p.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem))
        }
        
        // 先请求音频焦点，再准备播放
        if (autoPlay) {
            android.util.Log.d("ExoPlayerMusicPlugin", "Requesting audio focus before playback")
            requestAudioFocus()
        }
        
        android.util.Log.d("ExoPlayerMusicPlugin", "Preparing player")
        p.prepare()
        p.playWhenReady = autoPlay
        
        // 更新 MediaSession 和通知
        updateMediaSessionMetadata()
        updateNotification()
        
        android.util.Log.d("ExoPlayerMusicPlugin", "Media opened successfully")
        sendStateUpdate()
    }
    
    private fun setPlaylist(items: List<Map<String, Any?>>, startIndex: Int, autoPlay: Boolean) {
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
        
        // 设置播放列表
        p.setMediaItems(mediaItems, currentIndex, 0)
        p.prepare()
        p.playWhenReady = autoPlay
        
        updateMediaSessionMetadata()
        updateNotification()
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
            updateNotification()
        }
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
                        android.util.Log.w("ExoPlayerMusicPlugin", "Cover file not found: $filePath")
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
                android.util.Log.e("ExoPlayerMusicPlugin", "Failed to load cover: $e")
                currentCoverBitmap = null
            }
        }
    }
    
    // ==================== MediaSession ====================
    
    private fun initMediaSession() {
        val ctx = context ?: return
        
        if (mediaSession != null) return
        
        mediaSession = MediaSessionCompat(ctx, "EmbyHubMusicSession").apply {
            isActive = true
            
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    player?.play()
                    requestAudioFocus()
                }
                
                override fun onPause() {
                    player?.pause()
                }
                
                override fun onStop() {
                    player?.stop()
                    abandonAudioFocus()
                    hideNotification()
                }
                
                override fun onSkipToNext() {
                    playNext()
                }
                
                override fun onSkipToPrevious() {
                    playPrevious()
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
        val p = player ?: return
        
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
        val p = player ?: return
        
        val duration = if (p.duration == C.TIME_UNSET) 0L else p.duration
        
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, currentAlbum)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
        
        currentCoverBitmap?.let {
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
                    android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus changed: $focusChange")
                    when (focusChange) {
                        AudioManager.AUDIOFOCUS_LOSS -> {
                            android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus LOSS - pausing")
                            player?.pause()
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                            android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus LOSS_TRANSIENT - pausing")
                            player?.pause()
                        }
                        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus CAN_DUCK - lowering volume")
                            player?.volume = 0.3f
                        }
                        AudioManager.AUDIOFOCUS_GAIN -> {
                            android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus GAIN - resuming")
                            player?.volume = 1.0f
                            // 不自动恢复播放，让用户手动控制
                        }
                    }
                }
                .build()
            
            audioFocusRequest = focusRequest
            val result = audioMgr.requestAudioFocus(focusRequest)
            android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus request result: $result (GRANTED=1, FAILED=0, DELAYED=2)")
        } else {
            @Suppress("DEPRECATION")
            val result = audioMgr.requestAudioFocus(
                { focusChange ->
                    android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus changed (legacy): $focusChange")
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
            android.util.Log.d("ExoPlayerMusicPlugin", "Audio focus request result (legacy): $result")
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
        val p = player ?: return
        val session = mediaSession ?: return
        
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
        
        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setContentTitle(currentTitle.ifEmpty { "未知歌曲" })
            .setContentText(currentArtist.ifEmpty { "未知艺术家" })
            .setSubText(currentAlbum)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(currentCoverBitmap)
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
    }
    
    // ==================== 广播接收器 ====================
    
    private fun registerMediaReceiver() {
        val ctx = context ?: return
        
        mediaReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    ACTION_PLAY -> {
                        player?.play()
                        requestAudioFocus()
                    }
                    ACTION_PAUSE -> {
                        player?.pause()
                    }
                    ACTION_NEXT -> {
                        playNext()
                    }
                    ACTION_PREVIOUS -> {
                        playPrevious()
                    }
                    ACTION_STOP -> {
                        player?.stop()
                        abandonAudioFocus()
                        hideNotification()
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
        val p = player
        
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
        
        val state = hashMapOf(
            "event" to "state",
            "position_ms" to position,
            "duration_ms" to duration,
            "buffered_ms" to buffered,
            "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
            "isPlaying" to p.isPlaying,
            "isReady" to (p.playbackState == Player.STATE_READY),
            "currentIndex" to p.currentMediaItemIndex,
            "playlistLength" to playlist.size,
            "repeatMode" to repeatMode,
            "shuffleMode" to p.shuffleModeEnabled
        )
        sink.success(state)
    }
    
    private fun disposePlayer() {
        val toRelease = player ?: return
        player = null
        handler.post {
            toRelease.removeListener(playerListener)
            toRelease.release()
            sendStateUpdate()
        }
    }
}

