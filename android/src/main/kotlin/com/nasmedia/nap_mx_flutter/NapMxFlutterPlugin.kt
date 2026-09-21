@file:Suppress("OVERRIDE_DEPRECATION")

package com.nasmedia.nap_mx_flutter

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import com.nasmedia.admixerssp.ads.*
import com.nasmedia.admixerssp.common.AdMixer
import com.nasmedia.admixerssp.common.AdMixerLog
import com.nasmedia.admixerssp.common.Constants
import com.nasmedia.admixerssp.common.core.AdNetworkType
import com.nasmedia.admixerssp.common.nativeads.AdChoicesPosition
import com.nasmedia.admixerssp.common.nativeads.NativeAdViewBinder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Flutter bridge for the published nap mx Android SDK. */
class NapMxFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, ActivityAware {

    companion object { private const val PLUGIN_VERSION = "0.1.1" }

    private lateinit var applicationContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var messenger: BinaryMessenger
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var initialized = false
    private var configurationFingerprint: String? = null
    private var mediation = emptyMap<String, Map<String, String>>()
    private val requests = ConcurrentHashMap<String, FullscreenRequest>()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        messenger = binding.binaryMessenger
        methods = MethodChannel(messenger, "nap_mx_flutter/methods")
        events = EventChannel(messenger, "nap_mx_flutter/events")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "nap_mx_flutter/ad_view",
            NapMxAdViewFactory(messenger, ::emit, ::activity) { mediation },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        requests.values.forEach { it.dispose(false) }
        requests.clear()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivity() { activity = null }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
    override fun onCancel(arguments: Any?) { eventSink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "getSdkInfo" -> result.success(mapOf(
                "platform" to "android",
                "pluginVersion" to PLUGIN_VERSION,
                "sdkVersion" to Constants.VERSION_NAME,
                "adapterVersions" to AdMixer.getInstance().adapterVersionString,
            ))
            "loadFullscreen" -> loadFullscreen(call, result)
            "showFullscreen" -> showFullscreen(call, result)
            "disposeFullscreen" -> disposeFullscreen(call, result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error(
            "invalid_configuration", "Configuration map is required.", null,
        )
        val mediaKey = (args["mediaKey"] as? String)?.trim().orEmpty()
        val units = (args["adUnitIds"] as? Map<*, *>)?.values
            ?.mapNotNull { (it as? String)?.trim()?.takeIf(String::isNotEmpty) }.orEmpty()
        if (mediaKey.isEmpty() || units.isEmpty()) return result.error(
            "invalid_configuration", "mediaKey and at least one ad unit ID are required.", null,
        )
        val fingerprint = "$mediaKey|${units.sorted().joinToString(",")}" 
        if (initialized) {
            if (configurationFingerprint == fingerprint) result.success(null)
            else result.error("already_initialized", "nap mx was initialized with other values.", null)
            return
        }

        val privacy = args["privacy"] as? Map<*, *> ?: emptyMap<Any, Any>()
        if ((privacy["underAgeOfConsent"] as? String) !in setOf(null, "unspecified")) {
            return result.error(
                "unsupported_privacy",
                "The Android SDK has no under-age-of-consent setter; configure the installed network SDKs in the host app.",
                null,
            )
        }
        mediation = (args["mediation"] as? Map<*, *>)?.mapNotNull { (key, value) ->
            val adapter = key as? String ?: return@mapNotNull null
            val config = (value as? Map<*, *>)?.entries?.mapNotNull { (configKey, configValue) ->
                val name = configKey as? String ?: return@mapNotNull null
                val content = configValue as? String ?: return@mapNotNull null
                name to content
            }?.toMap() ?: return@mapNotNull null
            adapter to config
        }?.toMap().orEmpty()
        when (privacy["gdprConsent"] as? String) {
            "granted" -> AdMixer.setGdprConsent(true)
            "denied" -> AdMixer.setGdprConsent(false)
        }
        (privacy["usPrivacyString"] as? String)?.takeIf(String::isNotBlank)
            ?.let(AdMixer::setUsPrivacy)
        when (privacy["usSaleConsent"] as? String) {
            "granted" -> AdMixer.setCcpaDoNotSell(false)
            "denied" -> AdMixer.setCcpaDoNotSell(true)
        }
        when (privacy["childDirected"] as? String) {
            "granted" -> AdMixer.setTagForChildDirectedTreatment(
                AdMixer.AX_TAG_FOR_CHILD_DIRECTED_TREATMENT_TRUE,
            )
            "denied" -> AdMixer.setTagForChildDirectedTreatment(
                AdMixer.AX_TAG_FOR_CHILD_DIRECTED_TREATMENT_FALSE,
            )
            else -> AdMixer.setTagForChildDirectedTreatment(
                AdMixer.AX_TAG_FOR_CHILD_DIRECTED_TREATMENT_UNSPECIFIED,
            )
        }
        AdMixer.setTestMode(args["testMode"] as? Boolean ?: false)
        AdMixer.setTestDeviceIds((args["testDeviceIds"] as? List<*>)?.filterIsInstance<String>().orEmpty())
        AdMixerLog.setLogLevel(when (args["logLevel"] as? String) {
            "debug" -> AdMixerLog.LogLevel.VERBOSE
            "info" -> AdMixerLog.LogLevel.INFO
            "none" -> AdMixerLog.LogLevel.NONE
            else -> AdMixerLog.LogLevel.ERROR
        })
        AdMixer.getInstance().initialize(applicationContext, mediaKey, ArrayList(units))
        initialized = true
        configurationFingerprint = fingerprint
        result.success(null)
        emit(baseEvent("initializationSucceeded"))
    }

    private fun loadFullscreen(call: MethodCall, result: MethodChannel.Result) {
        if (!initialized) return result.error("not_initialized", "Call initialize first.", null)
        val requestId = call.argument<String>("requestId")?.trim().orEmpty()
        val format = call.argument<String>("format")?.trim().orEmpty()
        val adUnitId = call.argument<String>("adUnitId")?.trim().orEmpty()
        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: 30_000L)
            .coerceIn(1_000L, 120_000L)
        val customParams = call.argument<Map<String, String>>("customParams") ?: emptyMap()
        if (requestId.isEmpty() || adUnitId.isEmpty()) return result.error(
            "invalid_request", "requestId and adUnitId are required.", null,
        )
        if (format !in setOf("interstitial", "interstitialVideo", "rewarded")) {
            return result.error("unsupported", "Unsupported full-screen format: $format", null)
        }
        if (requests.containsKey(requestId)) return result.error(
            "duplicate_request", "requestId is already active.", null,
        )
        val request = FullscreenRequest(requestId, format, adUnitId, result, timeoutMs, customParams)
        requests[requestId] = request
        emit(request.event("loadStarted"))
        request.load()
    }

