package com.wellscreen.app

/** Pure threshold rule, shared by foreground and background warning checks. */
internal object TenMinuteWarningPolicy {
    private const val THRESHOLD_MS = 10L * 60_000L

    fun qualifies(limitMinutes: Int, remainingMilliseconds: Long): Boolean =
        limitMinutes in 1..1440 &&
            remainingMilliseconds > 0L &&
            remainingMilliseconds <= THRESHOLD_MS
}
