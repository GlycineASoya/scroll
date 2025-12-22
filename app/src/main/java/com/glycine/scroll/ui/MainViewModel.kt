package com.glycine.scroll.ui

import androidx.lifecycle.ViewModel
import com.glycine.scroll.model.ListItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

class MainViewModel : ViewModel() {

    private val _items = MutableStateFlow(
        listOf(
            ListItem(text = "Milk"),
            ListItem(text = "Bread"),
            ListItem(text = "Eggs")
        )
    )
    val items: StateFlow<List<ListItem>> = _items

    fun addItem(text: String) {
        if (text.isBlank()) return

        _items.update { current ->
            listOf(ListItem(text = text)) + current
        }
    }

    fun toggleItem(itemId: String, checked: Boolean) {
        _items.update { current ->
            current.map {
                if (it.id == itemId) it.copy(isChecked = checked)
                else it
            }
        }
    }

    fun deleteItem(itemId: String) {
        _items.update { current ->
            current.filterNot { it.id == itemId }
        }
    }
}