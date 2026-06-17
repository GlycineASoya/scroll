// lib/models/shopping_item.dart

class ShoppingItem {
  final String id;
  final String name;
  bool isBought;

  ShoppingItem({
    required this.id,
    required this.name,
    this.isBought = false,
  });

  // map to json
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isBought': isBought,
    };
  }

  // create item from json
  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      isBought: json['isBought'] as bool,
    );
  }
}