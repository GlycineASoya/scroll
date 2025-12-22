package com.glycine.scroll.model

import java.util.UUID

data class SharedList(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val items: List<ListItem> = emptyList()
)