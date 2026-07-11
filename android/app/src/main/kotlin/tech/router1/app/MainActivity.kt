package tech.router1.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "tech.router1.app/awg"
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var backend: GoBackend
    private var pendingConfig: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var state = Tunnel.State.DOWN
    private val tunnel = object : Tunnel {
        override fun getName() = "Router1"
        override fun onStateChange(newState: Tunnel.State) { state = newState }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backend = GoBackend(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val intent = VpnService.prepare(this)
                        if (intent == null) result.success(true)
                        else {
                            pendingResult = result
                            startActivityForResult(intent, 7001)
                        }
                    }
                    "connect" -> {
                        val config = call.argument<String>("config").orEmpty()
                        if (config.isBlank()) result.error("EMPTY_CONFIG", "Конфиг пуст", null)
                        else connect(config, result)
                    }
                    "disconnect" -> runAsync(result) {
                        backend.setState(tunnel, Tunnel.State.DOWN, null)
                        mapOf("state" to "down")
                    }
                    "status" -> runAsync(result) {
                        val actual = backend.getState(tunnel)
                        mapOf(
                            "state" to actual.name.lowercase(),
                            "handshake" to backend.getLastHandshake(tunnel),
                            "version" to backend.version
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun connect(configText: String, result: MethodChannel.Result) {
        if (VpnService.prepare(this) != null) {
            pendingConfig = configText
            pendingResult = result
            startActivityForResult(VpnService.prepare(this), 7002)
            return
        }
        runAsync(result) {
            val config = Config.parse(ByteArrayInputStream(configText.toByteArray(Charsets.UTF_8)))
            openFileOutput("router1-awg.conf", MODE_PRIVATE).use { it.write(configText.toByteArray()) }
            backend.setState(tunnel, Tunnel.State.UP, config)
            mapOf("state" to "up", "version" to backend.version)
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread { result.error("AWG_ERROR", error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7001) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
        } else if (requestCode == 7002) {
            val result = pendingResult
            val config = pendingConfig
            pendingResult = null
            pendingConfig = null
            if (resultCode == Activity.RESULT_OK && result != null && config != null) connect(config, result)
            else result?.error("VPN_DENIED", "Разрешение VPN не предоставлено", null)
        }
    }
}
