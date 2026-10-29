package com.vidyadesk.vidyadesk

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Opens a UPI app to pay, and hands the app's reply (with the UTR) back to Flutter.
// Also saves PDFs / Excel files into Download/VidyaDesk and opens them.
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val upiRequest = 4417

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vidyadesk/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> {
                    val name = call.argument<String>("name") ?: "file"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("bad_file", "No data", null)
                    } else {
                        try {
                            result.success(saveDownload(name, mime, bytes))
                        } catch (e: NeedPermission) {
                            result.error("need_permission", "Allow storage", null)
                        } catch (e: Exception) {
                            result.error("save_failed", e.message, null)
                        }
                    }
                }
                "open" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri"))
                        val intent = Intent(Intent.ACTION_VIEW)
                        intent.setDataAndType(uri, call.argument<String>("mime"))
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(Intent.createChooser(intent, "Open with"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
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

    private class NeedPermission : Exception()

    private fun saveDownload(name: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues()
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            values.put(MediaStore.MediaColumns.MIME_TYPE, mime)
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/VidyaDesk")
            values.put(MediaStore.MediaColumns.IS_PENDING, 1)
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw Exception("Could not create file")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: throw Exception("Could not write file")
            val done = ContentValues()
            done.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, done, null, null)
            return uri.toString()
        }
        // Android 7–9: needs storage permission
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4418)
            throw NeedPermission()
        }
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "VidyaDesk")
        dir.mkdirs()
        var file = File(dir, name)
        var n = 1
        while (file.exists()) {
            val dot = name.lastIndexOf('.')
            file = if (dot > 0) File(dir, name.substring(0, dot) + " (" + n + ")" + name.substring(dot)) else File(dir, "$name ($n)")
            n++
        }
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
        return "path:" + file.absolutePath
    }
}
