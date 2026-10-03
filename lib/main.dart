import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  int _selectedIndex = 0;
  int _issuedRefresh = 0;

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
    if (mounted) setState(() => _loading = true);
    final items = await WarehouseDatabase.instance.getItems(
      query: _searchController.text,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _refreshAll() async {
    if (mounted) setState(() => _issuedRefresh++);
    await _reload();
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
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
    }
  }

  Future<void> _changeStock(InventoryItem item, StockAction action) async {
    final request = await showDialog<StockChangeRequest>(
      context: context,
      builder: (context) => StockChangeDialog(
        action: action,
        itemName: item.name,
        available: item.quantity,
        unit: item.unit,
      ),
    );
    if (request == null) return;

    final delta = switch (action) {
      StockAction.incoming => request.quantity,
      StockAction.outgoing => -request.quantity,
      StockAction.returned => request.quantity,
    };
    final type = switch (action) {
      StockAction.incoming => 'Приход',
      StockAction.outgoing => 'Выдача',
      StockAction.returned => 'Возврат',
    };

    try {
      await WarehouseDatabase.instance.changeStock(
        itemId: item.id,
        delta: delta,
        type: type,
        recipient: request.recipient,
        note: request.note,
      );
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _inventory(InventoryItem item) async {
    final request = await showDialog<InventoryRequest>(
      context: context,
      builder: (context) => InventoryDialog(item: item),
    );
    if (request == null) return;

    try {
      await WarehouseDatabase.instance.setInventoryQuantity(
        itemId: item.id,
        actualQuantity: request.actualQuantity,
        note: request.note,
      );
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const HistoryScreen()),
    );
    if (!mounted) return;
    await _refreshAll();
  }

  Future<void> _createBackup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'sklad_backup_${now.year}${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}.db';
      final backup = await WarehouseDatabase.instance.createBackupFile(
        p.join(tempDir.path, fileName),
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backup.path)],
          text: 'Резервная копия приложения «Склад»',
          subject: 'Резервная копия склада',
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      _showError('Не удалось создать резервную копию: $error');
    }
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      _showError('Не удалось получить выбранный файл.');
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановить копию?'),
        content: const Text(
          'Текущая база будет заменена данными из выбранной резервной копии.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await WarehouseDatabase.instance.restoreBackup(sourcePath);
      _searchController.clear();
      if (!mounted) return;
      setState(() {
        _selectedIndex = 0;
        _issuedRefresh++;
      });
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Резервная копия восстановлена.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError('Не удалось восстановить копию: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Склад' : 'Выдано'),
        actions: [
          IconButton(
            tooltip: 'История операций',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (value) {
              if (value == 'backup') _createBackup();
              if (value == 'restore') _restoreBackup();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Создать резервную копию'),
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restore_page_outlined),
                  title: Text('Восстановить из копии'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Склад',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_ind_outlined),
            selectedIcon: Icon(Icons.assignment_ind),
            label: 'Выдано',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _WarehouseTab(
            searchController: _searchController,
            items: _items,
            loading: _loading,
            onReload: _reload,
            onSearchChanged: _reload,
            onClearSearch: () {
              _searchController.clear();
              _reload();
            },
            onIncoming: (item) => _changeStock(item, StockAction.incoming),
            onOutgoing: (item) => _changeStock(item, StockAction.outgoing),
            onReturn: (item) => _changeStock(item, StockAction.returned),
            onInventory: _inventory,
          ),
          _IssuedTab(key: ValueKey(_issuedRefresh)),
        ],
      ),
    );
  }
}

enum StockAction { incoming, outgoing, returned }

class _WarehouseTab extends StatelessWidget {
  const _WarehouseTab({
    required this.searchController,
    required this.items,
    required this.loading,
    required this.onReload,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onIncoming,
    required this.onOutgoing,
    required this.onReturn,
    required this.onInventory,
  });

  final TextEditingController searchController;
  final List<InventoryItem> items;
  final bool loading;
  final Future<void> Function() onReload;
  final Future<void> Function() onSearchChanged;
  final VoidCallback onClearSearch;
  final void Function(InventoryItem item) onIncoming;
  final void Function(InventoryItem item) onOutgoing;
  final void Function(InventoryItem item) onReturn;
  final void Function(InventoryItem item) onInventory;

