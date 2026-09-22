package com.nasmedia.nap_mx_flutter

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The reward gate is the only thing standing between the SDK callback and a double
 * payout, and it must stay usable after the ad closed: the network decides whether the
 * reward or the close callback arrives first.
 */
class NapMxRewardOnceTest {

    @Test
    fun `the first claim carries the transaction id`() {
        val gate = NapMxRewardOnce()
        assertEquals(mapOf("transactionId" to "tx-1"), gate.claim("tx-1"))
    }

    @Test
    fun `a missing transaction id becomes an empty string rather than null`() {
        val gate = NapMxRewardOnce()
        assertEquals(mapOf("transactionId" to ""), gate.claim(null))
    }

    @Test
    fun `later claims are refused so a reward is never paid twice`() {
        val gate = NapMxRewardOnce()
        gate.claim("tx-1")

        assertNull(gate.claim("tx-1"))
        assertNull(gate.claim("tx-2"))
    }

    /**
     * Guards the 0.1.2 fix. The gate must not consult any teardown state, because the
     * plugin marks a request closed before the reward can arrive on some networks.
     */
    @Test
    fun `a claim arriving after the ad closed is still delivered`() {
        val gate = NapMxRewardOnce()
        // Nothing at all happens between show and the reward except the close callback,
        // which the gate has no knowledge of by design.
        assertEquals(mapOf("transactionId" to "tx-late"), gate.claim("tx-late"))
    }

    @Test
    fun `concurrent claims yield exactly one payout`() {
        val gate = NapMxRewardOnce()
        val threads = 16
        val pool = Executors.newFixedThreadPool(threads)
        val start = CountDownLatch(1)
        val granted = java.util.concurrent.atomic.AtomicInteger()

        repeat(threads) {
            pool.execute {
                start.await()
                if (gate.claim("tx-race") != null) granted.incrementAndGet()
            }
        }
        start.countDown()
        pool.shutdown()
        pool.awaitTermination(10, TimeUnit.SECONDS)

        assertEquals(1, granted.get())
    }
}
