package com.nasmedia.nap_mx_flutter

import android.content.Context
import android.widget.FrameLayout
import com.nasmedia.admixerssp.ads.*
import com.nasmedia.admixerssp.common.core.AdNetworkType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mockConstruction
import org.mockito.kotlin.*

class NapMxAdViewTest {
    @Test
    fun `all inline formats ignore callbacks from cancelled loads and dispose once`() {
        for (format in listOf("banner", "native", "inlineVideo")) {
            mockConstruction(FrameLayout::class.java).use {
                mockConstruction(AMMBannerView::class.java).use { banners ->
                    mockConstruction(AMMNativeAdView::class.java).use { natives ->
                        mockConstruction(AMMVideoView::class.java).use { videos ->
                            val events = mutableListOf<Map<String, Any?>>()
                            val view = NapMxPlatformAdView(
                                mock<Context>(), 7, mapOf("format" to format, "adUnitId" to "123"),
                                mock<BinaryMessenger>(), { events.add(it) }, { null }, mutableListOf(), { emptyMap() },
                            )
                            fun listener(): AdListener {
                                val capture = argumentCaptor<AdListener>()
                                when (format) {
                                    "banner" -> verify(banners.constructed().last()).setAdViewListener(capture.capture())
                                    "native" -> verify(natives.constructed().last()).setAdViewListener(capture.capture())
                                    else -> verify(videos.constructed().last()).setAdViewListener(capture.capture())
                                }
                                return capture.firstValue
                            }
                            view.onMethodCall(MethodCall("load", null), mock<MethodChannel.Result>())
                            val old = listener()
                            view.onMethodCall(MethodCall("cancel", null), mock<MethodChannel.Result>())
                            view.onMethodCall(MethodCall("load", null), mock<MethodChannel.Result>())
                            val current = listener()
                            val before = events.size
                            old.onReceivedAd("AdMixer", Any())
                            old.onFailedToReceiveAd(-1, "late failure")
                            old.onAdDisplayed()
                            old.onAdClicked()
                            assertEquals(before, events.size)
                            val duplicate = mock<MethodChannel.Result>()
                            view.onMethodCall(MethodCall("load", null), duplicate)
                            verify(duplicate).error(eq("already_loading"), any(), isNull())
                            current.onReceivedAd(AdNetworkType.ADMIXER, Any())
                            current.onAdDisplayed()
                            current.onAdClicked()
                            current.onAdCompleted()
                            current.onAdSkipped()
                            current.onAdClosed()
                            assertEquals(listOf("loaded", "shown", "clicked", "completed", "skipped", "closed"),
                                events.drop(before).map { it["type"] })
                            assertTrue(events.all { it["viewId"] == 7 && it["format"] == format && it["adUnitId"] == "123" })
                            view.dispose()
                            view.dispose()
                            current.onAdDisplayed()
                            assertEquals(1, events.count { it["type"] == "disposed" })
                            assertEquals("disposed", events.last()["type"])
                        }
                    }
                }
            }
        }
    }
}
