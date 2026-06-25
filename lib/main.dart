import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:home_widget/home_widget.dart';

import 'models/crdt_models.dart';
import 'services/google_drive_service.dart';

// --- BACKGROUND CLICK HANDLER FOR THE WIDGET ---
Future<void> updateWidgetData(CrdtShoppingList list) async {
  List<Map<String, dynamic>> widgetItems = [];

  // 1. First, add only NOT PURCHASED items
  final activeItems = list.visibleItems.where((item) => !item.isBought.value);
  for (var item in activeItems) {
    widgetItems.add({
      'id': item.id,
      'name': item.name.value,
      'isBought': false,
    });
  }

  // 2. Then add PURCHASED items (they will always be at the bottom)
  final boughtItems = list.visibleItems.where((item) => item.isBought.value);
  for (var item in boughtItems) {
    widgetItems.add({'id': item.id, 'name': item.name.value, 'isBought': true});
  }

  if (widgetItems.isEmpty) {
    widgetItems.add({
      'id': 'empty',
      'name': 'The list is empty',
      'isBought': false,
    });
  }

  final jsonString = jsonEncode(widgetItems);
  await HomeWidget.saveWidgetData<String>('list_data_json', jsonString);
  await HomeWidget.updateWidget(
    name: 'ShoppingListWidget',
    androidName: 'ShoppingListWidget',
  );
}

