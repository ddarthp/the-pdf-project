package com.softmindai.the_pdf_project

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives PDFs other apps open or share into The PDF Project.
 *
 * Android hands over a `content://` URI, which is a permission grant rather
 * than a file: it is scoped to this intent and is no use to the viewer, which
 * opens documents by path. So every incoming document is copied into the app's
 * own cache first, and Dart is only ever told about a real readable file.
 *
 * Needs no permission of its own. The sender is granting read access to the
 * one document it chose, exactly as the system document picker does.
 */
class MainActivity : FlutterActivity() {

    /**
     * Documents that arrived before Dart was listening.
     *
     * Holds the launch intent until Dart asks for it, and catches the rare
     * case of a document landing between two engine attachments.
     */
    private val waiting = mutableListOf<Map<String, String>>()

    private var events: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        waiting += documentsFrom(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Taken, not read: the launch document opens once, and a
                    // later restart must not reopen it over the reader's work.
                    "takeInitialDocuments" -> {
                        result.success(waiting.toList())
                        waiting.clear()
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        events = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        events = null
                    }
                }
            )
    }

    /**
     * A second document while the app is already up.
     *
     * The activity is `singleTop`, so opening another PDF reuses this
     * instance rather than starting a new one — without this the second
     * document would be dropped in silence, because there is no new launch
     * for Dart to read.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep the activity's own intent in step, so a later restart sees the
        // document that is actually open.
        setIntent(intent)

        val documents = documentsFrom(intent)
        if (documents.isEmpty()) return

        val sink = events
        // No listener yet (the engine is still starting): hold the document
        // for the next takeInitialDocuments rather than losing it.
        if (sink == null) waiting += documents else sink.success(documents)
    }

    /** Pulls the PDFs out of an intent, whichever way they were sent. */
    private fun documentsFrom(intent: Intent?): List<Map<String, String>> {
        if (intent == null) return emptyList()
        val uris = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(streamExtra(intent))
            Intent.ACTION_SEND_MULTIPLE -> streamExtras(intent)
            else -> emptyList()
        }
        return uris.mapNotNull(::copyIntoCache)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamExtras(intent: Intent): List<Uri> =
        intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty().filterNotNull()

    /**
     * Copies an incoming document into the app's cache and describes it.
     *
     * Returns null when the document cannot be read — a revoked grant, a
     * provider that has gone away — so one unreadable document does not cost
     * the reader the others shared with it.
     */
    private fun copyIntoCache(uri: Uri): Map<String, String>? {
        return try {
            val name = displayNameOf(uri)
            val folder = File(cacheDir, INCOMING_FOLDER).apply { mkdirs() }
            // Prefixed with the arrival time so opening two documents of the
            // same name in one session does not have one overwrite the other.
            val target = File(folder, "${System.currentTimeMillis()}-$name")
            contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                target.outputStream().use(input::copyTo)
            }
            mapOf("path" to target.absolutePath, "name" to name)
        } catch (error: Exception) {
            Log.w(TAG, "Could not read an incoming document", error)
            null
        }
    }

    /**
     * The name the sender shows for the document, so the app bar reads the
     * same as the file manager the reader came from.
     */
    private fun displayNameOf(uri: Uri): String {
        val provided = try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
                }
        } catch (error: Exception) {
            Log.w(TAG, "Could not read the name of an incoming document", error)
            null
        }

        val readable = (provided ?: uri.lastPathSegment ?: DEFAULT_NAME)
            .substringAfterLast('/')
            .replace(Regex("[^A-Za-z0-9._ -]"), "_")
            .trim()
            .ifEmpty { DEFAULT_NAME }
        return if (readable.endsWith(".pdf", ignoreCase = true)) readable else "$readable.pdf"
    }

    private companion object {
        const val TAG = "IncomingDocuments"
        const val INCOMING_FOLDER = "incoming"
        const val DEFAULT_NAME = "document.pdf"
        const val METHOD_CHANNEL = "com.softmindai.the_pdf_project/incoming_documents"
        const val EVENT_CHANNEL = "com.softmindai.the_pdf_project/incoming_documents/events"
    }
}
