package tech.router1.app

import android.app.Activity
import android.app.DownloadManager
import android.content.Intent
import android.net.VpnService
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import java.io.ByteArrayInputStream
import java.util.LinkedHashMap
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private var sharedBackend: GoBackend? = null
    }

    private val channelName = "tech.router1.app/awg"
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var backend: GoBackend
    private var pendingConfig: String? = null
    private var pendingServerCode: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var state = Tunnel.State.DOWN
    private val tunnel = object : Tunnel {
        override fun getName() = "Router1"
        override fun onStateChange(newState: Tunnel.State) { state = newState }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backend = sharedBackend ?: GoBackend(applicationContext).also { sharedBackend = it }
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
                        val serverCode = call.argument<String>("serverCode").orEmpty()
                        if (config.isBlank()) result.error("EMPTY_CONFIG", "Конфиг пуст", null)
                        else connect(config, serverCode, result)
                    }
                    "configureFailover" -> {
                        runAsync(result) {
                            val primaryServer = call.argument<String>("primaryServer").orEmpty()
                            val activeServer = call.argument<String>("activeServer").orEmpty()
                            val rawNodes = call.argument<List<Map<String, Any?>>>("nodes").orEmpty()
                            val configs = LinkedHashMap<String, Config>()
                            for (node in rawNodes) {
                                val code = node["serverCode"]?.toString().orEmpty()
                                val text = node["config"]?.toString().orEmpty()
                                if (code.isNotBlank() && text.isNotBlank()) {
                                    configs[code] = Config.parse(
                                        ByteArrayInputStream(text.toByteArray(Charsets.UTF_8)))
                                }
                            }
                            backend.configureFailover(
                                primaryServer,
                                activeServer,
                                configs,
                                call.argument<Int>("failureSamples") ?: 3,
                                call.argument<Int>("handshakeStaleSeconds") ?: 180,
                                call.argument<Int>("switchCooldownSeconds") ?: 300
                            )
                            configs.size > 1
                        }
                    }
                    "disconnect" -> runAsync(result) {
                        backend.setState(tunnel, Tunnel.State.DOWN, null)
                        getSharedPreferences("router1_awg", MODE_PRIVATE)
                            .edit().putBoolean("enabled", false).apply()
                        mapOf("state" to "down")
                    }
                    "status" -> runAsync(result) {
                        val actual = backend.getState(tunnel)
                        val statistics = backend.getStatistics(tunnel)
                        mapOf(
                            "state" to actual.name.lowercase(),
                            "handshake" to backend.getLastHandshake(tunnel),
                            "rx" to statistics.totalRx(),
                            "tx" to statistics.totalTx(),
                            "serverCode" to backend.activeFailoverServer,
                            "version" to backend.version
                        )
                    }
                    "installUpdate" -> {
                        val url = call.argument<String>("url").orEmpty()
                        installUpdate(url, result)
                    }
                    else -> result.notImplemented()
                }
            }
        restoreTunnelIfRequested()
    }

    private fun installUpdate(url: String, result: MethodChannel.Result) {
        val uri = runCatching { Uri.parse(url) }.getOrNull()
        if (uri == null || uri.scheme != "https" || uri.host != "router1.tech") {
            result.error("INVALID_UPDATE_URL", "Недопустимая ссылка обновления", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ))
            result.error(
                "INSTALL_PERMISSION",
                "Разрешите установку обновлений для Router1 и нажмите «Обновить» ещё раз",
                null
            )
            return
        }
        val request = DownloadManager.Request(uri)
            .setTitle("Обновление Router1")
            .setDescription("Скачиваем новую версию")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setMimeType("application/vnd.android.package-archive")
            .setDestinationInExternalFilesDir(
                this,
                Environment.DIRECTORY_DOWNLOADS,
                "router1-internal-update.apk"
            )
        val manager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        val id = manager.enqueue(request)
        getSharedPreferences("router1_updates", MODE_PRIVATE)
            .edit().putLong("download_id", id).apply()
        result.success(true)
    }

    private fun connect(
        configText: String,
        serverCode: String,
        result: MethodChannel.Result
    ) {
        if (VpnService.prepare(this) != null) {
            pendingConfig = configText
            pendingServerCode = serverCode
            pendingResult = result
            startActivityForResult(VpnService.prepare(this), 7002)
            return
        }
        runAsync(result) {
            val config = Config.parse(ByteArrayInputStream(configText.toByteArray(Charsets.UTF_8)))
            openFileOutput("router1-awg.conf", MODE_PRIVATE).use { it.write(configText.toByteArray()) }
            backend.setState(tunnel, Tunnel.State.UP, config)
            if (serverCode.isNotBlank()) backend.setActiveFailoverServer(serverCode)
            getSharedPreferences("router1_awg", MODE_PRIVATE)
                .edit().putBoolean("enabled", true).apply()
            mapOf("state" to "up", "version" to backend.version)
        }
    }

    private fun restoreTunnelIfRequested() {
        val enabled = getSharedPreferences("router1_awg", MODE_PRIVATE)
            .getBoolean("enabled", false)
        val file = getFileStreamPath("router1-awg.conf")
        if (!enabled || !file.exists() || VpnService.prepare(this) != null) return
        executor.execute {
            try {
                if (backend.getState(tunnel) == Tunnel.State.UP) return@execute
                val config = file.inputStream().use { Config.parse(it) }
                backend.setState(tunnel, Tunnel.State.UP, config)
            } catch (_: Exception) {
                // Статус и точная ошибка будут доступны через MethodChannel после запуска UI.
            }
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
            val serverCode = pendingServerCode.orEmpty()
            pendingResult = null
            pendingConfig = null
            pendingServerCode = null
            if (resultCode == Activity.RESULT_OK && result != null && config != null) {
                connect(config, serverCode, result)
            }
            else result?.error("VPN_DENIED", "Разрешение VPN не предоставлено", null)
        }
    }
}