@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  // Log to the console to verify that the isolate has started
  debugPrint('✅ STATUS CHANGED AND WIDGET UPDATED');

  if (uri?.host == 'toggle') {
    final id = uri?.queryParameters['id'];
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();

      // CRITICALLY IMPORTANT: force the background process to reload the physical preferences file,
      // otherwise it will use stale cached data from its own isolate!
      await prefs.reload();

      String? jsonString = prefs.getString('crdt_shopping_list');

      if (jsonString != null) {
        final list = CrdtShoppingList.fromJson(jsonDecode(jsonString));

        try {
          final item = list.visibleItems.firstWhere((e) => e.id == id);
          final now = DateTime.now().millisecondsSinceEpoch;

          // Toggle the status (bought/not bought)
          item.isBought = LwwRecord(
            value: !item.isBought.value,
            timestamp: now,
          );

          // Save the updated list
          await prefs.setString(
            'crdt_shopping_list',
            jsonEncode(list.toJson()),
          );

          // Trigger the widget refresh
          await updateWidgetData(list);
          debugPrint('✅ STATUS CHANGED AND WIDGET UPDATED');
        } catch (e) {
          debugPrint('❌ Error finding item: $e');
        }
      }
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.registerBackgroundCallback(interactiveCallback);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRDT Shopping Sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
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

class _ShoppingScreenState extends State<ShoppingScreen>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  CrdtShoppingList _shoppingList = CrdtShoppingList();

  final GoogleDriveService _driveService = GoogleDriveService();

  bool _isAuthenticated = false;
  bool _isSyncing = false;
  bool _isSharing = false;

  late final String _fileName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fileName = _driveService.generateFileName('ScrollApp', 'Main List');
    _loadLocalData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When the app resumes, read checkbox changes and the pending add queue
      _loadLocalData();
    }
  }

  // --- WIDGET UPDATE LOGIC (FOR LISTVIEW) ---
  Future<void> _updateWidget() async {
    await updateWidgetData(_shoppingList);
  }

  // --- PROCESS THE QUICK ADD QUEUE FROM THE WIDGET ---
  Future<void> _processPendingWidgetAdds() async {
    final String? pendingJson = await HomeWidget.getWidgetData<String>(
      'pending_adds',
    );

    if (pendingJson != null && pendingJson != '[]') {
      try {
        final List<dynamic> pendingList = jsonDecode(pendingJson);
        if (pendingList.isNotEmpty) {
          setState(() {
            for (var itemName in pendingList) {
              // Generate a unique ID for the CRDT
              final id =
                  '${DateTime.now().millisecondsSinceEpoch}_${itemName.hashCode}';
              final newItem = CrdtShoppingItem.create(
                id,
                itemName.toString().trim(),
              );
              _shoppingList.putItem(newItem);
            }
          });

          // Clear the widget queue in SharedPreferences
          await HomeWidget.saveWidgetData<String>('pending_adds', '[]');

          // Save locally and push to Google Drive
          await _saveLocalData();
          await _syncWithDrive();
        }
      } catch (e) {
        debugPrint('Error parsing widget queue: $e');
      }
    }
  }

  // --- LOCAL DATA CRUD ---
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    String? jsonString = prefs.getString('crdt_shopping_list');
    if (jsonString != null) {
      setState(() {
        _shoppingList = CrdtShoppingList.fromJson(jsonDecode(jsonString));
      });
    }

    // First, process the pending queue from the widget, if any
    await _processPendingWidgetAdds();
    // First, process the pending queue from the widget, if any
    await _updateWidget();
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    String jsonString = jsonEncode(_shoppingList.toJson());
    await prefs.setString('crdt_shopping_list', jsonString);

    // Update widget after every list save
    await _updateWidget();
  }

  // --- AUTHZ and SYNC ---

  Future<void> _signIn() async {
    setState(() => _isSyncing = true);
    final success = await _driveService.signIn();

    setState(() {
      _isAuthenticated = success;
      _isSyncing = false;
    });

    if (success) {
      await _syncWithDrive();
    }
  }

  Future<void> _signOut() async {
    await _driveService.signOut();
    setState(() {
      _isAuthenticated = false;
    });
  }

  Future<void> _syncWithDrive() async {
    if (!_isAuthenticated) return;

    setState(() => _isSyncing = true);

    try {
      final remoteJson = await _driveService.downloadJson(_fileName);

      if (remoteJson != null) {
        final remoteList = CrdtShoppingList.fromJson(remoteJson);
        setState(() {
          _shoppingList.merge(remoteList);
        });
        await _saveLocalData();
      }

      await _driveService.uploadJson(_fileName, _shoppingList.toJson());
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  // --- SHARING ---

  Future<void> _shareList() async {
    if (!_isAuthenticated) return;

    setState(() => _isSharing = true);
    final allContacts = await _driveService.getContacts();
    setState(() => _isSharing = false);

    if (!mounted) return;

    List<ContactInfo> filteredContacts = List.from(allContacts);

    final selectedEmail = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SimpleDialog(
          title: const Text('Share with...'),
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search (name or email)',
                ),
                onChanged: (val) {
                  setDialogState(() {
                    filteredContacts = allContacts
                        .where(
                          (c) =>
                              c.name.toLowerCase().contains(
                                val.toLowerCase(),
                              ) ||
                              c.email.toLowerCase().contains(val.toLowerCase()),
                        )
                        .toList();
                  });
                },
              ),
            ),
            ...filteredContacts.map(
              (contact) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, contact.email),
                child: ListTile(
                  title: Text(contact.name),
                  subtitle: Text(contact.email),
                  leading: const Icon(Icons.person, color: Colors.teal),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Start sharing
    if (selectedEmail != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sharing access with $selectedEmail...')),
      );

      final success = await _driveService.shareFileWithUser(
        _fileName,
        selectedEmail,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully shared!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access granting error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- UI ---
  void _addItem() {
    if (_textController.text.isNotEmpty) {
      setState(() {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        final newItem = CrdtShoppingItem.create(id, _textController.text);
        _shoppingList.putItem(newItem);
      });
      _textController.clear();
      _saveLocalData();
      _syncWithDrive();
    }
  }

  void _deleteItem(CrdtShoppingItem item) {
    setState(() {
      final now = DateTime.now().millisecondsSinceEpoch;
      item.isDeleted = LwwRecord(value: true, timestamp: now);
    });
    _saveLocalData();
    _syncWithDrive();
  }

  void _toggleItem(CrdtShoppingItem item, bool? value) {
    setState(() {
      final now = DateTime.now().millisecondsSinceEpoch;
      item.isBought = LwwRecord(value: value ?? false, timestamp: now);
    });
    _saveLocalData();
    _syncWithDrive();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _shoppingList.visibleItems;
    final isBusy = _isSyncing || _isSharing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping list'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Sharing button (for logged users only)
          if (_isAuthenticated)
            IconButton(
              icon: _isSharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black54,
                      ),
                    )
                  : const Icon(Icons.group_add),
              onPressed: isBusy ? null : _shareList,
              tooltip: 'Share the list',
            ),

          // Sync button
          if (_isAuthenticated)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black54,
                      ),
                    )
                  : const Icon(Icons.sync),
              onPressed: isBusy ? null : _syncWithDrive,
              tooltip: 'Sync',
            ),

          // Login/Logout button
          IconButton(
            icon: Icon(_isAuthenticated ? Icons.logout : Icons.login),
            onPressed: isBusy ? null : (_isAuthenticated ? _signOut : _signIn),
            tooltip: _isAuthenticated ? 'Logout' : 'Logout from Google',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isAuthenticated && _driveService.currentUser != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              color: Colors.teal.withValues(alpha: 0.1),
              width: double.infinity,
              child: Text(
                'Sync is enabled: ${_driveService.currentUser!.email}',
                style: const TextStyle(fontSize: 12, color: Colors.teal),
                textAlign: TextAlign.center,
              ),
            ),

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
            child: visibleItems.isEmpty
                ? const Center(child: Text('Empty list'))
                : ListView.builder(
                    itemCount: visibleItems.length,
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      return Dismissible(
                        key: Key(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) => _deleteItem(item),
                        child: CheckboxListTile(
                          title: Text(
                            item.name.value,
                            style: TextStyle(
                              decoration: item.isBought.value
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.isBought.value
                                  ? Colors.grey
                                  : Colors.black,
                            ),
                          ),
                          value: item.isBought.value,
                          onChanged: (value) => _toggleItem(item, value),
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
