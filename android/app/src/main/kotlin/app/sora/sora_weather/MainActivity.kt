package app.sora.sora_weather

import android.content.ComponentCallbacks2
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import app.sora.sora_weather.ai.LocalAiPlugin

class MainActivity : FlutterActivity() {
    private var localAi: LocalAiPlugin? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = LocalAiPlugin { active ->
            if (active) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        localAi = plugin
        flutterEngine.plugins.add(plugin)
    }
    override fun onStop() { localAi?.onBackground(); super.onStop() }
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) localAi?.onBackground()
    }
}
