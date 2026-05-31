package com.example.collectio

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareSubject: String? = null
    private var shareText: String? = null
    private var shareChannel: MethodChannel? = null
    private var pendingShareDelivery = false
    private var shareDeliveredToFlutter = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShareFromIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getShareExtras" -> {
                        result.success(
                            hashMapOf(
                                "subject" to shareSubject?.trim()?.takeIf { it.isNotEmpty() },
                                "text" to shareText?.trim()?.takeIf { it.isNotEmpty() },
                            ),
                        )
                    }
                    "clearSharedUrl" -> {
                        clearShareExtras()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        captureShareFromIntent(intent)
        scheduleDeliverShareToFlutter(force = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shareDeliveredToFlutter = false
        captureShareFromIntent(intent)
        scheduleDeliverShareToFlutter(force = true)
    }

    override fun onResume() {
        super.onResume()
        captureShareFromIntent(intent)
        if (!shareText.isNullOrBlank() && !shareDeliveredToFlutter) {
            scheduleDeliverShareToFlutter(force = true)
        }
    }

    private fun captureShareFromIntent(intent: Intent?) {
        if (intent == null) return

        when (intent.action) {
            Intent.ACTION_SEND -> {
                val subject = readTextExtra(intent, Intent.EXTRA_SUBJECT)
                val text = readTextExtra(intent, Intent.EXTRA_TEXT)
                    ?: readTextExtra(intent, Intent.EXTRA_HTML_TEXT)
                    ?: intent.dataString?.takeIf { looksLikeUrl(it) }

                if (!text.isNullOrBlank() || !subject.isNullOrBlank()) {
                    shareSubject = subject
                    shareText = text ?: subject
                    shareDeliveredToFlutter = false
                    Log.d(TAG, "Captured ACTION_SEND text=$shareText subject=$shareSubject")
                }
            }

            Intent.ACTION_VIEW -> {
                val url = intent.dataString?.trim()
                if (!url.isNullOrBlank() && looksLikeUrl(url)) {
                    shareText = url
                    shareSubject = null
                    shareDeliveredToFlutter = false
                    Log.d(TAG, "Captured ACTION_VIEW url=$url")
                }
            }
        }
    }

    private fun readTextExtra(intent: Intent, key: String): String? {
        intent.getStringExtra(key)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        return intent.getCharSequenceExtra(key)?.toString()?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun looksLikeUrl(value: String): Boolean {
        return value.startsWith("http://", ignoreCase = true) ||
            value.startsWith("https://", ignoreCase = true)
    }

    private fun scheduleDeliverShareToFlutter(force: Boolean = false) {
        val text = shareText?.trim()
        if (text.isNullOrEmpty()) return
        if (shareDeliveredToFlutter && !force) return

        pendingShareDelivery = true
        deliverShareToFlutter(attemptsRemaining = 50)
    }

    private fun deliverShareToFlutter(attemptsRemaining: Int) {
        if (!pendingShareDelivery) return

        val text = shareText?.trim()
        if (text.isNullOrEmpty()) {
            pendingShareDelivery = false
            return
        }

        val channel = shareChannel
        if (channel != null) {
            channel.invokeMethod(
                "shareReceived",
                hashMapOf(
                    "text" to text,
                    "subject" to shareSubject?.trim()?.takeIf { it.isNotEmpty() },
                ),
            )
            shareDeliveredToFlutter = true
            pendingShareDelivery = false
            Log.d(TAG, "Delivered share to Flutter: $text")
            return
        }

        if (attemptsRemaining <= 0) {
            pendingShareDelivery = false
            Log.w(TAG, "Failed to deliver share — Flutter channel not ready")
            return
        }

        mainHandler.postDelayed(
            { deliverShareToFlutter(attemptsRemaining - 1) },
            200,
        )
    }

    private fun clearShareExtras() {
        shareSubject = null
        shareText = null
        pendingShareDelivery = false
        shareDeliveredToFlutter = false
    }

    companion object {
        private const val TAG = "CollectioShare"
        private const val SHARE_CHANNEL = "com.collectio.app/share_extension"
    }
}
