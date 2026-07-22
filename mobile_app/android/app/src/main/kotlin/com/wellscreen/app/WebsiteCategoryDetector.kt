package com.wellscreen.app

import java.util.Locale

data class WebsiteCategoryDetectionResult(
    val domain: String,
    val category: String,
    val isHarmful: Boolean,
    val matchedValue: String
)

class WebsiteCategoryDetector {

    fun detectFromTexts(textValues: List<String>): WebsiteCategoryDetectionResult? {
        val uniqueTexts = textValues
            .map { it.trim() }
            .filter { it.isNotBlank() && it.length <= 300 }
            .distinct()

        for (text in uniqueTexts) {
            val result = detectFromText(text)

            if (result != null) {
                return result
            }
        }

        return null
    }

    fun detectFromText(text: String?): WebsiteCategoryDetectionResult? {
        if (text.isNullOrBlank()) {
            return null
        }

        val candidate = extractUrlOrDomain(text) ?: return null
        val domain = normalizeDomain(candidate)

        if (domain.isBlank() || !domain.contains(".")) {
            return null
        }

        val category = detectCategory(domain, text)

        return WebsiteCategoryDetectionResult(
            domain = domain,
            category = category,
            isHarmful = isHarmfulCategory(category),
            matchedValue = candidate
        )
    }

    private fun extractUrlOrDomain(text: String): String? {
        val value = text.trim().lowercase(Locale.US)

        val urlRegex = Regex("""https?://[^\s]+""")
        val wwwRegex = Regex("""www\.[^\s]+""")
        val domainRegex = Regex(
            """([a-z0-9-]+\.)+(com|net|org|edu|gov|ph|io|co|me|tv|gg|app|site|online|xyz|info|biz|dev)(/[^\s]*)?"""
        )

        return urlRegex.find(value)?.value
            ?: wwwRegex.find(value)?.value
            ?: domainRegex.find(value)?.value
    }

    private fun normalizeDomain(value: String): String {
        var normalized = value.trim().lowercase(Locale.US)

        normalized = normalized
            .removePrefix("https://")
            .removePrefix("http://")
            .removePrefix("www.")

        normalized = normalized
            .substringBefore("/")
            .substringBefore("?")
            .substringBefore("#")
            .substringBefore(":")

        return normalized.trim('.', ',', ';', ':', ' ')
    }

    private fun detectCategory(domain: String, rawText: String): String {
        val source = "$domain ${rawText.lowercase(Locale.US)}"

        if (containsAny(source, adultKeywords)) {
            return CATEGORY_ADULT
        }

        if (containsAny(source, gamblingKeywords)) {
            return CATEGORY_GAMBLING
        }

        if (containsAny(source, violenceKeywords)) {
            return CATEGORY_VIOLENCE
        }

        if (containsAny(domain, videoStreamingDomains) ||
            containsAny(source, videoStreamingKeywords)
        ) {
            return CATEGORY_VIDEO_STREAMING
        }

        if (containsAny(domain, socialMediaDomains) ||
            containsAny(source, socialMediaKeywords)
        ) {
            return CATEGORY_SOCIAL_MEDIA
        }

        if (containsAny(domain, gamingDomains) ||
            containsAny(source, gamingKeywords)
        ) {
            return CATEGORY_GAMING
        }

        if (containsAny(domain, safeDomains)) {
            return CATEGORY_SAFE
        }

        return CATEGORY_UNKNOWN
    }

    private fun isHarmfulCategory(category: String): Boolean {
        return category == CATEGORY_ADULT ||
            category == CATEGORY_GAMBLING ||
            category == CATEGORY_VIOLENCE
    }

    private fun containsAny(value: String, keywords: List<String>): Boolean {
        return keywords.any { keyword -> value.contains(keyword) }
    }

    companion object {
        const val CATEGORY_ADULT = "adult"
        const val CATEGORY_GAMBLING = "gambling"
        const val CATEGORY_VIOLENCE = "violence"
        const val CATEGORY_SOCIAL_MEDIA = "social_media"
        const val CATEGORY_VIDEO_STREAMING = "video_streaming"
        const val CATEGORY_GAMING = "gaming"
        const val CATEGORY_SAFE = "safe"
        const val CATEGORY_UNKNOWN = "unknown"

        private val adultKeywords = listOf(
            "adult",
            "xxx",
            "porn",
            "explicit"
        )

        private val gamblingKeywords = listOf(
            "casino",
            "betting",
            "sportsbook",
            "poker",
            "slots",
            "lottery",
            "jackpot"
        )

        private val violenceKeywords = listOf(
            "gore",
            "violent",
            "weapon",
            "weapons",
            "shooting",
            "graphic violence"
        )

        private val socialMediaDomains = listOf(
            "facebook.com",
            "messenger.com",
            "instagram.com",
            "tiktok.com",
            "twitter.com",
            "x.com",
            "snapchat.com",
            "discord.com",
            "reddit.com"
        )

        private val socialMediaKeywords = listOf(
            "facebook",
            "messenger",
            "instagram",
            "tiktok",
            "twitter",
            "snapchat",
            "discord",
            "reddit"
        )

        private val videoStreamingDomains = listOf(
            "youtube.com",
            "youtu.be",
            "netflix.com",
            "twitch.tv",
            "vimeo.com",
            "dailymotion.com"
        )

        private val videoStreamingKeywords = listOf(
            "youtube",
            "netflix",
            "twitch",
            "vimeo",
            "dailymotion",
            "streaming"
        )

        private val gamingDomains = listOf(
            "roblox.com",
            "minecraft.net",
            "steampowered.com",
            "epicgames.com",
            "riotgames.com",
            "mobilelegends.com",
            "pubgmobile.com",
            "callofduty.com"
        )

        private val gamingKeywords = listOf(
            "roblox",
            "minecraft",
            "steam",
            "epic games",
            "riot games",
            "mobile legends",
            "pubg",
            "call of duty",
            "gaming"
        )

        private val safeDomains = listOf(
            "google.com",
            "wikipedia.org",
            "khanacademy.org",
            "deped.gov.ph",
            "gov.ph",
            "edu.ph",
            "classroom.google.com"
        )
    }
}