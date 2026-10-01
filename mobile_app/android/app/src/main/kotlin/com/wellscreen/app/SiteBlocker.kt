package com.wellscreen.app

import android.content.Context
import org.json.JSONArray

/**
 * Decides whether a browsed domain should be blocked.
 *
 * Two sources:
 *  1. The harmful-site dataset the Flutter side already bundles
 *     (assets/site_categories/cleaned_site_categories.csv: gambling, drugs,
 *     adult, dangerous_material) - read straight from the APK's flutter_assets.
 *  2. An optional parent-defined list in SharedPreferences key
 *     flutter.blocked_domains_json (JSON array of domains).
 *
 * Subdomains match their parent ("m.example.com" -> "example.com").
 */
object SiteBlocker {
    private const val CSV_PATH = "flutter_assets/assets/site_categories/cleaned_site_categories.csv"

    @Volatile
    private var datasetDomains: Set<String>? = null

    private fun loadDataset(context: Context): Set<String> {
        datasetDomains?.let { return it }
        val result = HashSet<String>()
        try {
            context.assets.open(CSV_PATH).bufferedReader().useLines { lines ->
                lines.drop(1).forEach { line ->
                    val comma = line.indexOf(',')
                    if (comma > 0) result.add(line.substring(0, comma).trim().lowercase())
                }
            }
        } catch (_: Exception) {
            // Dataset unavailable - fall back to the parent list only.
        }
        datasetDomains = result
        return result
    }

    private fun parentDomains(context: Context): Set<String> {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString("flutter.blocked_domains_json", "[]") ?: "[]")
            (0 until arr.length()).map { arr.getString(it).trim().lowercase() }.toSet()
        } catch (_: Exception) {
            emptySet()
        }
    }

    fun isBlocked(context: Context, domain: String): Boolean {
        val d = domain.trim().lowercase()
        if (d.isEmpty()) return false
        val dataset = loadDataset(context)
        val parent = parentDomains(context)
        val labels = d.split('.')
        for (start in 0..(labels.size - 2)) {
            val candidate = labels.subList(start, labels.size).joinToString(".")
            if (dataset.contains(candidate) || parent.contains(candidate)) return true
        }
        return false
    }
}
