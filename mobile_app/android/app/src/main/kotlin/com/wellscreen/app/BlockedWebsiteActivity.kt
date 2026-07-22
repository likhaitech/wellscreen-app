package com.wellscreen.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

class BlockedWebsiteActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContentView(R.layout.activity_blocked_website)

        val domain = intent.getStringExtra(EXTRA_DOMAIN) ?: "Restricted website"
        val category = intent.getStringExtra(EXTRA_CATEGORY) ?: "restricted"

        findViewById<TextView>(R.id.blockedWebsiteDomainText).text = domain
        findViewById<TextView>(R.id.blockedWebsiteCategoryText).text =
            "Category: ${category.replace("_", " ")}"

        findViewById<Button>(R.id.blockedWebsiteLeaveButton).setOnClickListener {
            leaveRestrictedWebsite()
        }
    }

    override fun onBackPressed() {
        leaveRestrictedWebsite()
    }

    private fun leaveRestrictedWebsite() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        startActivity(homeIntent)
        finish()
    }

    companion object {
        const val EXTRA_DOMAIN = "extra_domain"
        const val EXTRA_CATEGORY = "extra_category"
    }
}
