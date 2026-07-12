package tech.router1.app

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val completedId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
        val prefs = context.getSharedPreferences("router1_updates", Context.MODE_PRIVATE)
        if (completedId <= 0 || completedId != prefs.getLong("download_id", -2)) return
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val apkUri = manager.getUriForDownloadedFile(completedId) ?: return
        prefs.edit().remove("download_id").apply()
        val installer = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(installer)
    }
}