  @override
  Widget build(BuildContext context) {
    final zeroStock = items.where((item) => item.quantity == 0).length;

    return RefreshIndicator(
      onRefresh: onReload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          TextField(
            controller: searchController,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              hintText: 'Поиск по названию, категории, месту',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClearSearch,
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
                  value: '${items.length}',
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
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (items.isEmpty)
            const _EmptyState()
          else
            ...items.map(
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
                                      style: Theme.of(context).textTheme.bodySmall,
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
                              onPressed: () => onIncoming(item),
                              icon: const Icon(Icons.add),
                              label: const Text('Приход'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: item.quantity == 0
                                  ? null
                                  : () => onOutgoing(item),
                              icon: const Icon(Icons.remove),
                              label: const Text('Выдача'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => onReturn(item),
                              icon: const Icon(Icons.undo),
                              label: const Text('Возврат'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => onInventory(item),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Инвентаризация'),
                            ),
                          ),
                        ],
                      ),
                      if (item.note.isNotEmpty) ...[
                        const Divider(height: 22),
                        Text(item.note, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IssuedTab extends StatelessWidget {
  const _IssuedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StockMovement>>(
      future: WarehouseDatabase.instance.getIssuedMovements(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Ошибка: ${snapshot.error}'));
        }

        final movements = snapshot.data ?? const [];
        if (movements.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Пока ничего не выдавалось.'),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: movements.length,
          itemBuilder: (context, index) {
            final movement = movements[index];
            final recipient = movement.recipient.trim();

            return Card(
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
                          child: Text(
                            movement.itemName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${movement.quantity} ${movement.unit}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            recipient.isEmpty
                                ? 'Кому: не указано'
                                : 'Кому: $recipient',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 20),
                        const SizedBox(width: 8),
                        Text('Когда: ${_formatDateTime(movement.createdAt)}'),
                      ],
                    ),
                    if (movement.note.isNotEmpty) ...[
                      const Divider(height: 22),
                      Text('Примечание: ${movement.note}'),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
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
                        decoration: const InputDecoration(
                          labelText: 'Начальный остаток',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          if (parsed == null || parsed < 0) return 'Число ≥ 0';
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
    required this.action,
    required this.itemName,
    required this.available,
    required this.unit,
  });

  final StockAction action;
  final String itemName;
  final int available;
  final String unit;

  @override
  State<StockChangeDialog> createState() => _StockChangeDialogState();
}

class _StockChangeDialogState extends State<StockChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _recipient = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _quantity.dispose();
    _recipient.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.action) {
      StockAction.incoming => 'Приход',
      StockAction.outgoing => 'Выдача',
      StockAction.returned => 'Возврат',
    };
    final needsPerson = widget.action != StockAction.incoming;
    final personLabel = widget.action == StockAction.outgoing
        ? 'Кому выдано *'
        : 'От кого возвращено *';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
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
                  decoration: InputDecoration(
                    labelText: 'Количество, ${widget.unit}',
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Укажи число больше 0';
                    }
                    if (widget.action == StockAction.outgoing &&
                        parsed > widget.available) {
                      return 'На складе только ${widget.available} ${widget.unit}';
                    }
                    return null;
                  },
                ),
                if (needsPerson)
                  TextFormField(
                    controller: _recipient,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: personLabel,
                      hintText: 'Фамилия, имя или подразделение',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Заполни это поле';
                      }
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
                recipient: needsPerson ? _recipient.text.trim() : '',
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
  const StockChangeRequest({
    required this.quantity,
    required this.recipient,
    required this.note,
  });

  final int quantity;
  final String recipient;
  final String note;
}

class InventoryDialog extends StatefulWidget {
  const InventoryDialog({super.key, required this.item});

  final InventoryItem item;

  @override
  State<InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<InventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _actual;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _actual = TextEditingController(text: '${widget.item.quantity}');
  }

  @override
  void dispose() {
    _actual.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Инвентаризация'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.name),
            const SizedBox(height: 4),
            Text(
              'Учётный остаток: ${widget.item.quantity} ${widget.item.unit}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _actual,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Фактически, ${widget.item.unit}',
              ),
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed < 0) return 'Укажи число ≥ 0';
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
              InventoryRequest(
                actualQuantity: int.parse(_actual.text.trim()),
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Зафиксировать'),
        ),
      ],
    );
  }
}

