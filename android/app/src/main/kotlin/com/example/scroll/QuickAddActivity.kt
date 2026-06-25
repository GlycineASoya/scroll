package com.example.scroll

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.widget.EditText
import android.widget.LinearLayout
import org.json.JSONArray
import org.json.JSONObject

class QuickAddActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val context: Context = this
        val input = EditText(context).apply {
            hint = "What to Buy?"
            setSingleLine(true)
        }
        
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(60, 20, 60, 0)
            addView(input)
        }

        val dialog = AlertDialog.Builder(context)
            .setTitle("Add item")
            .setView(container)
            .setPositiveButton("Add") { _, _ ->
                val text = input.text.toString().trim()
                if (text.isNotEmpty()) {
                    saveItemToWidgetAndPending(context, text)
                }
                finishAndRemoveTask()
            }
            .setNegativeButton("Cancel") { _, _ -> finishAndRemoveTask() }
            .setOnCancelListener { finishAndRemoveTask() }
            .create()

        dialog.show()
    }

    private fun saveItemToWidgetAndPending(context: Context, itemName: String) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        
        val jsonString = prefs.getString("list_data_json", "[]")
        val updatedArray = JSONArray()
        
        updatedArray.put(JSONObject().apply {
            put("id", "pending_${System.currentTimeMillis()}")
            put("name", itemName)
            put("isBought", false)
        })
        
        try {
            val oldArray = JSONArray(jsonString)
            for (i in 0 until oldArray.length()) {
                val oldItem = oldArray.getJSONObject(i)
                if (oldItem.optString("id") != "empty") {
                    updatedArray.put(oldItem)
                }
            }
        } catch (e: Exception) { e.printStackTrace() }

        val pendingString = prefs.getString("pending_adds", "[]")
        val pendingArray = try { JSONArray(pendingString) } catch (e: Exception) { JSONArray() }
        pendingArray.put(itemName)

        prefs.edit()
            .putString("list_data_json", updatedArray.toString())
            .putString("pending_adds", pendingArray.toString())
            .apply()

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, ShoppingListWidget::class.java)
        val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
        
        appWidgetManager.notifyAppWidgetViewDataChanged(allWidgetIds, R.id.widget_list_view)
    }
}