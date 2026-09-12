package com.lovekush.lovekush_pos

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val WHATSAPP_CHANNEL = "com.lovekush.pos/whatsapp"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WHATSAPP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sharePdfToWhatsApp" -> {
                    val bytes = call.argument<ByteArray>("pdfBytes")
                    val filename = call.argument<String>("filename") ?: "bill.pdf"
                    val phone = call.argument<String>("phone")
                    val caption = call.argument<String>("caption")

                    if (bytes == null || bytes.isEmpty()) {
                        result.error("EMPTY_DATA", "PDF bytes are empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        // Save PDF bytes to application cache directory
                        val cacheDir = applicationContext.cacheDir
                        val pdfFile = File(cacheDir, filename)
                        pdfFile.writeBytes(bytes)

                        val contentUri: Uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            pdfFile
                        )

                        val pm = packageManager
                        val isWaInstalled = try {
                            pm.getPackageInfo("com.whatsapp", 0)
                            true
                        } catch (e: Exception) {
                            false
                        }
                        val isWaBusinessInstalled = try {
                            pm.getPackageInfo("com.whatsapp.w4b", 0)
                            true
                        } catch (e: Exception) {
                            false
                        }

                        val targetPackage = when {
                            isWaInstalled -> "com.whatsapp"
                            isWaBusinessInstalled -> "com.whatsapp.w4b"
                            else -> null
                        }

                        if (targetPackage != null) {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/pdf"
                                putExtra(Intent.EXTRA_STREAM, contentUri)
                                if (!caption.isNullOrEmpty()) {
                                    putExtra(Intent.EXTRA_TEXT, caption)
                                }
                                setPackage(targetPackage)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }

                            if (!phone.isNullOrEmpty()) {
                                val cleanDigits = phone.filter { it.isDigit() }
                                if (cleanDigits.isNotEmpty()) {
                                    val fullPhone = if (cleanDigits.length == 10) "91$cleanDigits" else cleanDigits
                                    intent.putExtra("jid", "$fullPhone@s.whatsapp.net")
                                }
                            }

                            startActivity(intent)
                            result.success(true)
                        } else {
                            // WhatsApp not installed
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("SHARE_ERROR", e.localizedMessage, null)
                    }
                }
                "isWhatsAppInstalled" -> {
                    val pm = packageManager
                    val isWaInstalled = try {
                        pm.getPackageInfo("com.whatsapp", 0)
                        true
                    } catch (e: Exception) {
                        false
                    }
                    val isWaBusinessInstalled = try {
                        pm.getPackageInfo("com.whatsapp.w4b", 0)
                        true
                    } catch (e: Exception) {
                        false
                    }
                    result.success(isWaInstalled || isWaBusinessInstalled)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
