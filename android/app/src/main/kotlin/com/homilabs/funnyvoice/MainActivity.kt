package com.homilabs.funnyvoice

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens this app's page in Android settings, so a refused microphone can be allowed again.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.homilabs.funnyvoice/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openAppSettings") {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
