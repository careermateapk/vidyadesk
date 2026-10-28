package com.vidyadesk.vidyadesk

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Opens a UPI app to pay, and hands the app's reply (with the UTR) back to Flutter.
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val upiRequest = 4417

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vidyadesk/upi").setMethodCallHandler { call, result ->
            if (call.method != "pay") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrEmpty()) {
                result.error("bad_url", "No UPI link", null)
                return@setMethodCallHandler
            }
            val pkg = call.argument<String>("package")
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                if (!pkg.isNullOrEmpty()) intent.setPackage(pkg)
                pending?.success(null)
                pending = result
                val launch = if (pkg.isNullOrEmpty()) Intent.createChooser(intent, "Pay with") else intent
                startActivityForResult(launch, upiRequest)
            } catch (e: Exception) {
                pending = null
                result.error("no_app", e.message, null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == upiRequest) {
            val reply = data?.getStringExtra("response") ?: data?.getStringExtra("Status") ?: ""
            pending?.success(reply)
            pending = null
        }
    }
}
