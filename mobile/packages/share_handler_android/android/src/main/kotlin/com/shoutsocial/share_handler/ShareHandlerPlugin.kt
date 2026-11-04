package com.shoutsocial.share_handler

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap

import androidx.annotation.NonNull
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private const val TAG = "ShareHandlerPlugin"
private const val kEventsChannel = "com.shoutsocial.share_handler/sharedMediaStream"

/** ShareHandlerPlugin */
class ShareHandlerPlugin : FlutterPlugin, Messages.ShareHandlerApi, EventChannel.StreamHandler, ActivityAware,
  PluginRegistry.NewIntentListener {
  @Volatile
  private var initialMedia: Messages.SharedMedia? = null
  @Volatile
  private var initialMediaJob: Deferred<Messages.SharedMedia?>? = null
  @Volatile
  private var pendingStreamMedia: Messages.SharedMedia? = null
  private var eventChannel: EventChannel? = null
  private var eventSink: EventChannel.EventSink? = null

  private var binding: ActivityPluginBinding? = null
  private lateinit var applicationContext: Context
  private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = flutterPluginBinding.applicationContext

    val messenger = flutterPluginBinding.binaryMessenger
    Messages.ShareHandlerApi.setup(messenger, this)

    eventChannel = EventChannel(messenger, kEventsChannel)
    eventChannel?.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    Messages.ShareHandlerApi.setup(binding.binaryMessenger, null)
    pluginScope.cancel()
  }

  override fun getInitialSharedMedia(result: Messages.Result<Messages.SharedMedia>?) {
    val job = initialMediaJob
    if (job != null) {
      pluginScope.launch {
        val media = try {
          job.await()
        } catch (e: Exception) {
          Log.e(TAG, "Error awaiting initial shared media", e)
          null
        }
        withContext(Dispatchers.Main) {
          result?.success(media)
        }
      }
    } else {
      result?.success(initialMedia)
    }
  }

  override fun recordSentMessage(media: Messages.SharedMedia) {
    val packageName = applicationContext.packageName
    val intent = Intent(applicationContext, Class.forName("$packageName.MainActivity")).apply {
      action = Intent.ACTION_SEND
      putExtra("conversationIdentifier", media.conversationIdentifier)
    }
    val shortcutTarget = "$packageName.dynamic_share_target"
    val shortcutBuilder = ShortcutInfoCompat.Builder(applicationContext, media.conversationIdentifier ?: "")
      .setShortLabel(media.speakableGroupName ?: "Unknown")
      .setIsConversation()
      .setCategories(setOf(shortcutTarget))
      .setIntent(intent)
      .setLongLived(true)

    val personBuilder = Person.Builder()
      .setKey(media.conversationIdentifier)
      .setName(media.speakableGroupName)

    media.imageFilePath?.let {
      val bitmap = BitmapFactory.decodeFile(it)
      val icon = IconCompat.createWithAdaptiveBitmap(bitmap)
      shortcutBuilder.setIcon(icon)
      personBuilder.setIcon(icon)
    }

    val person = personBuilder.build()
    shortcutBuilder.setPerson(person)

    val shortcut = shortcutBuilder.build()

    ShortcutManagerCompat.addDynamicShortcuts(applicationContext, listOf(shortcut))
  }

  override fun resetInitialSharedMedia() {
    initialMedia = null
    initialMediaJob = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    val pending = pendingStreamMedia
    if (pending != null && events != null) {
      pendingStreamMedia = null
      events.success(pending.toMap())
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onNewIntent(intent: Intent): Boolean {
    handleIntent(intent, false)
    return false
  }

  // ActivityAware
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addOnNewIntentListener(this)
    handleIntent(binding.activity.intent, true)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    binding?.removeOnNewIntentListener(this)
    binding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivity() {
    binding?.removeOnNewIntentListener(this)
    binding = null
  }

  private fun handleIntent(intent: Intent?, initial: Boolean) {
    if (intent == null) return
    val action = intent.action
    if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
      return
    }

    // Snapshot intent payload and mark intent consumed so config changes do not re-trigger
    val singleUri = if (action == Intent.ACTION_SEND) {
      intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
    } else null
    val multipleUris = if (action == Intent.ACTION_SEND_MULTIPLE) {
      intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
    } else null
    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
    val conversationIdentifier = intent.getStringExtra("android.intent.extra.shortcut.ID")
      ?: intent.getStringExtra("conversationIdentifier")

    intent.action = null
    intent.removeExtra(Intent.EXTRA_STREAM)
    intent.removeExtra(Intent.EXTRA_TEXT)

    val deferred = pluginScope.async {
      try {
        val attachments = when (action) {
          Intent.ACTION_SEND -> singleUri?.let { uri -> attachmentForUri(uri)?.let { listOf(it) } }
          Intent.ACTION_SEND_MULTIPLE -> multipleUris?.mapNotNull { uri -> attachmentForUri(uri) }?.takeIf { it.isNotEmpty() }
          else -> null
        }

        if (attachments != null || text != null || conversationIdentifier != null) {
          val mediaBuilder = Messages.SharedMedia.Builder()
          attachments?.let { mediaBuilder.setAttachments(it) }
          text?.let { mediaBuilder.setContent(it) }
          conversationIdentifier?.let { mediaBuilder.setConversationIdentifier(it) }
          val media = mediaBuilder.build()

          if (initial) {
            initialMedia = media
          } else {
            withContext(Dispatchers.Main) {
              val sink = eventSink
              if (sink != null) {
                sink.success(media.toMap())
              } else {
                pendingStreamMedia = media
              }
            }
          }
          media
        } else {
          null
        }
      } catch (e: Exception) {
        Log.e(TAG, "Error processing share intent", e)
        null
      }
    }

    if (initial) {
      initialMediaJob = deferred
    }
  }

  private fun attachmentForUri(uri: Uri): Messages.SharedAttachment? {
    val contentResolver = applicationContext.contentResolver
    val mimeType = contentResolver.getType(uri)
    val path = FileDirectory.getAbsolutePath(applicationContext, uri) ?: return null

    val file = File(path)
    val type = getAttachmentType(mimeType)

    return Messages.SharedAttachment.Builder()
      .setPath(file.absolutePath)
      .setType(type)
      .build()
  }

  private fun getAttachmentType(mimeType: String?): Messages.SharedAttachmentType {
    return when {
      mimeType?.startsWith("image") == true -> Messages.SharedAttachmentType.image
      mimeType?.startsWith("video") == true -> Messages.SharedAttachmentType.video
      mimeType?.startsWith("audio") == true -> Messages.SharedAttachmentType.audio
      else -> Messages.SharedAttachmentType.file
    }
  }
}
