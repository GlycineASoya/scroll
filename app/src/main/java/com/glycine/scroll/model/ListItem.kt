package com.glycine.scroll.model

import java.util.UUID

data class ListItem(
    val id: String = UUID.randomUUID().toString(),
    val text: String,
    val isChecked: Boolean = false
)