package com.example.scroll

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONObject

class WidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return WidgetDataProvider(this.applicationContext)
    }
}

class WidgetDataProvider(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var itemsList = ArrayList<JSONObject>()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val jsonString = prefs.getString("list_data_json", "[]")
        
        itemsList.clear()
        try {
            val jsonArray = JSONArray(jsonString)
            for (i in 0 until jsonArray.length()) {
                itemsList.add(jsonArray.getJSONObject(i))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() { itemsList.clear() }
    override fun getCount(): Int = itemsList.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_list_item)

        // Out-of-Bounds Protection
        if (position >= itemsList.size) return views
        
        val item = itemsList[position]
        
        val id = item.optString("id", "")
        val name = item.optString("name", "Error")
        val isBought = item.optBoolean("isBought", false)

        // Item appreance depends on isBought flag
        views.setTextViewText(R.id.widget_item_text, name)
        
        if (id == "empty") {
            // If the list is empty, hide checkbox
            views.setViewVisibility(R.id.widget_item_checkbox, android.view.View.GONE)
            views.setTextColor(R.id.widget_item_text, Color.parseColor("#757575"))
            views.setInt(R.id.widget_item_text, "setPaintFlags", Paint.ANTI_ALIAS_FLAG)
        } else {
            views.setViewVisibility(R.id.widget_item_checkbox, android.view.View.VISIBLE)
            
            if (isBought) {
                views.setImageViewResource(R.id.widget_item_checkbox, com.example.scroll.R.drawable.widget_cb_checked)
                views.setTextColor(R.id.widget_item_text, Color.parseColor("#9E9E9E"))
                views.setInt(R.id.widget_item_text, "setPaintFlags", Paint.STRIKE_THRU_TEXT_FLAG or Paint.ANTI_ALIAS_FLAG)
            } else {
                views.setImageViewResource(R.id.widget_item_checkbox, com.example.scroll.R.drawable.widget_cb_unchecked)
                views.setTextColor(R.id.widget_item_text, Color.parseColor("#000000"))
                views.setInt(R.id.widget_item_text, "setPaintFlags", Paint.ANTI_ALIAS_FLAG)
            }

            // Attach the click handler (only if this is a real product, not a placeholder)
            val fillInIntent = Intent().apply {
                data = Uri.parse("scrollapp://toggle?id=$id")
            }
            views.setOnClickFillInIntent(R.id.widget_item_row, fillInIntent)
        }

        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}