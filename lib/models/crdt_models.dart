class LwwRecord<T> {
  final T value;
  final int timestamp;

  LwwRecord({required this.value, required this.timestamp});

  Map<String, dynamic> toJson() => {'value': value, 'timestamp': timestamp};

  factory LwwRecord.fromJson(Map<String, dynamic> json) {
    return LwwRecord<T>(
      value: json['value'] as T,
      timestamp: json['timestamp'] as int,
    );
  }
}

class CrdtShoppingItem {
  final String id;
  LwwRecord<String> name;
  LwwRecord<bool> isBought;
  LwwRecord<bool> isDeleted;

  CrdtShoppingItem({
    required this.id,
    required this.name,
    required this.isBought,
    required this.isDeleted,
  });

  // New item creation
  factory CrdtShoppingItem.create(String id, String name) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return CrdtShoppingItem(
      id: id,
      name: LwwRecord(value: name, timestamp: now),
      isBought: LwwRecord(value: false, timestamp: now),
      isDeleted: LwwRecord(value: false, timestamp: now),
    );
  }

  // --------- MERGE -----------
  CrdtShoppingItem mergeWith(CrdtShoppingItem other) {
    return CrdtShoppingItem(
      id: id,
      // wins the one which was changed later
      name: name.timestamp > other.name.timestamp ? name : other.name,
      // wins the one which was changed later
      isBought: isBought.timestamp > other.isBought.timestamp
          ? isBought
          : other.isBought,
      // wins the one which was changed later
      isDeleted: isDeleted.timestamp > other.isDeleted.timestamp
          ? isDeleted
          : other.isDeleted,
    );
  }

  // saving to gdrive
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.toJson(),
    'isBought': isBought.toJson(),
    'isDeleted': isDeleted.toJson(),
  };

  factory CrdtShoppingItem.fromJson(Map<String, dynamic> json) {
    return CrdtShoppingItem(
      id: json['id'] as String,
      name: LwwRecord.fromJson(json['name']),
      isBought: LwwRecord.fromJson(json['isBought']),
      isDeleted: LwwRecord.fromJson(json['isDeleted']),
    );
  }
}

class CrdtShoppingList {
  Map<String, CrdtShoppingItem> items = {};

  CrdtShoppingList();

  void putItem(CrdtShoppingItem item) {
    items[item.id] = item;
  }

  List<CrdtShoppingItem> get visibleItems {
    return items.values.where((item) => !item.isDeleted.value).toList();
  }

  // --- Syncing ---
  void merge(CrdtShoppingList remoteList) {
    remoteList.items.forEach((remoteId, remoteItem) {
      if (items.containsKey(remoteId)) {
        // if the item is in the list for both users, resolve conflict on field level
        items[remoteId] = items[remoteId]!.mergeWith(remoteItem);
      } else {
        // the new item from the shared file - adding it
        items[remoteId] = remoteItem;
      }
    });
  }

  // --- Saving to json ---
  Map<String, dynamic> toJson() {
    return {
      // dict to json
      'items': items.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory CrdtShoppingList.fromJson(Map<String, dynamic> json) {
    final list = CrdtShoppingList();
    final itemsJson = json['items'] as Map<String, dynamic>? ?? {};

    itemsJson.forEach((key, value) {
      list.items[key] = CrdtShoppingItem.fromJson(value);
    });

    return list;
  }
}