    private fun showFullscreen(call: MethodCall, result: MethodChannel.Result) {
        val requestId = call.argument<String>("requestId")?.trim().orEmpty()
        val request = requests[requestId]
            ?: return result.error("not_loaded", "No active request for $requestId.", null)
        request.show(result)
    }

    private fun disposeFullscreen(call: MethodCall, result: MethodChannel.Result) {
        val requestId = call.argument<String>("requestId")?.trim().orEmpty()
        requests.remove(requestId)?.dispose(true)
        result.success(null)
    }

    private inner class FullscreenRequest(
        val id: String,
        val format: String,
        val adUnitId: String,
        private var loadResult: MethodChannel.Result?,
        timeoutMs: Long,
        private val customParams: Map<String, String>,
    ) {
        private val startedAt = System.currentTimeMillis()
        private val finished = AtomicBoolean(false)
        private val rewardSent = AtomicBoolean(false)
        private var showResult: MethodChannel.Result? = null
        private var network: String? = null
        private var ad: Any? = null
        private var state = "loading"
        private val timeout = Runnable {
            if (state == "loading" && !finished.get()) {
                failLoad("timeout", "Plugin load timeout.", AdMixer.AX_ERR_TIMEOUT)
            }
        }

        init { mainHandler.postDelayed(timeout, timeoutMs) }

        fun load() {
            val builder = adInfoBuilder(adUnitId)
            if (customParams.isNotEmpty()) builder.setCustomParams(customParams)
            val info = builder.build()
            when (format) {
                "interstitial" -> AMMInterstitial.loadAd(
                    applicationContext, info, object : AMMInterstitialLoadCallback() {
                        override fun onSuccessLoadInterstitial(type: AdNetworkType, value: AMMInterstitial) =
                            loaded(type.adapterName, value)
                        @Suppress("DEPRECATION")
                        override fun onSuccessLoadInterstitial(name: String, value: AMMInterstitial) = loaded(name, value)
                        override fun onFailLoadInterstitial(code: Int, message: String?) =
                            failLoad("load_failed", message ?: "Ad load failed.", code)
                    },
                )
                "interstitialVideo" -> AMMVideoInterstitial.loadAd(
                    applicationContext, info, object : AMMVideoInterstitialLoadCallback() {
                        override fun onSuccessLoadVideoInterstitial(type: AdNetworkType, value: AMMVideoInterstitial) =
                            loaded(type.adapterName, value)
                        @Suppress("DEPRECATION")
                        override fun onSuccessLoadVideoInterstitial(name: String, value: AMMVideoInterstitial) = loaded(name, value)
                        override fun onFailLoadVideoInterstitial(code: Int, message: String?) =
                            failLoad("load_failed", message ?: "Video ad load failed.", code)
                    },
                )
                "rewarded" -> AMMRewardVideo.loadAd(
                    applicationContext, info, object : AMMRewardVideoLoadCallback() {
                        override fun onSuccessLoadReward(type: AdNetworkType, value: AMMRewardVideo) =
                            loaded(type.adapterName, value)
                        @Suppress("DEPRECATION")
                        override fun onSuccessLoadReward(name: String, value: AMMRewardVideo) = loaded(name, value)
                        override fun onFailLoadReward(code: Int, message: String?) =
                            failLoad("load_failed", message ?: "Reward ad load failed.", code)
                    },
                )
            }
        }

        private fun loaded(adapterName: String, loadedAd: Any) {
            if (finished.get() || state != "loading") {
                stopAd(loadedAd)
                return
            }
            mainHandler.removeCallbacks(timeout)
            state = "loaded"
            network = adapterName
            ad = loadedAd
            installListener(loadedAd)
            loadResult?.success(null)
            loadResult = null
            emit(event("loaded"))
        }

        fun show(result: MethodChannel.Result) {
            if (state != "loaded") return result.error("not_loaded", "Ad is in state $state.", null)
            val host = activity
            if (host == null || host.isFinishing || host.isDestroyed) {
                return result.error("no_activity", "No active Activity is attached.", null)
            }
            state = "showing"
            showResult = result
            when (val value = ad) {
                is AMMRewardVideo -> value.show(host, object : OnUserEarnedRewardListener {
                    override fun onUserEarnedReward() = emitReward(null)
                    override fun onUserEarnedReward(info: RewardInfo) = emitReward(info.transactionId)
                })
                is AMMInterstitial -> value.show(host)
                is AMMVideoInterstitial -> value.show(host)
                else -> {
                    state = "failed"
                    result.error("not_loaded", "Loaded ad instance is unavailable.", null)
                    showResult = null
                }
            }
        }

        private fun installListener(loadedAd: Any) {
            val listener = object : AdListener() {
                override fun onAdDisplayed() {
                    if (finished.get()) return
                    showResult?.success(null)
                    showResult = null
                    emit(event("shown"))
                }
                override fun onAdClicked() { if (!finished.get()) emit(event("clicked")) }
                override fun onAdCompleted() { if (!finished.get()) emit(event("completed")) }
                override fun onAdSkipped() { if (!finished.get()) emit(event("skipped")) }
                override fun onAdClosed() {
                    if (finished.get()) return
                    showResult?.error("show_failed", "Ad closed before a show confirmation.", null)
                    showResult = null
                    emit(event("closed"))
                    dispose(false)
                    requests.remove(id, this@FullscreenRequest)
                }
                override fun onAdShowFailed(
                    adView: Any?, adapterName: String, errorCode: Int, errorMsg: String?,
                ) {
                    if (finished.get()) return
                    state = "failed"
                    showResult?.error("show_failed", errorMsg ?: "Ad show failed.", errorCode)
                    showResult = null
                    emit(errorEvent("showFailed", "show_failed", errorMsg, errorCode))
                }
            }
            when (loadedAd) {
                is AMMInterstitial -> loadedAd.setAdListener(listener)
                is AMMVideoInterstitial -> loadedAd.setAdListener(listener)
                is AMMRewardVideo -> loadedAd.setAdListener(listener)
            }
        }

        private fun emitReward(transactionId: String?) {
            if (!rewardSent.compareAndSet(false, true) || finished.get()) return
            emit(event("rewarded").toMutableMap().apply {
                put("reward", mapOf("transactionId" to (transactionId ?: "")))
            })
        }

        private fun failLoad(code: String, message: String, nativeCode: Int) {
            if (finished.getAndSet(true)) return
            mainHandler.removeCallbacks(timeout)
            state = "failed"
            stopAd(ad)
            ad = null
            loadResult?.error(code, message, nativeCode)
            loadResult = null
            emit(errorEvent("loadFailed", code, message, nativeCode))
            requests.remove(id, this)
        }

        fun dispose(notify: Boolean) {
            if (!finished.getAndSet(true)) {
                mainHandler.removeCallbacks(timeout)
                loadResult?.error("cancelled", "Ad request was disposed.", null)
                loadResult = null
                showResult?.error("cancelled", "Ad request was disposed.", null)
                showResult = null
                stopAd(ad)
                ad = null
            }
            state = "disposed"
            if (notify) emit(event("disposed"))
        }

        fun event(type: String): Map<String, Any?> = baseEvent(type).toMutableMap().apply {
            put("requestId", id); put("format", format); put("adUnitId", adUnitId)
            put("network", network); put("elapsedMs", (System.currentTimeMillis() - startedAt).toInt())
        }
        private fun errorEvent(type: String, code: String, message: String?, nativeCode: Int) =
            event(type).toMutableMap().apply { put("error", errorMap(code, message, nativeCode)) }
    }

