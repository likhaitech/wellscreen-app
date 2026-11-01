
package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TenMinuteWarningPolicyTest {

    @Test
    fun doesNotWarnBeforeTenMinutes() {
        assertFalse(TenMinuteWarningPolicy.qualifies(40, 600_001L))
    }

    @Test
    fun warnsAtExactlyTenMinutes() {
        assertTrue(TenMinuteWarningPolicy.qualifies(40, 600_000L))
    }

    @Test
    fun warnsAtNineMinutes() {
        assertTrue(TenMinuteWarningPolicy.qualifies(40, 540_000L))
    }

    @Test
    fun warnsWithLessThanOneMinuteLeft() {
        assertTrue(TenMinuteWarningPolicy.qualifies(40, 20_000L))
    }

    @Test
    fun doesNotWarnAtZeroRemaining() {
        assertFalse(TenMinuteWarningPolicy.qualifies(40, 0L))
    }

    @Test
    fun doesNotWarnWithNegativeRemaining() {
        assertFalse(TenMinuteWarningPolicy.qualifies(40, -100L))
    }

    @Test
    fun doesNotWarnForInvalidLimit() {
        assertFalse(TenMinuteWarningPolicy.qualifies(1500, 600_000L))
    }

    @Test
    fun warnsForTenMinuteAllowance() {
        assertTrue(TenMinuteWarningPolicy.qualifies(10, 600_000L))
    }
}
