package com.example.collectio

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareSubject: String? = null
    private var shareText: String? = null
    private var shareChannel: MethodChannel? = null
    private var pendingShareDelivery = false
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
        scheduleDeliverShareToFlutter()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareFromIntent(intent)
        scheduleDeliverShareToFlutter()
    }

    override fun onResume() {
        super.onResume()
        captureShareFromIntent(intent)
        scheduleDeliverShareToFlutter()
    }

    private fun captureShareFromIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        shareSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        shareText = intent.getStringExtra(Intent.EXTRA_TEXT)
    }

    private fun scheduleDeliverShareToFlutter() {
        val text = shareText?.trim()
        if (text.isNullOrEmpty()) return
        pendingShareDelivery = true
        deliverShareToFlutter(attemptsRemaining = 15)
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
            pendingShareDelivery = false
            return
        }

        if (attemptsRemaining <= 0) {
            pendingShareDelivery = false
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
    }

    companion object {
        private const val SHARE_CHANNEL = "com.collectio.app/share_extension"
    }
}