    private fun stopAd(value: Any?) { when (value) {
        is AMMInterstitial -> value.stop()
        is AMMVideoInterstitial -> value.stop()
        is AMMRewardVideo -> value.stop()
    } }
    private fun adInfoBuilder(adUnitId: String): AdInfo.Builder =
        AdInfo.Builder(adUnitId).also { builder ->
            mediation.forEach { (adapter, config) -> builder.setAdapterConfig(adapter, config) }
        }
    private fun baseEvent(type: String): Map<String, Any?> = mapOf(
        "type" to type, "timestampMs" to System.currentTimeMillis(),
    )
    private fun errorMap(code: String, message: String?, nativeCode: Int): Map<String, Any?> = mapOf(
        "code" to code, "message" to (message ?: code), "nativeCode" to nativeCode,
        "isNoFill" to (nativeCode == AdMixer.AX_ERR_NO_ADS),
        "isTimeout" to (nativeCode == AdMixer.AX_ERR_TIMEOUT),
    )
    private fun emit(value: Map<String, Any?>) { mainHandler.post { eventSink?.success(value) } }
}

private class NapMxAdViewFactory(
    private val messenger: BinaryMessenger,
    private val emit: (Map<String, Any?>) -> Unit,
    private val activityProvider: () -> Activity?,
    private val mediationProvider: () -> Map<String, Map<String, String>>,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = NapMxPlatformAdView(
        context, viewId, (args as? Map<*, *>) ?: emptyMap<Any, Any>(), messenger, emit,
        activityProvider, mediationProvider,
    )
}

