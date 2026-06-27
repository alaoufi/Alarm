package com.mudhakkarati.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// نرث من FlutterFragmentActivity لأن حزمة local_auth (البصمة) تتطلب ذلك.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.mudhakkarati.app/ringtone"
    private val dictationChannel = "com.mudhakkarati.app/dictation"
    private val volumeChannel = "com.mudhakkarati.app/alarm_volume"
    private val installerChannel = "com.mudhakkarati.app/installer"
    private val pickRequest = 4201
    private val speechRequest = 4711
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSpeech: MethodChannel.Result? = null

    // رفع/استعادة مستوى صوت تيّار المنبّه (STREAM_ALARM) — يعمل حتى مع الصامت.
    private var savedAlarmVolume: Int? = null
    private var volumeRamp: Runnable? = null
    private val rampHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickRingtone" -> openPicker(call.argument<String>("current"), result)
                    "ringtoneTitle" -> result.success(titleFor(call.argument<String>("uri")))
                    else -> result.notImplemented()
                }
            }

        // قناة الإملاء الصوتيّ — تفتح نافذة التعرّف الأصلية في النظام.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, dictationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(speechAvailable())
                    "recognize" -> startSpeech(call.argument<String>("locale"), result)
                    else -> result.notImplemented()
                }
            }

        // قناة رفع صوت المنبّه (تيّار STREAM_ALARM) — رفع فوري أو تدرّجيّ + استعادة.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "raise" -> {
                        val target = call.argument<Int>("targetPercent") ?: 100
                        val ramp = call.argument<Int>("rampSeconds") ?: 0
                        raiseAlarmVolume(target, ramp)
                        result.success(true)
                    }
                    "restore" -> {
                        restoreAlarmVolume()
                        result.success(true)
                    }
                    "isBatteryUnrestricted" -> result.success(isBatteryUnrestricted())
                    "requestBatteryUnrestricted" -> {
                        requestBatteryUnrestricted(); result.success(true)
                    }
                    "openAutoStart" -> { openAutoStart(); result.success(true) }
                    "openAppSettings" -> { openAppSettings(); result.success(true) }
                    else -> result.notImplemented()
                }
            }

        // قناة تثبيت تحديث APK مباشرةً (نيّة تثبيت بلا فتح ملف/منتقي).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings(); result.success(true)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "مسار غير صالح", null)
                        } else {
                            result.success(installApk(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// هل يُسمح للتطبيق بتثبيت حزم (صلاحية «تثبيت تطبيقات غير معروفة»)؟
    private fun canInstallPackages(): Boolean {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                packageManager.canRequestPackageInstalls()
            } else {
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    /// يفتح شاشة منح «تثبيت تطبيقات غير معروفة» لهذا التطبيق (مرّة واحدة).
    private fun openInstallSettings() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES
                ).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } else {
                openAppSettings()
            }
        } catch (e: Exception) {
            openAppSettings()
        }
    }

    /// يطلق مثبّت النظام مباشرةً على ملفّ APK عبر FileProvider (لا يفتح ملفًّا).
    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(
                this, "$packageName.updateprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /// يرفع صوت تيّار المنبّه إلى [targetPercent]٪ — فورًا أو بالتدرّج خلال
    /// [rampSeconds] ثانية. يحفظ المستوى الأصليّ لاستعادته لاحقًا.
    private fun raiseAlarmVolume(targetPercent: Int, rampSeconds: Int) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            if (max <= 0) return
            if (savedAlarmVolume == null) {
                savedAlarmVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            }
            val pct = targetPercent.coerceIn(0, 100)
            val target = (max * pct / 100).coerceIn(1, max)
            volumeRamp?.let { rampHandler.removeCallbacks(it) }
            volumeRamp = null
            if (rampSeconds <= 0) {
                am.setStreamVolume(AudioManager.STREAM_ALARM, target, 0)
                return
            }
            // تدرّج: نبدأ من 1 ونزيد خطوة كل فترة حتى الهدف.
            var current = 1
            am.setStreamVolume(AudioManager.STREAM_ALARM, current, 0)
            val steps = (target - current).coerceAtLeast(1)
            val interval = (rampSeconds * 1000L / steps).coerceAtLeast(150L)
            val r = object : Runnable {
                override fun run() {
                    current += 1
                    am.setStreamVolume(
                        AudioManager.STREAM_ALARM, current.coerceAtMost(target), 0)
                    if (current < target) rampHandler.postDelayed(this, interval)
                }
            }
            volumeRamp = r
            rampHandler.postDelayed(r, interval)
        } catch (e: Exception) {
            // قد تمنع بعض الأجهزة/سياسات DND تغيير الصوت — نتجاهل بأمان.
        }
    }

    /// يستعيد مستوى صوت المنبّه الأصليّ (ويُلغي أيّ تدرّج جارٍ).
    private fun restoreAlarmVolume() {
        try {
            volumeRamp?.let { rampHandler.removeCallbacks(it) }
            volumeRamp = null
            val saved = savedAlarmVolume ?: return
            savedAlarmVolume = null
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.setStreamVolume(AudioManager.STREAM_ALARM, saved, 0)
        } catch (e: Exception) {
        }
    }

    /// هل التطبيق مُستثنى من توفير البطارية؟ (مهمّ كي لا يُقتل المنبّه المجدول).
    private fun isBatteryUnrestricted(): Boolean {
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (e: Exception) {
            true // عند التعذّر لا نُزعج المستخدم
        }
    }

    /// يفتح صفحة تفاصيل التطبيق في الإعدادات (مخرج احتياطيّ موثوق).
    private fun openAppSettings() {
        try {
            val intent = Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            ).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
        }
    }

    /// يحاول فتح شاشة «التشغيل التلقائي» الخاصّة بالمُصنّع (شاومي/هواوي/أوبو/…)،
    /// وإلا يفتح صفحة إعدادات التطبيق كبديل.
    private fun openAutoStart() {
        val candidates = listOf(
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to
                "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to
                "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.iqoo.secure" to
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.vivo.permissionmanager" to
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.letv.android.letvsafe" to
                "com.letv.android.letvsafe.AutobootManageActivity",
            "com.samsung.android.lool" to
                "com.samsung.android.sm.ui.battery.BatteryActivity"
        )
        for ((pkg, cls) in candidates) {
            try {
                val intent = Intent().apply {
                    component = android.content.ComponentName(pkg, cls)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return
            } catch (e: Exception) {
                // جرّب التالي
            }
        }
        openAppSettings()
    }

    /// يطلب من المستخدم استثناء التطبيق من توفير البطارية (نافذة النظام).
    private fun requestBatteryUnrestricted() {
        try {
            val intent = Intent(
                android.provider.Settings
                    .ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
            ).apply { data = Uri.parse("package:$packageName") }
            startActivity(intent)
        } catch (e: Exception) {
            // بديل: نفتح إعدادات توفير البطارية العامّة.
            try {
                startActivity(
                    Intent(
                        android.provider.Settings
                            .ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                    )
                )
            } catch (_: Exception) {
            }
        }
    }

    // (6) فحص توفّر الخدمة: محرّك تعرّف أو Activity يستقبل ACTION_RECOGNIZE_SPEECH.
    private fun speechAvailable(): Boolean {
        return try {
            val hasRecognizer = SpeechRecognizer.isRecognitionAvailable(this)
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            val resolved = intent.resolveActivity(packageManager) != null
            hasRecognizer || resolved
        } catch (e: Exception) {
            false
        }
    }

    // (3,4) فتح نافذة الإملاء الأصلية بصيغة حرّة ولغة محدّدة.
    private fun startSpeech(locale: String?, result: MethodChannel.Result) {
        if (pendingSpeech != null) {
            result.error("busy", "الإملاء قيد التشغيل", null); return
        }
        val lang = if (locale.isNullOrEmpty()) "ar-SA" else locale
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, lang)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "🎙️")
            // إطالة مُهَل الصمت كي لا تتوقّف بعد كلمتين (جُمل أطول، توقّفات قصيرة).
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 6000)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 5000)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                5000)
        }
        try {
            pendingSpeech = result
            startActivityForResult(intent, speechRequest)
        } catch (e: ActivityNotFoundException) {
            pendingSpeech = null
            result.error("unavailable", "لا توجد خدمة إملاء", null)
        } catch (e: Exception) {
            pendingSpeech = null
            result.error("error", e.message, null)
        }
    }

    private fun openPicker(current: String?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "اختيار قيد التنفيذ", null); return
        }
        pendingResult = result
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,
                RingtoneManager.TYPE_NOTIFICATION or RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "اختر نغمة التنبيه")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            if (!current.isNullOrEmpty()) {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(current))
            }
        }
        try {
            startActivityForResult(intent, pickRequest)
        } catch (e: Exception) {
            pendingResult = null
            result.error("unavailable", "تعذّر فتح منتقي النغمات", e.message)
        }
    }

    private fun titleFor(uri: String?): String? {
        if (uri.isNullOrEmpty()) return null
        return try {
            RingtoneManager.getRingtone(this, Uri.parse(uri))?.getTitle(this)
        } catch (e: Exception) {
            null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            pickRequest -> {
                val r = pendingResult ?: return
                pendingResult = null
                if (resultCode == Activity.RESULT_OK) {
                    val picked: Uri? =
                        data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                    r.success(picked?.toString())
                } else {
                    r.success(null)
                }
            }
            speechRequest -> {
                val r = pendingSpeech ?: return
                pendingSpeech = null
                // (5) اقرأ أول نتيجة غير فارغة من EXTRA_RESULTS.
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val results =
                        data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    val text = results?.firstOrNull { it.isNotBlank() } ?: ""
                    r.success(text)
                } else {
                    r.success(null) // أُلغيت العملية
                }
            }
        }
    }
}
