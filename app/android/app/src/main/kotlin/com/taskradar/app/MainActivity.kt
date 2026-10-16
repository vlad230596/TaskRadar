package com.taskradar.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Emulator QA package only (`tests/android/`): Dart reports the first
        // rasterized frame that already shows the cached board, and Android
        // turns it into the standard "Fully drawn" launch metric. The regular
        // package never registers the channel.
        if (packageName != "com.taskradar.app.qa") return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taskradar/qa")
            .setMethodCallHandler { call, result ->
                if (call.method == "cachedBoardRasterized") {
                    reportFullyDrawn()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
