package com.shoutsocial.share_handler

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.util.Date

private const val TAG = "FileDirectory"

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

                    if ("primary".equals(type, ignoreCase = true)) {
                        val path = context.getExternalFilesDir(null)?.toString() + "/" + split[1]
                        if (File(path).canRead()) return path
                    }
                    val path = getDataColumn(context, uri, null, null)
                    if (path != null) return path
                } else if (isDownloadsDocument(uri)) {
                    try {
                        val id = DocumentsContract.getDocumentId(uri)
                        val contentUri = ContentUris.withAppendedId(
                            Uri.parse("content://downloads/public_downloads"), java.lang.Long.valueOf(id)
                        )
                        val path = getDataColumn(context, contentUri, null, null)
                        if (path != null) return path
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
                        else -> null
                    }

                    if (contentUri != null && split.size > 1) {
                        val selection = "_id=?"
                        val selectionArgs = arrayOf(split[1])
                        val path = getDataColumn(context, contentUri, selection, selectionArgs)
                        if (path != null) return path
                    }
                }
            }

            // 3. General Content URI (e.g. content://media/external/video/media/12345 or other apps)
            if ("content".equals(uri.scheme, ignoreCase = true)) {
                // Priority 1: Check if the underlying real file can be resolved directly via MediaStore DATA column
                val directPath = tryGetDirectFilePath(context, uri)
                if (directPath != null) {
                    val file = File(directPath)
                    if (file.exists() && file.canRead()) {
                        Log.i(TAG, "Direct file path resolved without copy: $directPath")
                        return directPath
                    }
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
     * Attempts to query the real file path (_data column) directly without copying.
     */
    private fun tryGetDirectFilePath(context: Context, uri: Uri): String? {
        val projection = arrayOf(MediaStore.MediaColumns.DATA)
        return try {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (columnIndex != -1) {
                        cursor.getString(columnIndex)
                    } else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Copy content stream to cache directory if direct access is not possible.
     */
    private fun copyContentUriToCache(context: Context, uri: Uri): String? {
        var fileName: String? = null
        try {
            val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx != -1) {
                        fileName = cursor.getString(nameIdx)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not determine file name from URI", e)
        }

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

        val targetFile = File(context.cacheDir, fileName)

        // If target file already exists and has the same length, reuse it
        try {
            context.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                val uriLength = pfd.statSize
                if (targetFile.exists() && uriLength > 0 && targetFile.length() == uriLength) {
                    Log.i(TAG, "Reusing existing cached file: ${targetFile.absolutePath}")
                    return targetFile.absolutePath
                }
            }
        } catch (_: Exception) {
            // Ignore descriptor check errors
        }

        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(targetFile).use { fileOut ->
                    val buffer = ByteArray(64 * 1024) // 64KB buffer for efficient transfer
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        fileOut.write(buffer, 0, bytesRead)
                    }
                }
            }
            return targetFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy content URI to cache: $uri", e)
            return null
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
