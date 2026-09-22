package com.nasmedia.nap_mx_flutter

import android.app.Activity
import android.app.Application
import com.nasmedia.admixerssp.ads.AdListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformViewRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

/**
 * Regression tests for the ad lifecycle defects fixed in 0.1.2. These run on the JVM
 * against the real published SDK and Flutter embedding, with only the Android
 * framework objects mocked.
 */
class NapMxFlutterPluginTest {

    private lateinit var application: Application
    private lateinit var plugin: NapMxFlutterPlugin
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    /** Records which host lifecycle callbacks a registered view actually received. */
    private class FakeView : NapMxHostLifecycle {
        val calls = mutableListOf<String>()
        override fun onHostResume() { calls += "resume" }
        override fun onHostPause() { calls += "pause" }
    }

    @Before
    fun setUp() {
        application = mock()
        binding = mock()
        whenever(binding.applicationContext).thenReturn(application)
        whenever(binding.binaryMessenger).thenReturn(mock<BinaryMessenger>())
        whenever(binding.platformViewRegistry).thenReturn(mock<PlatformViewRegistry>())
        plugin = NapMxFlutterPlugin()
    }

    @Test
    fun `host lifecycle observation is registered while attached to the engine`() {
        attach()
        verify(application).registerActivityLifecycleCallbacks(plugin.activityCallbacks)

        plugin.onDetachedFromEngine(binding)
        verify(application).unregisterActivityLifecycleCallbacks(plugin.activityCallbacks)
    }

    @Test
    fun `resume and pause reach the ad views of the attached activity`() {
        attach()
        val host = mock<Activity>()
        plugin.onAttachedToActivity(activityBinding(host))

        val view = FakeView()
        plugin.adViews += view

        plugin.activityCallbacks.onActivityResumed(host)
        plugin.activityCallbacks.onActivityPaused(host)

        assertEquals(listOf("resume", "pause"), view.calls)
    }

    @Test
    fun `another activity's lifecycle never reaches the ad views`() {
        attach()
        val host = mock<Activity>()
        val unrelated = mock<Activity>()
        plugin.onAttachedToActivity(activityBinding(host))

        val view = FakeView()
        plugin.adViews += view

        plugin.activityCallbacks.onActivityResumed(unrelated)
        plugin.activityCallbacks.onActivityPaused(unrelated)

        assertTrue(view.calls.isEmpty())
    }

    @Test
    fun `no activity is attached means no forwarding`() {
        attach()
        val view = FakeView()
        plugin.adViews += view

        plugin.activityCallbacks.onActivityResumed(mock())

        assertTrue(view.calls.isEmpty())
    }

    @Test
    fun `detaching from the engine stops tracking ad views`() {
        attach()
        plugin.adViews += FakeView()

        plugin.onDetachedFromEngine(binding)

        assertTrue(plugin.adViews.isEmpty())
    }

    /**
     * The SDK keeps a banner listener in a WeakReference, so the listener has to be a
     * field on the view. A listener scoped to the load call would be collectible and the
     * banner would silently stop reporting events.
     */
    @Test
    fun `the platform ad view holds its listener in a field`() {
        val listenerFields = NapMxPlatformAdView::class.java.declaredFields
            .filter { AdListener::class.java.isAssignableFrom(it.type) }

        assertEquals(
            "exactly one AdListener field is expected on the platform ad view",
            1,
            listenerFields.size,
        )
        assertNotNull(listenerFields.single())
    }

    private fun attach() = plugin.onAttachedToEngine(binding)

    private fun activityBinding(host: Activity): ActivityPluginBinding {
        val value = mock<ActivityPluginBinding>()
        whenever(value.activity).thenReturn(host)
        return value
    }
}
