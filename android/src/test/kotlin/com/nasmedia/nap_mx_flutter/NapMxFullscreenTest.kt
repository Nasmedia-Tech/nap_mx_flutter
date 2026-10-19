package com.nasmedia.nap_mx_flutter

import android.app.Activity
import android.app.Application
import android.os.Handler
import com.nasmedia.admixerssp.ads.*
import com.nasmedia.admixerssp.common.AdMixer
import com.nasmedia.admixerssp.common.AdMixerLog
import com.nasmedia.admixerssp.common.core.AdNetworkType
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.PlatformViewRegistry
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mockConstruction
import org.mockito.Mockito.mockStatic
import org.mockito.kotlin.*

class NapMxFullscreenTest {
    @Test
    fun `all full screen formats complete futures and forward native events`() {
        mockConstruction(Handler::class.java) { handler, _ ->
            whenever(handler.post(any())).thenAnswer { it.getArgument<Runnable>(0).run(); true }
        }.use {
            mockStatic(AdMixer::class.java).use { sdkStatic ->
                mockStatic(AdMixerLog::class.java).use {
                    val sdk = mock<AdMixer>()
                    sdkStatic.`when`<AdMixer> { AdMixer.getInstance() }.thenReturn(sdk)
                    var loadCallback: Any? = null
                    mockStatic(AMMInterstitial::class.java) { invocation ->
                        loadCallback = invocation.getArgument<Any>(2); null
                    }.use {
                        mockStatic(AMMVideoInterstitial::class.java) { invocation ->
                            loadCallback = invocation.getArgument<Any>(2); null
                        }.use {
                            mockStatic(AMMRewardVideo::class.java) { invocation ->
                                loadCallback = invocation.getArgument<Any>(2); null
                            }.use {
                                for ((format, showFails) in listOf("interstitial", "interstitialVideo", "rewarded").flatMap { format ->
                                    listOf(format to false, format to true)
                                }) {
                                    val plugin = NapMxFlutterPlugin()
                                    val binding = mock<FlutterPlugin.FlutterPluginBinding>()
                                    whenever(binding.applicationContext).thenReturn(mock<Application>())
                                    whenever(binding.binaryMessenger).thenReturn(mock<BinaryMessenger>())
                                    whenever(binding.platformViewRegistry).thenReturn(mock<PlatformViewRegistry>())
                                    plugin.onAttachedToEngine(binding)
                                    val host = mock<Activity>()
                                    val activityBinding = mock<ActivityPluginBinding>()
                                    whenever(activityBinding.activity).thenReturn(host)
                                    plugin.onAttachedToActivity(activityBinding)
                                    val events = mutableListOf<Map<*, *>>()
                                    val sink = mock<EventChannel.EventSink>()
                                    doAnswer { events += it.getArgument<Map<*, *>>(0); null }.whenever(sink).success(any())
                                    plugin.onListen(null, sink)
                                    plugin.onMethodCall(MethodCall("initialize", mapOf(
                                        "mediaKey" to "123", "additionalAdUnitIds" to listOf("456"),
                                    )), mock())
                                    val failedLoad = mock<MethodChannel.Result>()
                                    plugin.onMethodCall(MethodCall("loadFullscreen", mapOf(
                                        "requestId" to "failed", "format" to format, "adUnitId" to "456",
                                    )), failedLoad)
                                    when (val callback = loadCallback) {
                                        is AMMInterstitialLoadCallback -> callback.onFailLoadInterstitial(AdMixer.AX_ERR_NO_ADS, "No ads")
                                        is AMMVideoInterstitialLoadCallback -> callback.onFailLoadVideoInterstitial(AdMixer.AX_ERR_NO_ADS, "No ads")
                                        is AMMRewardVideoLoadCallback -> callback.onFailLoadReward(AdMixer.AX_ERR_NO_ADS, "No ads")
                                    }
                                    verify(failedLoad).error("load_failed", "No ads", AdMixer.AX_ERR_NO_ADS)
                                    assertEquals(true, (events.last()["error"] as Map<*, *>)["isNoFill"])
                                    val load = mock<MethodChannel.Result>()
                                    plugin.onMethodCall(MethodCall("loadFullscreen", mapOf(
                                        "requestId" to "request", "format" to format, "adUnitId" to "456",
                                    )), load)
                                    val capture = argumentCaptor<AdListener>()
                                    val rewardAd = mock<AMMRewardVideo>()
                                    when (format) {
                                        "interstitial" -> {
                                            val ad = mock<AMMInterstitial>()
                                            (loadCallback as AMMInterstitialLoadCallback).onSuccessLoadInterstitial(AdNetworkType.ADMIXER, ad)
                                            verify(ad).setAdListener(capture.capture())
                                            // Duplicate success for the same instance must not stop the live ad.
                                            (loadCallback as AMMInterstitialLoadCallback).onSuccessLoadInterstitial("AdMixer", ad)
                                            verify(ad, never()).stop()
                                        }
                                        "interstitialVideo" -> {
                                            val ad = mock<AMMVideoInterstitial>()
                                            (loadCallback as AMMVideoInterstitialLoadCallback).onSuccessLoadVideoInterstitial(AdNetworkType.ADMIXER, ad)
                                            verify(ad).setAdListener(capture.capture())
                                        }
                                        else -> {
                                            (loadCallback as AMMRewardVideoLoadCallback).onSuccessLoadReward(AdNetworkType.ADMIXER, rewardAd)
                                            verify(rewardAd).setAdListener(capture.capture())
                                        }
                                    }
                                    verify(load).success(null)
                                    val show = mock<MethodChannel.Result>()
                                    plugin.onMethodCall(MethodCall("showFullscreen", mapOf("requestId" to "request")), show)
                                    verify(show, never()).success(anyOrNull())
                                    val listener = capture.firstValue
                                    if (showFails) {
                                        listener.onAdShowFailed(null, AdNetworkType.ADMIXER, AdMixer.AX_ERR_NO_ADS, "Show failed")
                                        verify(show).error("show_failed", "Show failed", AdMixer.AX_ERR_NO_ADS)
                                        assertEquals("showFailed", events.last()["type"])
                                        plugin.onDetachedFromEngine(binding)
                                        continue
                                    }
                                    listener.onAdDisplayed()
                                    verify(show).success(null)
                                    listener.onAdClicked()
                                    listener.onAdCompleted()
                                    listener.onAdSkipped()
                                    listener.onAdClosed()
                                    if (format == "rewarded") {
                                        val rewardListener = argumentCaptor<OnUserEarnedRewardListener>()
                                        verify(rewardAd).show(eq(host), rewardListener.capture())
                                        val info = mock<RewardInfo>()
                                        whenever(info.transactionId).thenReturn("tx-late")
                                        rewardListener.firstValue.onUserEarnedReward(info)
                                        rewardListener.firstValue.onUserEarnedReward()
                                        assertEquals(1, events.count { it["type"] == "rewarded" })
                                        assertEquals(mapOf("transactionId" to "tx-late"), events.last()["reward"])
                                    }
                                    assertEquals(listOf("loadStarted", "loaded", "shown", "clicked", "completed", "skipped", "closed"),
                                        events.filter { it["requestId"] == "request" && it["type"] != "rewarded" }.map { it["type"] })
                                    plugin.onMethodCall(MethodCall("disposeFullscreen", mapOf("requestId" to "request")), mock())
                                    val count = events.size
                                    listener.onAdDisplayed()
                                    assertEquals(count, events.size)
                                    plugin.onDetachedFromEngine(binding)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
