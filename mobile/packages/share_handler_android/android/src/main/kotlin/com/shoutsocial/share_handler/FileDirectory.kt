package com.shoutsocial.share_handler

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.util.Date

private const val TAG = "FileDirectory"
private const val SHARE_CACHE_DIR = "share_intent_cache"
private const val CACHE_MAX_AGE_MS = 24L * 60L * 60L * 1000L // 24 hours

object FileDirectory {

    /**
     * Get a file path from a Uri. This will get the path for Storage Access
     * Framework Documents, as well as the _data field for the MediaStore and
     * other file-based ContentProviders.
     */
    fun getAbsolutePath(context: Context, uri: Uri): String? {
        try {
            // 1. Direct file URI
            if ("file".equals(uri.scheme, ignoreCase = true)) {
                val path = uri.path
                if (path != null && File(path).canRead()) {
                    return path
                }
            }

            // 2. Storage Access Framework (DocumentsContract)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && DocumentsContract.isDocumentUri(context, uri)) {
                if (isExternalStorageDocument(uri)) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
                    val type = split[0]

                    if ("primary".equals(type, ignoreCase = true) && split.size > 1) {
                        val primaryPath = "${Environment.getExternalStorageDirectory()}/${split[1]}"
                        if (File(primaryPath).canRead()) return primaryPath
                        val appExtPath = "${context.getExternalFilesDir(null)}/${split[1]}"
                        if (File(appExtPath).canRead()) return appExtPath
                    }
                    val path = getDataColumn(context, uri, null, null)
                    if (path != null) return path
                } else if (isDownloadsDocument(uri)) {
                    try {
                        val id = DocumentsContract.getDocumentId(uri)
                        if (id.startsWith("raw:")) {
                            val rawPath = id.removePrefix("raw:")
                            if (File(rawPath).canRead()) return rawPath
                        }
                        val numericId = id.substringAfter(':', id).toLongOrNull()
                        if (numericId != null) {
                            val contentUri = ContentUris.withAppendedId(
                                Uri.parse("content://downloads/public_downloads"), numericId
                            )
                            val path = getDataColumn(context, contentUri, null, null)
                            if (path != null) return path
                        }
                    } catch (_: Exception) {
                        val path = getDataColumn(context, uri, null, null)
                        if (path != null) return path
                    }
                } else if (isMediaDocument(uri)) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
                    val type = split[0]

                    val contentUri = when (type) {
                        "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                        else -> MediaStore.Files.getContentUri("external")
                    }

                    if (contentUri != null && split.size > 1) {
                        val selection = "_id=?"
                        val selectionArgs = arrayOf(split[1])
                        val path = getDataColumn(context, contentUri, selection, selectionArgs)
                        if (path != null) return path
                    }
                }
            }

            // 3. General Content URI (e.g. MediaStore, Photo Picker, Google Photos, Gallery, File Managers)
            if ("content".equals(uri.scheme, ignoreCase = true)) {
                // Priority 1: Resolve underlying real file path without copying
                val directPath = tryGetDirectFilePath(context, uri)
                if (directPath != null) {
                    Log.i(TAG, "Direct file path resolved without copy: $directPath")
                    return directPath
                }

                // Priority 2: Fallback to copying content stream into app cache directory
                return copyContentUriToCache(context, uri)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resolve absolute path for URI: $uri", e)
        }

        return uri.path
    }

    /**
     * Attempts to resolve the real local file path without copying:
     * 1) Direct _data column on the URI
     * 2) Embedded content://media/... URI (e.g. Google Photos provider) or MediaStore numeric ID (e.g. Photo Picker)
     * 3) MediaStore lookup by (DISPLAY_NAME, SIZE)
     */
    private fun tryGetDirectFilePath(context: Context, uri: Uri): String? {
        // Step 1: Query _data directly on the incoming URI
        getDataColumn(context, uri, null, null)?.let { return it }

        val mimeType = try {
            context.contentResolver.getType(uri)
        } catch (_: Exception) {
            null
        }
        val (displayName, expectedSize) = queryDisplayNameAndSize(context, uri)

        // Step 2a: Check if the URI wraps an embedded content://media/... URI (e.g. Google Photos)
        try {
            val decodedUriString = Uri.decode(uri.toString())
            val mediaPrefixIdx = decodedUriString.indexOf("content://media/")
            if (mediaPrefixIdx > 0) {
                val tail = decodedUriString.substring(mediaPrefixIdx)
                val regex = Regex("""content://media/[a-zA-Z0-9_]+/(?:images|video|audio|file)/media/\d+""")
                val match = regex.find(tail)
                if (match != null) {
                    val embeddedUri = Uri.parse(match.value)
                    getDataColumn(context, embeddedUri, null, null)?.let { path ->
                        if (expectedSize <= 0L || File(path).length() == expectedSize) {
                            return path
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }

        // Step 2b: Check if the URI has a numeric MediaStore ID (e.g. Android Photo Picker content://media/picker/.../media/<id>)
        val candidateId = uri.lastPathSegment?.substringAfterLast(':')?.toLongOrNull()
        if (candidateId != null && candidateId > 0) {
            val candidateTables = getCandidateMediaTables(mimeType)
            for (tableUri in candidateTables) {
                val path = getDataColumn(
                    context,
                    tableUri,
                    "${MediaStore.MediaColumns._ID}=?",
                    arrayOf(candidateId.toString())
                )
                if (path != null) {
                    val file = File(path)
                    if (expectedSize > 0L && file.length() == expectedSize) {
                        return path
                    } else if (expectedSize <= 0L && "media".equals(uri.authority, ignoreCase = true)) {
                        return path
                    }
                }
            }
        }

        // Step 3: Lookup in MediaStore by (DISPLAY_NAME, SIZE)
        if (!displayName.isNullOrBlank() && expectedSize > 0L) {
            val candidateTables = getCandidateMediaTables(mimeType)
            for (tableUri in candidateTables) {
                try {
                    context.contentResolver.query(
                        tableUri,
                        arrayOf(MediaStore.MediaColumns.DATA),
                        "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.SIZE}=?",
                        arrayOf(displayName, expectedSize.toString()),
                        "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
                    )?.use { cursor ->
                        while (cursor.moveToNext()) {
                            val colIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                            if (colIdx != -1) {
                                val path = cursor.getString(colIdx)
                                if (!path.isNullOrBlank()) {
                                    val file = File(path)
                                    if (file.exists() && file.canRead() && file.length() == expectedSize) {
                                        return path
                                    }
                                }
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }
        }

        return null
    }

    private fun getCandidateMediaTables(mimeType: String?): List<Uri> {
        return when {
            mimeType?.startsWith("video/") == true -> listOf(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Files.getContentUri("external")
            )
            mimeType?.startsWith("image/") == true -> listOf(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Files.getContentUri("external")
            )
            mimeType?.startsWith("audio/") == true -> listOf(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Files.getContentUri("external")
            )
            else -> listOf(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Files.getContentUri("external")
            )
        }
    }

    private fun queryDisplayNameAndSize(context: Context, uri: Uri): Pair<String?, Long> {
        var displayName: String? = null
        var size = -1L
        try {
            val projection = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx != -1 && !cursor.isNull(nameIdx)) {
                        displayName = cursor.getString(nameIdx)
                    }
                    if (sizeIdx != -1 && !cursor.isNull(sizeIdx)) {
                        size = cursor.getLong(sizeIdx)
                    }
                }
            }
        } catch (_: Exception) {
        }
        if (size <= 0L) {
            try {
                context.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                    if (pfd.statSize > 0L) {
                        size = pfd.statSize
                    }
                }
            } catch (_: Exception) {
            }
        }
        return displayName to size
    }

    /**
     * Copy content stream to cache directory if direct access is not possible.
     */
    private fun copyContentUriToCache(context: Context, uri: Uri): String? {
        val (queriedName, uriLength) = queryDisplayNameAndSize(context, uri)
        var fileName = queriedName?.let { File(it).name }

        val mimeType = context.contentResolver.getType(uri)
        if (fileName.isNullOrBlank()) {
            val prefix = when {
                mimeType?.startsWith("image") == true -> "IMG"
                mimeType?.startsWith("video") == true -> "VID"
                else -> "FILE"
            }
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "bin"
            fileName = "${prefix}_${Date().time}.$ext"
        }

        val cacheSubDir = File(context.cacheDir, SHARE_CACHE_DIR)
        if (!cacheSubDir.exists()) {
            cacheSubDir.mkdirs()
        } else {
            pruneOldCacheFiles(cacheSubDir)
        }

        val targetFile = File(cacheSubDir, fileName)

        // If target file already exists and has the same length, reuse it
        if (targetFile.exists() && uriLength > 0L && targetFile.length() == uriLength) {
            Log.i(TAG, "Reusing existing cached file: ${targetFile.absolutePath}")
            return targetFile.absolutePath
        }

        val tempFile = File(cacheSubDir, "$fileName.tmp_${System.nanoTime()}")
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { fileOut ->
                    val buffer = ByteArray(256 * 1024) // 256KB buffer for high-throughput transfer
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        fileOut.write(buffer, 0, bytesRead)
                    }
                }
            } ?: return null

            if (targetFile.exists()) {
                targetFile.delete()
            }
            return if (tempFile.renameTo(targetFile)) {
                targetFile.absolutePath
            } else {
                tempFile.absolutePath
            }
        } catch (e: Exception) {
            tempFile.delete()
            Log.e(TAG, "Failed to copy content URI to cache: $uri", e)
            return null
        }
    }

    private fun pruneOldCacheFiles(dir: File) {
        try {
            val cutoff = System.currentTimeMillis() - CACHE_MAX_AGE_MS
            dir.listFiles()?.forEach { file ->
                if (file.isFile && file.lastModified() < cutoff) {
                    file.delete()
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun getDataColumn(
        context: Context,
        uri: Uri,
        selection: String?,
        selectionArgs: Array<String>?
    ): String? {
        val projection = arrayOf(MediaStore.MediaColumns.DATA)
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, null)
            if (cursor != null && cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (columnIndex != -1) {
                    val path = cursor.getString(columnIndex)
                    if (!path.isNullOrBlank() && File(path).canRead()) {
                        return path
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to query getDataColumn for uri: $uri", e)
        } finally {
            cursor?.close()
        }

        return null
    }

    private fun isExternalStorageDocument(uri: Uri): Boolean {
        return "com.android.externalstorage.documents" == uri.authority
    }

    private fun isDownloadsDocument(uri: Uri): Boolean {
        return "com.android.providers.downloads.documents" == uri.authority
    }

    private fun isMediaDocument(uri: Uri): Boolean {
        return "com.android.providers.media.documents" == uri.authority
    }
}
