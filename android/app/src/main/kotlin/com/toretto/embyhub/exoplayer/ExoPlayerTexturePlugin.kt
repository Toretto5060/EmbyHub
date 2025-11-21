package com.toretto.embyhub.exoplayer

import android.content.Context
import android.net.TrafficStats
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.LoadControl
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.PlaybackParameters
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.DefaultRenderersFactory
import com.google.android.exoplayer2.RenderersFactory
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.source.DefaultMediaSourceFactory
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.util.MimeTypes
import com.google.android.exoplayer2.video.VideoSize
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import kotlin.math.max

class ExoPlayerTexturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var eventSink: EventChannel.EventSink? = null
    private var renderersFactory: DefaultRenderersFactory? = null
    private val handler = Handler(Looper.getMainLooper())

    // ✅ 网络速度计算相关变量（使用系统 TrafficStats）
    private var lastTotalRxBytes: Long = 0
    private var lastSpeedUpdateTime: Long = 0
    private var currentNetworkSpeedBps: Long = 0

    private val progressRunnable = object : Runnable {
        override fun run() {
            sendStateUpdate()
            handler.postDelayed(this, 500)
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            sendStateUpdate()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            sendStateUpdate()
        }

        override fun onPlayerError(error: PlaybackException) {
            eventSink?.success(
                hashMapOf(
                    "event" to "error",
                    "message" to (error.localizedMessage ?: "Unknown playback error")
                )
            )
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            eventSink?.success(
                hashMapOf(
                    "event" to "videoSize",
                    "width" to videoSize.width,
                    "height" to videoSize.height
                )
            )
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "com.embyhub/exoplayer_texture"
        )
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(
            binding.binaryMessenger,
            "com.embyhub/exoplayer_texture/events"
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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handler.removeCallbacks(progressRunnable)
        methodChannel.setMethodCallHandler(null)
        disposePlayer()
        surface?.release()
        textureEntry?.release()
        surface = null
        textureEntry = null
        eventSink = null
        renderersFactory = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                initializeTextureIfNeeded()
                val textureId = textureEntry?.id()
                if (textureId != null) {
                    result.success(textureId)
                } else {
                    result.error("texture_init_failed", "Unable to allocate texture.", null)
                }
            }

            "open" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("invalid_args", "url is required.", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val headers = (call.argument<Map<String, String>>("headers")) ?: emptyMap()
                val startPositionMs = (call.argument<Number>("startPositionMs"))?.toLong()
                val autoPlay = call.argument<Boolean>("autoPlay") ?: true
                val isHls = call.argument<Boolean>("isHls") ?: false
                @Suppress("UNCHECKED_CAST")
                val cacheConfig =
                    call.argument<Map<String, Any>>("cacheConfig")
                openMedia(url, headers, startPositionMs, autoPlay, cacheConfig, isHls)
                result.success(null)
            }

            "play" -> {
                player?.play()
                result.success(null)
            }

            "pause" -> {
                player?.pause()
                result.success(null)
            }

            "seekTo" -> {
                val position = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                player?.seekTo(position)
                result.success(null)
            }

            "setRate" -> {
                val rate = (call.argument<Double>("rate") ?: 1.0).toFloat().coerceAtLeast(0.1f)
                val current = player?.playbackParameters
                player?.playbackParameters =
                    PlaybackParameters(rate, current?.pitch ?: 1.0f)
                result.success(null)
            }

            "setVolume" -> {
                val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                player?.volume = volume.coerceIn(0f, 1f)
                result.success(null)
            }

            "disableSubtitles" -> {
                disableSubtitles()
                result.success(null)
            }

            "dispose" -> {
                disposePlayer()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun initializeTextureIfNeeded() {
        if (textureEntry != null && player != null) return

        val registry = textureRegistry ?: return
        if (textureEntry == null) {
            textureEntry = registry.createSurfaceTexture().also {
                it.surfaceTexture().setDefaultBufferSize(1920, 1080)
                surface = Surface(it.surfaceTexture())
            }
        }
        if (player == null) {
            rebuildPlayer(null)
        }
    }

    private fun rebuildPlayer(loadControl: LoadControl?) {
        val ctx = context ?: return

        player?.removeListener(playerListener)
        player?.release()
        player = null

        if (trackSelector == null) {
            trackSelector = DefaultTrackSelector(ctx).apply {
                parameters = buildUponParameters()
                    .setRendererDisabled(C.TRACK_TYPE_TEXT, true)
                    .build()
            }
        }

        val builder = ExoPlayer.Builder(ctx, obtainRenderersFactory(ctx))
            .setTrackSelector(trackSelector!!)
        if (loadControl != null) {
            builder.setLoadControl(loadControl)
        }
        val exoPlayer = builder.build()
        val surface = this.surface
        if (surface != null) {
            exoPlayer.setVideoSurface(surface)
        }
        exoPlayer.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.CONTENT_TYPE_MOVIE)
                .build(),
            true
        )
        exoPlayer.setHandleAudioBecomingNoisy(true)
        exoPlayer.repeatMode = Player.REPEAT_MODE_OFF
        exoPlayer.addListener(playerListener)
        player = exoPlayer
        sendStateUpdate()
    }

    private fun obtainRenderersFactory(ctx: Context): RenderersFactory {
        val existing = renderersFactory
        if (existing != null) {
            return existing
        }
        val factory = DefaultRenderersFactory(ctx)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)
            .setEnableDecoderFallback(true)
        renderersFactory = factory
        return factory
    }

    private fun openMedia(
        url: String,
        headers: Map<String, String>,
        startPositionMs: Long?,
        autoPlay: Boolean,
        cacheConfig: Map<String, Any>?,
        isHls: Boolean
    ) {
        initializeTextureIfNeeded()

        val loadControl = cacheConfig?.let { buildLoadControl(it) }
        if (loadControl != null || player == null) {
            rebuildPlayer(loadControl)
        }

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(30000)
            .apply {
                if (headers.isNotEmpty()) {
                    setDefaultRequestProperties(headers)
                }
            }

        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        val mediaItemBuilder = MediaItem.Builder()
            .setUri(url)
        if (isHls) {
            mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        val mediaItem = mediaItemBuilder.build()

        player?.setMediaSource(mediaSourceFactory.createMediaSource(mediaItem))
        player?.prepare()
        if (startPositionMs != null && startPositionMs > 0) {
            player?.seekTo(startPositionMs)
        } else {
            player?.seekTo(0)
        }
        player?.playWhenReady = autoPlay
        if (!autoPlay) {
            player?.pause()
        }
        sendStateUpdate()
    }

    private fun buildLoadControl(config: Map<String, Any>): LoadControl {
        val builder = com.google.android.exoplayer2.DefaultLoadControl.Builder()
        val minBufferMs = (config["minBufferMs"] as Number?)?.toInt()
        val maxBufferMs = (config["maxBufferMs"] as Number?)?.toInt()
        val bufferForPlaybackMs =
            (config["bufferForPlaybackMs"] as Number?)?.toInt()
        val bufferForPlaybackAfterRebufferMs =
            (config["bufferForPlaybackAfterRebufferMs"] as Number?)?.toInt()
        if (minBufferMs != null && maxBufferMs != null &&
            bufferForPlaybackMs != null && bufferForPlaybackAfterRebufferMs != null
        ) {
            builder.setBufferDurationsMs(
                minBufferMs,
                maxBufferMs,
                bufferForPlaybackMs,
                bufferForPlaybackAfterRebufferMs
            )
        }
        return builder.build()
    }

    private fun disableSubtitles() {
        val selector = trackSelector ?: return
        val builder = selector.buildUponParameters()
            .setRendererDisabled(C.TRACK_TYPE_TEXT, true)
        selector.parameters = builder.build()
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

    private fun sendStateUpdate() {
        val sink = eventSink ?: return
        val player = this.player ?: return
        val duration = if (player.duration == C.TIME_UNSET) -1 else player.duration
        val position = max(0L, player.currentPosition)
        val buffered = max(position, player.bufferedPosition)
        
        // ✅ 使用系统 TrafficStats 计算真实网络速度（与状态栏一致）
        val isBuffering = player.playbackState == Player.STATE_BUFFERING
        val currentTime = System.currentTimeMillis()
        
        // ✅ 每秒更新一次网络速度
        if (currentTime - lastSpeedUpdateTime >= 1000) {
            val currentRxBytes = TrafficStats.getTotalRxBytes()
            
            if (lastTotalRxBytes > 0 && currentRxBytes > lastTotalRxBytes) {
                // ✅ 计算 1 秒内接收的字节数
                val bytesReceived = currentRxBytes - lastTotalRxBytes
                val timeDiffSeconds = (currentTime - lastSpeedUpdateTime) / 1000.0
                
                // ✅ 转换为 bps (bits per second)
                currentNetworkSpeedBps = ((bytesReceived * 8) / timeDiffSeconds).toLong()
            }
            
            lastTotalRxBytes = currentRxBytes
            lastSpeedUpdateTime = currentTime
        }
        
        // ✅ 不在缓冲时，不显示速度（设为 0）
        val networkSpeed = if (isBuffering) currentNetworkSpeedBps else 0L
        
        val state = hashMapOf(
            "event" to "state",
            "position_ms" to position,
            "duration_ms" to duration,
            "buffered_ms" to buffered,
            "isBuffering" to isBuffering,
            "isPlaying" to player.isPlaying,
            "isReady" to (player.playbackState == Player.STATE_READY),
            "networkSpeedBps" to networkSpeed
        )
        sink.success(state)
    }
}

