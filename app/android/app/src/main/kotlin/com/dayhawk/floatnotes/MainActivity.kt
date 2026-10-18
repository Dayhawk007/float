package com.dayhawk.floatnotes

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    private val systemChannel = "float/system"
    private var clipboardManager: ClipboardManager? = null
    private var events: EventChannel.EventSink? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val clipboardListener = ClipboardManager.OnPrimaryClipChangedListener { sendClipboardText() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "float/clipboard_history").setStreamHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "openOverlaySettings" -> {
                    startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "copyToClipboard" -> {
                    val text = call.argument<String>("text")?.trim().orEmpty()
                    if (text.isEmpty()) {
                        result.error("empty_text", "Nothing to copy.", null)
                    } else {
                        val manager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        manager.setPrimaryClip(ClipData.newPlainText("Float", text))
                        Log.d("FloatClipboard", "clipboard.write length=${text.length}")
                        result.success(null)
                    }
                }
                "getClipboardText" -> {
                    val manager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val text = manager.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()?.trim()
                    Log.d("FloatClipboard", "clipboard.read hasText=${!text.isNullOrEmpty()}")
                    result.success(text)
                }
                "acquireMulticastLock" -> {
                    val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    if (multicastLock == null) {
                        multicastLock = wifi.createMulticastLock("float-mdns").apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                        Log.d("FloatDiscovery", "mdns.multicast_lock.acquired")
                    }
                    result.success(null)
                }
                "releaseMulticastLock" -> {
                    multicastLock?.let { lock -> if (lock.isHeld) lock.release() }
                    multicastLock = null
                    Log.d("FloatDiscovery", "mdns.multicast_lock.released")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        events = eventSink
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(clipboardListener)
        Log.d("FloatClipboard", "clipboard.listener.started")
    }

    override fun onCancel(arguments: Any?) {
        clipboardManager?.removePrimaryClipChangedListener(clipboardListener)
        events = null
        Log.d("FloatClipboard", "clipboard.listener.stopped")
    }

    override fun onDestroy() {
        onCancel(null)
        multicastLock?.let { lock -> if (lock.isHeld) lock.release() }
        multicastLock = null
        super.onDestroy()
    }

    private fun sendClipboardText() {
        val manager = clipboardManager ?: return
        val clip = manager.primaryClip ?: return
        if (!manager.hasPrimaryClip() || clip.itemCount == 0) return
        val text = clip.getItemAt(0).coerceToText(this)?.toString()?.trim().orEmpty()
        if (text.isNotEmpty()) {
            Log.d("FloatClipboard", "clipboard.listener.received length=${text.length}")
            runOnUiThread { events?.success(text) }
        }
    }
}