class InventoryRequest {
  const InventoryRequest({required this.actualQuantity, required this.note});

  final int actualQuantity;
  final String note;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<StockMovement>> _movements;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _movements = WarehouseDatabase.instance.getMovements();
  }

  Future<void> _edit(StockMovement movement) async {
    final request = await showDialog<EditMovementRequest>(
      context: context,
      builder: (context) => EditMovementDialog(movement: movement),
    );
    if (request == null) return;

    try {
      await WarehouseDatabase.instance.editMovement(
        movementId: movement.id,
        quantity: request.quantity,
        recipient: request.recipient,
        note: request.note,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _delete(StockMovement movement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить операцию?'),
        content: Text(
          '${movement.type}: ${movement.itemName}, '
          '${movement.quantity} ${movement.unit}.\n\n'
          'Остаток на складе будет автоматически пересчитан.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await WarehouseDatabase.instance.deleteMovement(movement.id);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
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
              final parts = <String>[
                '${movement.type} • ${_formatDateTime(movement.createdAt)}',
              ];

              if ((movement.type == 'Выдача' || movement.type == 'Возврат') &&
                  movement.recipient.trim().isNotEmpty) {
                parts.add(
                  movement.type == 'Выдача'
                      ? 'Кому: ${movement.recipient.trim()}'
                      : 'От кого: ${movement.recipient.trim()}',
                );
              }
              if (movement.note.isNotEmpty) parts.add(movement.note);

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_movementIcon(movement.type)),
                title: Text(movement.itemName),
                subtitle: Text(parts.join('\n')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _movementAmount(movement),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(movement);
                        if (value == 'delete') _delete(movement);
                      },
                      itemBuilder: (context) => [
                        if (movement.canEdit)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Исправить'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EditMovementDialog extends StatefulWidget {
  const EditMovementDialog({super.key, required this.movement});

  final StockMovement movement;

  @override
  State<EditMovementDialog> createState() => _EditMovementDialogState();
}

class _EditMovementDialogState extends State<EditMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _recipient;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(text: '${widget.movement.quantity}');
    _recipient = TextEditingController(text: widget.movement.recipient);
    _note = TextEditingController(text: widget.movement.note);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _recipient.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsPerson =
        widget.movement.type == 'Выдача' || widget.movement.type == 'Возврат';

    return AlertDialog(
      title: Text('Исправить: ${widget.movement.type}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Количество, ${widget.movement.unit}',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) return 'Укажи число > 0';
                  return null;
                },
              ),
              if (needsPerson)
                TextFormField(
                  controller: _recipient,
                  decoration: InputDecoration(
                    labelText: widget.movement.type == 'Выдача'
                        ? 'Кому выдано *'
                        : 'От кого возвращено *',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Заполни это поле'
                      : null,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              EditMovementRequest(
                quantity: int.parse(_quantity.text.trim()),
                recipient: needsPerson ? _recipient.text.trim() : '',
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

class EditMovementRequest {
  const EditMovementRequest({
    required this.quantity,
    required this.recipient,
    required this.note,
  });

  final int quantity;
  final String recipient;
  final String note;
}

String _formatDateTime(DateTime value) {
  final date = value.toLocal();
  return '${_two(date.day)}.${_two(date.month)}.${date.year} '
      '${_two(date.hour)}:${_two(date.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

IconData _movementIcon(String type) {
  return switch (type) {
    'Выдача' => Icons.remove_circle_outline,
    'Возврат' => Icons.undo,
    'Инвентаризация' => Icons.fact_check_outlined,
    _ => Icons.add_circle_outline,
  };
}

String _movementAmount(StockMovement movement) {
  if (movement.type == 'Инвентаризация') {
    final sign = movement.delta > 0 ? '+' : '';
    return '$sign${movement.delta} ${movement.unit}';
  }
  final sign = movement.delta < 0 ? '−' : '+';
  return '$sign${movement.quantity} ${movement.unit}';
}
