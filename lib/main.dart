// lib/main.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // json-decoder

import 'models/shopping_item.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scroll',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ShoppingScreen(),
    );
  }
}

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final TextEditingController _textController = TextEditingController();
  
  List<ShoppingItem> _shoppingList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // save/load list
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    // mapping to json
    List<Map<String, dynamic>> jsonList = _shoppingList.map((item) => item.toJson()).toList();
    String jsonString = jsonEncode(jsonList);
    await prefs.setString('my_shopping_list', jsonString);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('my_shopping_list');
    
    if (jsonString != null) {
      List<dynamic> decodedList = jsonDecode(jsonString);
      setState(() {
        _shoppingList = decodedList.map((item) => ShoppingItem.fromJson(item)).toList();
      });
    }
  }


  // list actions
  void _addItem() {
    if (_textController.text.isNotEmpty) {
      setState(() {
        _shoppingList.add(
          ShoppingItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: _textController.text,
          ),
        );
      });
      _textController.clear();
      _saveData();
    }
  }

  void _deleteItem(int index) {
    setState(() {
      _shoppingList.removeAt(index);
    });
    _saveData();
  }

  void _toggleItem(int index, bool? value) {
    setState(() {
      _shoppingList[index].isBought = value ?? false;
    });
    _saveData();
  }


  //interface
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My list'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'What to buy?',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addItem(), 
                  ),
                ),
                const SizedBox(width: 10),
                FloatingActionButton(
                  onPressed: _addItem,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: _shoppingList.length,
              itemBuilder: (context, index) {
                final item = _shoppingList[index];
                
                return Dismissible(
                  key: Key(item.id), 
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) => _deleteItem(index),
                  child: CheckboxListTile(
                    title: Text(
                      item.name,
                      style: TextStyle(
                        decoration: item.isBought ? TextDecoration.lineThrough : null,
                        color: item.isBought ? Colors.grey : Colors.black,
                      ),
                    ),
                    value: item.isBought,
                    onChanged: (value) => _toggleItem(index, value),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}