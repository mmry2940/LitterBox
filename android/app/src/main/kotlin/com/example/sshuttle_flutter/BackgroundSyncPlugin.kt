package lit.terssh.box

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.TimeUnit

class BackgroundSyncPlugin: FlutterPlugin, MethodCallHandler {
    companion object {
        private const val CHANNEL = "com.example.litterbox/background_sync"
        private const val NOTIFICATION_CHANNEL_ID = "background_sync"
        private const val WORK_TAG = "background_sync_work"
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        
        createNotificationChannel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startBackgroundTask" -> {
                startBackgroundTask(result)
            }
            "stopBackgroundTask" -> {
                stopBackgroundTask(result)
            }
            "isBackgroundTaskRunning" -> {
                result.success(isBackgroundTaskRunning())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startBackgroundTask(result: Result) {
        try {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()

            val workRequest = PeriodicWorkRequestBuilder<BackgroundSyncWorker>(
                15, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .addTag(WORK_TAG)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "background_sync",
                ExistingPeriodicWorkPolicy.REPLACE,
                workRequest
            )
            
            result.success(true)
        } catch (e: Exception) {
            result.error("BACKGROUND_TASK_ERROR", "Failed to start background task: ${e.message}", null)
        }
    }

    private fun stopBackgroundTask(result: Result) {
        try {
            WorkManager.getInstance(context).cancelAllWorkByTag(WORK_TAG)
            result.success(true)
        } catch (e: Exception) {
            result.error("BACKGROUND_TASK_ERROR", "Failed to stop background task: ${e.message}", null)
        }
    }

    private fun isBackgroundTaskRunning(): Boolean {
        val workInfos = WorkManager.getInstance(context)
            .getWorkInfosByTag(WORK_TAG)
            .get()
        return workInfos.any { it.state == WorkInfo.State.RUNNING || it.state == WorkInfo.State.ENQUEUED }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Background Sync"
            val descriptionText = "Manages background connection synchronization"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            
            val notificationManager: NotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

class BackgroundSyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            // Perform background sync operations here
            // This would typically involve:
            // 1. Checking connection health
            // 2. Syncing device data
            // 3. Updating cached information
            
            showNotification("Background sync completed")
            Result.success()
        } catch (e: Exception) {
            showNotification("Background sync failed: ${e.message}")
            Result.retry()
        }
    }

    private fun showNotification(message: String) {
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val notification = NotificationCompat.Builder(applicationContext, "background_sync")
            .setContentTitle("LitterBox Sync")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }
}