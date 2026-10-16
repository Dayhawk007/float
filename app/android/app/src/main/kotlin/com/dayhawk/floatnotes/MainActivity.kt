package com.dayhawk.floatnotes

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val systemChannel = "float/system"
    private var clipboardManager: ClipboardManager? = null
    private var events: EventChannel.EventSink? = null
    private val clipboardListener = ClipboardManager.OnPrimaryClipChangedListener { sendClipboardText() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "float/clipboard_history").setStreamHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel).setMethodCallHandler { call, result ->
            if (call.method == "openOverlaySettings") {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        events = eventSink
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(clipboardListener)
    }

    override fun onCancel(arguments: Any?) {
        clipboardManager?.removePrimaryClipChangedListener(clipboardListener)
        events = null
    }

    override fun onDestroy() {
        onCancel(null)
        super.onDestroy()
    }

    private fun sendClipboardText() {
        val manager = clipboardManager ?: return
        val clip = manager.primaryClip ?: return
        if (!manager.hasPrimaryClip() || !clip.description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)) return
        val text = clip.getItemAt(0).coerceToText(this)?.toString()?.trim().orEmpty()
        if (text.isNotEmpty()) runOnUiThread { events?.success(text) }
    }
}
