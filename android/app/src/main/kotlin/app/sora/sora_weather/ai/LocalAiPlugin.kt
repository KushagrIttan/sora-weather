package app.sora.sora_weather.ai

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import com.google.ai.edge.litertlm.*
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Model management and JNI inference run off Flutter's platform/UI thread.
 * Registration and status never initialise an LLM or start a download. */
class LocalAiPlugin(private val keepAwake: (Boolean) -> Unit = {}) : FlutterPlugin,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var store: ModelStore
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val conversationLock = Any()
    private var conversation: Conversation? = null
    private var engine: Engine? = null // Only accessed on worker.
    @Volatile private var operation = ""
    @Volatile private var releaseRequested = false
    @Volatile private var detached = false
    private var sink: EventChannel.EventSink? = null // Main thread only.
    private val idleRelease = Runnable { release() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val asset = binding.flutterAssets.getAssetFilePathByName("assets/ai/qwen3_06b.json")
        val spec = context.assets.open(asset).bufferedReader().use {
            Gson().fromJson(it, ModelSpec::class.java)
        }
        require(spec.runtime == "0.19.1") { "Model and runtime versions must stay paired." }
        store = ModelStore(File(context.noBackupFilesDir, "sora_ai/${spec.id}"), spec)
        channel = MethodChannel(binding.binaryMessenger, "sora_weather/local_ai")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "sora_weather/local_ai/progress")
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun memoryInfo() = ActivityManager.MemoryInfo().also {
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(it)
    }

    private fun supported() = Build.VERSION.SDK_INT >= 24 &&
        Build.SUPPORTED_ABIS.any { it == "arm64-v8a" || it == "x86_64" }

    private fun status(): Map<String, Any> = mapOf(
        "supported" to supported(), "installed" to store.isInstalled,
        "modelName" to store.spec.name, "modelBytes" to store.spec.bytes,
        "partialBytes" to store.partialBytes, "busy" to busy.get(),
        "freeBytes" to StatFs(context.noBackupFilesDir.path).availableBytes,
        "availableMemoryBytes" to memoryInfo().availMem, "backend" to "cpu",
        "runtime" to store.spec.runtime,
    )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "cancel" -> { cancelCurrent(); result.success(null) }
            "unload" -> {
                releaseRequested = true
                worker.execute {
                    closeEngine()
                    main.post { if (!detached) result.success(null) }
                }
            }
            "install", "remove", "generate" -> {
                if (!supported()) {
                    result.error("unsupported", "On-device AI needs 64-bit Android 7 or newer.", null)
                    return
                }
                if (!busy.compareAndSet(false, true)) {
                    result.error("busy", "The local model is busy. Try again shortly.", null)
                    return
                }
                main.removeCallbacks(idleRelease)
                cancelled.set(false)
                releaseRequested = false
                operation = call.method
                keepAwake(true)
                val delivered = AtomicBoolean(false)
                fun success(value: Any?) {
                    if (delivered.compareAndSet(false, true)) main.post {
                        if (!detached) result.success(value)
                    }
                }
                fun failure(code: String, message: String) {
                    if (delivered.compareAndSet(false, true)) main.post {
                        if (!detached) result.error(code, message, null)
                    }
                }
                val deadline = if (call.method == "generate") timer.schedule({
                    // A finishing request must not cancel the following one.
                    if (delivered.compareAndSet(false, true)) {
                        cancelCurrent()
                        releaseRequested = true
                        main.post { if (!detached) result.error("timeout",
                            "On-device AI took too long. Showing local picks instead.", null) }
                    }
                }, 45, TimeUnit.SECONDS) else null
                worker.execute {
                    var response: Any? = null
                    var failureCode: String? = null
                    var failureMessage: String? = null
                    try {
                        response = when (call.method) {
                            "install" -> {
                                closeEngine()
                                var lastProgress = 0L
                                store.install(
                                    availableBytes = { StatFs(context.noBackupFilesDir.path).availableBytes },
                                    cancelled = { cancelled.get() },
                                    progress = { received, total ->
                                        val now = System.currentTimeMillis()
                                        if (received == total || now - lastProgress > 200) {
                                            lastProgress = now
                                            main.post { sink?.success(mapOf("received" to received, "total" to total)) }
                                        }
                                    },
                                )
                                null
                            }
                            "remove" -> {
                                closeEngine()
                                store.remove()
                                // This dedicated runtime cache never contains application data.
                                File(context.cacheDir, "sora_ai").deleteRecursively()
                                null
                            }
                            else -> generate(call)
                        }
                        if (cancelled.get()) throw CancellationException("Local AI request cancelled.")
                    } catch (error: Throwable) {
                        releaseRequested = true
                        failureCode = if (cancelled.get()) "cancelled" else "local_ai_error"
                        failureMessage = when (error) {
                                is OutOfMemoryError -> "Not enough memory for the model right now. Showing local picks."
                                else -> error.message?.take(240) ?: "The local model could not complete this request."
                            }
                    } finally {
                        deadline?.cancel(false)
                        if (releaseRequested) closeEngine()
                        operation = ""
                        busy.set(false)
                        main.post {
                            keepAwake(false)
                            if (!detached) main.postDelayed(idleRelease, 30_000)
                        }
                    }
                    // Deliver after cleanup, so a retry cannot race the prior
                    // request's busy flag or its engine.close(). Deadline errors
                    // still return early when native initialization cannot stop.
                    if (failureCode != null) failure(failureCode, failureMessage ?: "Local AI failed.")
                    else success(response)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun generate(call: MethodCall): Map<String, Any> {
        check(store.isInstalled) { "Download the Qwen model in Settings first. Local rules are still available." }
        check(!memoryInfo().lowMemory) { "Android is low on memory. Try local AI again later." }
        val prompt = call.argument<String>("prompt") ?: error("Missing prompt.")
        val system = call.argument<String>("system") ?: error("Missing system instruction.")
        val task = call.argument<String>("task") ?: error("Missing AI task.")
        require(task == "rank") { "Unknown AI task." }
        require(prompt.length + system.length <= 6500) { "This request is too long for the small local model." }
        val started = System.nanoTime()
        if (engine == null) {
            check(store.verify()) { "Model checksum failed. Remove and download the model again." }
            if (cancelled.get()) throw CancellationException()
            val cache = File(context.cacheDir, "sora_ai").apply { mkdirs() }
            val next = Engine(EngineConfig(
                modelPath = store.modelFile.absolutePath,
                backend = Backend.CPU(threadCount = 3),
                maxNumTokens = store.spec.contextTokens,
                cacheDir = cache.absolutePath,
            ))
            try { next.initialize() } catch (error: Throwable) { runCatching { next.close() }; throw error }
            engine = next
        }
        if (cancelled.get()) throw CancellationException()
        val config = ConversationConfig(
            systemInstruction = Contents.of(system),
            tools = emptyList(),
            automaticToolCalling = false,
            extraContext = mapOf("enable_thinking" to false),
            thinkingConfig = ThinkingConfig(enableThinking = false),
            samplerConfig = SamplerConfig(topK = 1, topP = 1.0, temperature = 0.0),
            maxOutputToken = minOf(128, store.spec.maxOutputTokens),
            enableResponseFormat = true,
        )
        val nextConversation = engine!!.createConversation(config)
        try {
            synchronized(conversationLock) { conversation = nextConversation }
            if (cancelled.get()) throw CancellationException()
            val format = ResponseFormat.json(
                call.argument<String>("schema") ?: error("Missing output schema.")
            )
            val response = nextConversation.sendMessage(prompt, responseFormat = format)
            return mapOf(
                "text" to response.toString().take(12000),
                "toolCalls" to response.toolCalls.take(3).map {
                    mapOf("name" to it.name, "arguments" to it.arguments)
                },
                "elapsedMs" to (System.nanoTime() - started) / 1_000_000,
            )
        } finally {
            synchronized(conversationLock) { conversation = null; nextConversation.close() }
        }
    }

    private fun cancelCurrent() {
        cancelled.set(true)
        synchronized(conversationLock) { runCatching { conversation?.cancelProcess() } }
    }

    /** Called when the activity leaves the foreground; never starts inference. */
    fun onBackground() {
        if (operation == "generate") cancelCurrent()
        release()
    }

    private fun release() {
        releaseRequested = true
        if (!detached) worker.execute { if (!busy.get()) closeEngine() }
    }

    private fun closeEngine() {
        runCatching { engine?.close() }
        engine = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        main.removeCallbacks(idleRelease)
        keepAwake(false)
        cancelCurrent()
        releaseRequested = true
        worker.execute { closeEngine() }
        worker.shutdown()
        timer.shutdownNow()
    }
}
