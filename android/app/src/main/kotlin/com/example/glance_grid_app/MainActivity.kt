package com.example.glance_grid_app

import android.os.Bundle
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "facecount"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "initRuntime" -> {
                        val configPath = call.argument<String>("configPath")
                        try {
                            initRuntime(configPath)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INIT_ERROR", e.localizedMessage, null)
                        }
                    }
                    "analyzeJpegBytes" -> {
                        val bytes = call.argument<ByteArray>("jpegBytes")
                        if (bytes == null) {
                            result.error("INVALID_ARGS", "jpegBytes missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val output = analyzeJpegBytes(bytes)
                            result.success(output)
                        } catch (e: Exception) {
                            result.error("ANALYZE_ERROR", e.localizedMessage, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun initRuntime(configPath: String?) {
        val py = Python.getInstance()
        val module = py.getModule("src.chaquopy_bridge")
        if (configPath.isNullOrBlank()) {
            module.callAttr("init_runtime")
        } else {
            module.callAttr("init_runtime", configPath)
        }
    }

    private fun analyzeJpegBytes(jpegBytes: ByteArray): String {
        val py = Python.getInstance()
        val module = py.getModule("src.chaquopy_bridge")
        return module.callAttr("analyze_jpeg_bytes", jpegBytes).toString()
    }
}