private class NapMxPlatformAdView(
    context: Context,
    private val viewId: Int,
    args: Map<*, *>,
    messenger: BinaryMessenger,
    private val emit: (Map<String, Any?>) -> Unit,
    private val activityProvider: () -> Activity?,
    private val mediationProvider: () -> Map<String, Map<String, String>>,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val format = args["format"] as? String ?: ""
    private val adUnitId = args["adUnitId"] as? String ?: ""
    private val muted = args["muted"] as? Boolean ?: true
    private val container = FrameLayout(context)
    private val channel = MethodChannel(messenger, "nap_mx_flutter/view/$viewId")
    private var adView: View? = null
    private var disposed = false
    private var loading = false
    private var startedAt = 0L

    init {
        channel.setMethodCallHandler(this)
        if (args["autoLoad"] as? Boolean == true) load()
    }
    override fun getView(): View = container
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) { when (call.method) {
        "load" -> if (disposed) result.error("disposed", "Ad view is disposed.", null)
            else if (loading) result.error("already_loading", "Ad view is already loading.", null)
            else { load(); result.success(null) }
        "cancel", "dispose" -> { release(call.method == "dispose"); result.success(null) }
        else -> result.notImplemented()
    } }

    private fun load() {
        if (disposed || loading) return
        if (adUnitId.isBlank()) { emitError("invalid_ad_unit", "adUnitId must not be empty.", null); return }
        loading = true; startedAt = System.currentTimeMillis(); emitEvent("loadStarted")
        val hostContext = activityProvider() ?: container.context
        val infoBuilder = AdInfo.Builder(adUnitId).setMute(muted)
        mediationProvider().forEach { (adapter, config) ->
            infoBuilder.setAdapterConfig(adapter, config)
        }
        val info = infoBuilder.build()
        val listener = object : AdListener() {
            override fun onReceivedAd(type: AdNetworkType, view: Any) {
                loading = false; emitEvent("loaded", type.adapterName)
            }
            @Suppress("DEPRECATION")
            override fun onReceivedAd(name: String, view: Any) { loading = false; emitEvent("loaded", name) }
            override fun onFailedToReceiveAd(code: Int, message: String?) {
                loading = false; emitError("load_failed", message ?: "Ad load failed.", code)
            }
            override fun onAdDisplayed() = emitEvent("shown")
            override fun onAdClicked() = emitEvent("clicked")
            override fun onAdClosed() = emitEvent("closed")
            override fun onAdCompleted() = emitEvent("completed")
            override fun onAdSkipped() = emitEvent("skipped")
        }
        val created: View = when (format) {
            "banner" -> AMMBannerView(hostContext).apply { setAdInfo(info); setAdViewListener(listener) }
            "native" -> AMMNativeAdView(hostContext).apply {
                setAdInfo(info)
                setViewBinder(NativeAdViewBinder.Builder(R.layout.nap_mx_native_ad)
                    .setIconImageId(R.id.nap_mx_iv_icon).setTitleId(R.id.nap_mx_tv_title)
                    .setAdvertiserId(R.id.nap_mx_tv_adv).setDescriptionId(R.id.nap_mx_tv_desc)
                    .setMainViewId(R.id.nap_mx_iv_main).setCtaId(R.id.nap_mx_btn_cta)
                    .setAdChoicesPosition(AdChoicesPosition.RIGHT_TOP).setAddGAMAdAttribute(false).build())
                setAdViewListener(listener)
            }
            "inlineVideo" -> AMMVideoView(hostContext).apply { setAdInfo(info); setAdViewListener(listener) }
            else -> { loading = false; emitError("unsupported", "Unsupported view format: $format", null); return }
        }
        stopCurrent(); adView = created; container.removeAllViews()
        container.addView(created, FrameLayout.LayoutParams(-1, -1))
        when (created) {
            is AMMBannerView -> created.loadAd()
            is AMMNativeAdView -> created.loadAd()
            is AMMVideoView -> created.loadAd()
        }
    }

    private fun stopCurrent() {
        when (val value = adView) {
            is AMMBannerView -> value.stop()
            is AMMNativeAdView -> value.stop()
            is AMMVideoView -> value.stop()
        }
        adView = null; container.removeAllViews()
    }
    private fun release(final: Boolean) {
        loading = false; stopCurrent()
        if (final) { disposed = true; channel.setMethodCallHandler(null); emitEvent("disposed") }
        else emitEvent("cancelled")
    }
    override fun dispose() = release(true)
    private fun emitEvent(type: String, network: String? = null) {
        if (disposed && type != "disposed") return
        emit(mapOf(
            "type" to type, "timestampMs" to System.currentTimeMillis(), "viewId" to viewId,
            "format" to format, "adUnitId" to adUnitId, "network" to network,
            "elapsedMs" to if (startedAt == 0L) null else (System.currentTimeMillis() - startedAt).toInt(),
        ))
    }
    private fun emitError(code: String, message: String, nativeCode: Int?) {
        if (disposed) return
        emit(mapOf(
            "type" to "loadFailed", "timestampMs" to System.currentTimeMillis(), "viewId" to viewId,
            "format" to format, "adUnitId" to adUnitId,
            "elapsedMs" to if (startedAt == 0L) null else (System.currentTimeMillis() - startedAt).toInt(),
            "error" to mapOf("code" to code, "message" to message, "nativeCode" to nativeCode,
                "isNoFill" to (nativeCode == AdMixer.AX_ERR_NO_ADS),
                "isTimeout" to (nativeCode == AdMixer.AX_ERR_TIMEOUT)),
        ))
    }
}
