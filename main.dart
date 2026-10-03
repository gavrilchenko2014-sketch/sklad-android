import 'package:flutter/material.dart';

import 'database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WarehouseApp());
}

class WarehouseApp extends StatelessWidget {
  const WarehouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Склад',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF455A64),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  List<InventoryItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final items = await WarehouseDatabase.instance.getItems(
      query: _searchController.text,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final request = await showDialog<NewItemRequest>(
      context: context,
      builder: (context) => const AddItemDialog(),
    );
    if (request == null) return;

    try {
      await WarehouseDatabase.instance.addItem(
        name: request.name,
        category: request.category,
        initialQuantity: request.initialQuantity,
        unit: request.unit,
        location: request.location,
        note: request.note,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    }
  }

  Future<void> _changeStock(InventoryItem item, bool incoming) async {
    final request = await showDialog<StockChangeRequest>(
      context: context,
      builder: (context) => StockChangeDialog(
        title: incoming ? 'Приход' : 'Выдача',
        itemName: item.name,
        available: item.quantity,
        unit: item.unit,
      ),
    );
    if (request == null) return;

    try {
      await WarehouseDatabase.instance.changeStock(
        itemId: item.id,
        delta: incoming ? request.quantity : -request.quantity,
        type: incoming ? 'Приход' : 'Выдача',
        note: request.note,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zeroStock = _items.where((item) => item.quantity == 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Склад'),
        actions: [
          IconButton(
            tooltip: 'История операций',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const HistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Поиск по названию, категории, месту',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _reload();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Позиций',
                    value: '${_items.length}',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Нулевой остаток',
                    value: '$zeroStock',
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_items.isEmpty)
              const _EmptyState()
            else
              ..._items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (item.category.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(item.category),
                                    ),
                                  if (item.location.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        'Место: ${item.location}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${item.quantity} ${item.unit}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _changeStock(item, true),
                                icon: const Icon(Icons.add),
                                label: const Text('Приход'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: item.quantity == 0
                                    ? null
                                    : () => _changeStock(item, false),
                                icon: const Icon(Icons.remove),
                                label: const Text('Выдача'),
                              ),
                            ),
                          ],
                        ),
                        if (item.note.isNotEmpty) ...[
                          const Divider(height: 22),
                          Text(
                            item.note,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 56),
          const SizedBox(height: 12),
          Text('Склад пока пуст', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Нажми «Добавить», чтобы создать первую позицию.'),
        ],
      ),
    );
  }
}

class AddItemDialog extends StatefulWidget {
  const AddItemDialog({super.key});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _quantity = TextEditingController(text: '0');
  final _unit = TextEditingController(text: 'шт.');
  final _location = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _quantity.dispose();
    _unit.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая позиция'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Наименование *'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Укажи наименование'
                      : null,
                ),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Категория'),
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Начальный остаток'),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          if (parsed == null || parsed < 0) {
                            return 'Число ≥ 0';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        decoration: const InputDecoration(labelText: 'Ед.'),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: 'Место хранения'),
                ),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Примечание'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              NewItemRequest(
                name: _name.text.trim(),
                category: _category.text.trim(),
                initialQuantity: int.parse(_quantity.text.trim()),
                unit: _unit.text.trim(),
                location: _location.text.trim(),
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class NewItemRequest {
  const NewItemRequest({
    required this.name,
    required this.category,
    required this.initialQuantity,
    required this.unit,
    required this.location,
    required this.note,
  });

  final String name;
  final String category;
  final int initialQuantity;
  final String unit;
  final String location;
  final String note;
}

class StockChangeDialog extends StatefulWidget {
  const StockChangeDialog({
    super.key,
    required this.title,
    required this.itemName,
    required this.available,
    required this.unit,
  });

  final String title;
  final String itemName;
  final int available;
  final String unit;

  @override
  State<StockChangeDialog> createState() => _StockChangeDialogState();
}

class _StockChangeDialogState extends State<StockChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _note = TextEditingController();

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.itemName),
            const SizedBox(height: 4),
            Text(
              'Текущий остаток: ${widget.available} ${widget.unit}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Количество, ${widget.unit}'),
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed <= 0) return 'Укажи число больше 0';
                return null;
              },
            ),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Примечание'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              StockChangeRequest(
                quantity: int.parse(_quantity.text.trim()),
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Провести'),
        ),
      ],
    );
  }
}

class StockChangeRequest {
  const StockChangeRequest({required this.quantity, required this.note});

  final int quantity;
  final String note;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final Future<List<StockMovement>> _movements;

  @override
  void initState() {
    super.initState();
    _movements = WarehouseDatabase.instance.getMovements();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История операций')),
      body: FutureBuilder<List<StockMovement>>(
        future: _movements,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }

          final movements = snapshot.data ?? const [];
          if (movements.isEmpty) {
            return const Center(child: Text('Операций пока нет.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: movements.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final movement = movements[index];
              final date = movement.createdAt.toLocal();
              final dateText =
                  '${_two(date.day)}.${_two(date.month)}.${date.year} '
                  '${_two(date.hour)}:${_two(date.minute)}';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  movement.type == 'Выдача'
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                ),
                title: Text(movement.itemName),
                subtitle: Text(
                  movement.note.isEmpty
                      ? '${movement.type} • $dateText'
                      : '${movement.type} • $dateText\n${movement.note}',
                ),
                trailing: Text(
                  '${movement.quantity}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
