import 'dart:io';

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
      _showError(_cleanError(error));
    }
  }

  Future<void> _editItem(InventoryItem item) async {
    final request = await showDialog<EditItemRequest>(
      context: context,
      builder: (context) => EditItemDialog(item: item),
    );
    if (request == null) return;

    try {
      await WarehouseDatabase.instance.updateItem(
        itemId: item.id,
        name: request.name,
        category: request.category,
        unit: request.unit,
        location: request.location,
        note: request.note,
      );
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showError(_cleanError(error));
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить позицию?'),
        content: Text(
          '«${item.name}» исчезнет из активного склада.\n\n'
          'Остаток сейчас: ${item.quantity} ${item.unit}. '
          'История операций сохранится, а саму позицию можно будет '
          'восстановить через «Удалённые позиции».',
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
      await WarehouseDatabase.instance.deleteItem(item.id);
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showError(_cleanError(error));
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
      StockAction.writeOff => -request.quantity,
    };
    final type = switch (action) {
      StockAction.incoming => 'Приход',
      StockAction.outgoing => 'Выдача',
      StockAction.returned => 'Возврат',
      StockAction.writeOff => 'Списание',
    };

    try {
      await WarehouseDatabase.instance.changeStock(
        itemId: item.id,
        delta: delta,
        type: type,
        recipient: request.recipient,
        department: request.department,
        note: request.note,
      );
      await _refreshAll();
    } catch (error) {
      if (!mounted) return;
      _showError(_cleanError(error));
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
      _showError(_cleanError(error));
    }
  }

  Future<void> _openItem(InventoryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ItemDetailScreen(itemId: item.id),
      ),
    );
    if (!mounted) return;
    await _refreshAll();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const HistoryScreen()),
    );
    if (!mounted) return;
    await _refreshAll();
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const TrashScreen()),
    );
    if (!mounted) return;
    await _refreshAll();
  }

  Future<void> _openDeletedItems() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const DeletedItemsScreen(),
      ),
    );
    if (!mounted) return;
    await _refreshAll();
  }

  Future<void> _openReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const ReportScreen()),
    );
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
      _showError('Не удалось создать резервную копию: ${_cleanError(error)}');
    }
  }

  Future<void> _restoreBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (file == null) return;

    final sourcePath = file.path;
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
      _showError('Не удалось восстановить копию: ${_cleanError(error)}');
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
              if (value == 'report') _openReport();
              if (value == 'trash') _openTrash();
              if (value == 'deleted_items') _openDeletedItems();
              if (value == 'backup') _createBackup();
              if (value == 'restore') _restoreBackup();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.summarize_outlined),
                  title: Text('Отчёт за период'),
                ),
              ),
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Корзина операций'),
                ),
              ),
              PopupMenuItem(
                value: 'deleted_items',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Удалённые позиции'),
                ),
              ),
              PopupMenuDivider(),
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
            onOpen: _openItem,
            onEdit: _editItem,
            onDelete: _deleteItem,
            onIncoming: (item) => _changeStock(item, StockAction.incoming),
            onOutgoing: (item) => _changeStock(item, StockAction.outgoing),
            onReturn: (item) => _changeStock(item, StockAction.returned),
            onWriteOff: (item) => _changeStock(item, StockAction.writeOff),
            onInventory: _inventory,
          ),
          _IssuedTab(key: ValueKey(_issuedRefresh)),
        ],
      ),
    );
  }
}

enum StockAction { incoming, outgoing, returned, writeOff }

class _WarehouseTab extends StatelessWidget {
  const _WarehouseTab({
    required this.searchController,
    required this.items,
    required this.loading,
    required this.onReload,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onIncoming,
    required this.onOutgoing,
    required this.onReturn,
    required this.onWriteOff,
    required this.onInventory,
  });

  final TextEditingController searchController;
  final List<InventoryItem> items;
  final bool loading;
  final Future<void> Function() onReload;
  final Future<void> Function() onSearchChanged;
  final VoidCallback onClearSearch;
  final void Function(InventoryItem item) onOpen;
  final void Function(InventoryItem item) onEdit;
  final void Function(InventoryItem item) onDelete;
  final void Function(InventoryItem item) onIncoming;
  final void Function(InventoryItem item) onOutgoing;
  final void Function(InventoryItem item) onReturn;
  final void Function(InventoryItem item) onWriteOff;
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
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onOpen(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
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
                                    const SizedBox(height: 4),
                                    Text(
                                      'Нажми, чтобы открыть карточку и историю',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${item.quantity} ${item.unit}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Позиция',
                                    onSelected: (value) {
                                      if (value == 'edit') onEdit(item);
                                      if (value == 'delete') onDelete(item);
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('Редактировать'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.delete_outline),
                                          title: Text('Удалить позицию'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: item.quantity == 0
                              ? null
                              : () => onWriteOff(item),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Списание'),
                        ),
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
    );
  }
}

class _IssuedTab extends StatefulWidget {
  const _IssuedTab({super.key});

  @override
  State<_IssuedTab> createState() => _IssuedTabState();
}

class _IssuedTabState extends State<_IssuedTab> {
  IssuedFilters _filters = const IssuedFilters();
  late Future<List<StockMovement>> _movements;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _movements = WarehouseDatabase.instance.getIssuedMovements(
      recipient: _filters.recipient,
      item: _filters.item,
      department: _filters.department,
      from: _filters.range?.start,
      to: _filters.range?.end,
    );
  }

  Future<void> _openFilters() async {
    final result = await showDialog<IssuedFilters>(
      context: context,
      builder: (context) => IssuedFilterDialog(initial: _filters),
    );
    if (result == null) return;
    setState(() {
      _filters = result;
      _reload();
    });
  }

  void _clearFilters() {
    setState(() {
      _filters = const IssuedFilters();
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StockMovement>>(
      future: _movements,
      builder: (context, snapshot) {
        final movements = snapshot.data ?? const <StockMovement>[];
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _movements;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openFilters,
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: Text(
                        _filters.isEmpty ? 'Фильтры' : 'Фильтры включены',
                      ),
                    ),
                  ),
                  if (!_filters.isEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Сбросить фильтры',
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                    ),
                  ],
                ],
              ),
              if (!_filters.isEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _filters.labels
                      .map((label) => Chip(label: Text(label)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ошибка: ${snapshot.error}'),
                )
              else if (movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('По этим условиям выдач нет.')),
                )
              else ...[
                Text(
                  'Найдено: ${movements.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ...movements.map(
                  (movement) => Card(
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
                          _IconText(
                            icon: Icons.person_outline,
                            text: movement.recipient.trim().isEmpty
                                ? 'Кому: не указано'
                                : 'Кому: ${movement.recipient.trim()}',
                          ),
                          if (movement.department.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _IconText(
                              icon: Icons.groups_outlined,
                              text:
                                  'Подразделение: ${movement.department.trim()}',
                            ),
                          ],
                          const SizedBox(height: 6),
                          _IconText(
                            icon: Icons.schedule,
                            text: 'Когда: ${_formatDateTime(movement.createdAt)}',
                          ),
                          if (movement.note.isNotEmpty) ...[
                            const Divider(height: 22),
                            Text('Примечание: ${movement.note}'),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class IssuedFilters {
  const IssuedFilters({
    this.recipient = '',
    this.item = '',
    this.department = '',
    this.range,
  });

  final String recipient;
  final String item;
  final String department;
  final DateTimeRange? range;

  bool get isEmpty =>
      recipient.trim().isEmpty &&
      item.trim().isEmpty &&
      department.trim().isEmpty &&
      range == null;

  List<String> get labels {
    final result = <String>[];
    if (recipient.trim().isNotEmpty) result.add('Кому: ${recipient.trim()}');
    if (item.trim().isNotEmpty) result.add('Позиция: ${item.trim()}');
    if (department.trim().isNotEmpty) {
      result.add('Подразделение: ${department.trim()}');
    }
    if (range != null) {
      result.add(
        '${_formatDate(range!.start)} — ${_formatDate(range!.end)}',
      );
    }
    return result;
  }
}

class IssuedFilterDialog extends StatefulWidget {
  const IssuedFilterDialog({super.key, required this.initial});

  final IssuedFilters initial;

  @override
  State<IssuedFilterDialog> createState() => _IssuedFilterDialogState();
}

class _IssuedFilterDialogState extends State<IssuedFilterDialog> {
  late final TextEditingController _recipient;
  late final TextEditingController _item;
  late final TextEditingController _department;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _recipient = TextEditingController(text: widget.initial.recipient);
    _item = TextEditingController(text: widget.initial.item);
    _department = TextEditingController(text: widget.initial.department);
    _range = widget.initial.range;
  }

  @override
  void dispose() {
    _recipient.dispose();
    _item.dispose();
    _department.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Фильтры выдачи'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _recipient,
                decoration: const InputDecoration(
                  labelText: 'Человек / получатель',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              TextField(
                controller: _item,
                decoration: const InputDecoration(
                  labelText: 'Позиция',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              TextField(
                controller: _department,
                decoration: const InputDecoration(
                  labelText: 'Подразделение',
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_outlined),
                title: Text(
                  _range == null
                      ? 'Дата: любой период'
                      : '${_formatDate(_range!.start)} — '
                          '${_formatDate(_range!.end)}',
                ),
                trailing: _range == null
                    ? null
                    : IconButton(
                        tooltip: 'Сбросить дату',
                        onPressed: () => setState(() => _range = null),
                        icon: const Icon(Icons.clear),
                      ),
                onTap: _pickRange,
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
            Navigator.of(context).pop(
              IssuedFilters(
                recipient: _recipient.text.trim(),
                item: _item.text.trim(),
                department: _department.text.trim(),
                range: _range,
              ),
            );
          },
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final int itemId;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late Future<_ItemDetailData> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<_ItemDetailData> _load() async {
    final item = await WarehouseDatabase.instance.getItem(widget.itemId);
    final movements = await WarehouseDatabase.instance.getMovements(
      itemId: widget.itemId,
    );
    return _ItemDetailData(item: item, movements: movements);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка позиции')),
      body: FutureBuilder<_ItemDetailData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final item = data.item;
          if (item == null) {
            return const Center(child: Text('Позиция не найдена.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _data;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '${item.quantity} ${item.unit}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        if (item.category.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _IconText(
                            icon: Icons.category_outlined,
                            text: item.category,
                          ),
                        ],
                        if (item.location.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _IconText(
                            icon: Icons.place_outlined,
                            text: 'Место: ${item.location}',
                          ),
                        ],
                        if (item.note.isNotEmpty) ...[
                          const Divider(height: 22),
                          Text(item.note),
                        ],
                        if (item.isDeleted) ...[
                          const Divider(height: 22),
                          const Text('Позиция сейчас находится в удалённых.'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'История позиции',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (data.movements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Операций пока нет.')),
                  )
                else
                  ...data.movements.map(
                    (movement) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(_movementIcon(movement.type)),
                        title: Text(movement.type),
                        subtitle: Text(_movementDetails(movement).join('\n')),
                        trailing: Text(
                          _movementAmount(movement),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ItemDetailData {
  const _ItemDetailData({required this.item, required this.movements});

  final InventoryItem? item;
  final List<StockMovement> movements;
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTimeRange _range;
  late Future<List<ReportRow>> _rows;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day),
    );
    _reload();
  }

  void _reload() {
    _rows = WarehouseDatabase.instance.getReport(
      from: _range.start,
      to: _range.end,
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _reload();
    });
  }

  Future<void> _exportCsv() async {
    try {
      final rows = await WarehouseDatabase.instance.getReport(
        from: _range.start,
        to: _range.end,
      );
      final buffer = StringBuffer();
      buffer.writeln(
        'Позиция;Ед.;Начальный остаток;Приход;Выдача;Возврат;Списание;'
        'Корректировка;Конечный остаток',
      );
      for (final row in rows) {
        buffer.writeln([
          _csvCell(row.itemName),
          _csvCell(row.unit),
          row.opening,
          row.incoming,
          row.outgoing,
          row.returned,
          row.writeOff,
          row.adjustment,
          row.closing,
        ].join(';'));
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'otchet_${_fileDate(_range.start)}_${_fileDate(_range.end)}.csv';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString('\ufeff$buffer');

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Отчёт склада ${_formatDate(_range.start)} — '
              '${_formatDate(_range.end)}',
          text: 'Отчёт склада в CSV. Файл открывается в Excel.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать: ${_cleanError(error)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчёт за период'),
        actions: [
          IconButton(
            tooltip: 'Экспорт CSV',
            onPressed: _exportCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<ReportRow>>(
        future: _rows,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <ReportRow>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  '${_formatDate(_range.start)} — ${_formatDate(_range.end)}',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Начальный остаток считается на начало первого дня, '
                'конечный — на конец последнего дня.',
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                Text('Ошибка: ${snapshot.error}')
              else if (rows.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('За выбранный период данных нет.'),
                  ),
                )
              else
                ...rows.map(
                  (row) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.itemName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '${row.opening} → ${row.closing} ${row.unit}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ReportMetric(
                                label: 'Приход',
                                value: '+${row.incoming}',
                              ),
                              _ReportMetric(
                                label: 'Выдача',
                                value: '−${row.outgoing}',
                              ),
                              _ReportMetric(
                                label: 'Возврат',
                                value: '+${row.returned}',
                              ),
                              _ReportMetric(
                                label: 'Списание',
                                value: '−${row.writeOff}',
                              ),
                              _ReportMetric(
                                label: 'Корректировка',
                                value: row.adjustment > 0
                                    ? '+${row.adjustment}'
                                    : '${row.adjustment}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: snapshot.connectionState == ConnectionState.done
                    ? _exportCsv
                    : null,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Экспортировать CSV для Excel'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late Future<List<StockMovement>> _movements;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _movements = WarehouseDatabase.instance.getTrashMovements();
  }

  Future<void> _restore(StockMovement movement) async {
    try {
      await WarehouseDatabase.instance.restoreMovement(movement.id);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Операция восстановлена.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Корзина операций')),
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
            return const Center(child: Text('Корзина пуста.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: movements.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final movement = movements[index];
              final deleted = movement.deletedAt;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_movementIcon(movement.type)),
                title: Text(movement.itemName),
                subtitle: Text([
                  '${movement.type} • ${_formatDateTime(movement.createdAt)}',
                  if (deleted != null)
                    'Удалено: ${_formatDateTime(deleted)}',
                  ..._movementDetails(movement).skip(1),
                ].join('\n')),
                trailing: IconButton(
                  tooltip: 'Восстановить',
                  onPressed: () => _restore(movement),
                  icon: const Icon(Icons.restore),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DeletedItemsScreen extends StatefulWidget {
  const DeletedItemsScreen({super.key});

  @override
  State<DeletedItemsScreen> createState() => _DeletedItemsScreenState();
}

class _DeletedItemsScreenState extends State<DeletedItemsScreen> {
  late Future<List<InventoryItem>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = WarehouseDatabase.instance.getDeletedItems();
  }

  Future<void> _restore(InventoryItem item) async {
    try {
      await WarehouseDatabase.instance.restoreItem(item.id);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Позиция восстановлена.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Удалённые позиции')),
      body: FutureBuilder<List<InventoryItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('Удалённых позиций нет.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(item.name),
                subtitle: Text([
                  '${item.quantity} ${item.unit}',
                  if (item.category.isNotEmpty) item.category,
                  if (item.deletedAt != null)
                    'Удалено: ${_formatDateTime(item.deletedAt!)}',
                ].join('\n')),
                trailing: IconButton(
                  tooltip: 'Восстановить',
                  onPressed: () => _restore(item),
                  icon: const Icon(Icons.restore),
                ),
              );
            },
          );
        },
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

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
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

class EditItemDialog extends StatefulWidget {
  const EditItemDialog({super.key, required this.item});

  final InventoryItem item;

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _location;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _category = TextEditingController(text: widget.item.category);
    _unit = TextEditingController(text: widget.item.unit);
    _location = TextEditingController(text: widget.item.location);
    _note = TextEditingController(text: widget.item.note);
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать позицию'),
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
                TextFormField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Единица'),
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
                const SizedBox(height: 8),
                const Text(
                  'Остаток здесь не меняется — для него используются '
                  'приход, выдача, списание и инвентаризация.',
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
              EditItemRequest(
                name: _name.text.trim(),
                category: _category.text.trim(),
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

class EditItemRequest {
  const EditItemRequest({
    required this.name,
    required this.category,
    required this.unit,
    required this.location,
    required this.note,
  });

  final String name;
  final String category;
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
  final _department = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _quantity.dispose();
    _recipient.dispose();
    _department.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.action) {
      StockAction.incoming => 'Приход',
      StockAction.outgoing => 'Выдача',
      StockAction.returned => 'Возврат',
      StockAction.writeOff => 'Списание',
    };
    final needsPerson =
        widget.action == StockAction.outgoing ||
        widget.action == StockAction.returned;
    final personLabel = widget.action == StockAction.outgoing
        ? 'Кому выдано *'
        : 'От кого возвращено *';
    final decreasesStock =
        widget.action == StockAction.outgoing ||
        widget.action == StockAction.writeOff;

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
                    if (decreasesStock && parsed > widget.available) {
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
                      hintText: 'Фамилия, имя',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Заполни это поле';
                      }
                      return null;
                    },
                  ),
                if (widget.action == StockAction.outgoing)
                  TextFormField(
                    controller: _department,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Подразделение',
                      hintText: 'Например: 1 рота',
                    ),
                  ),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: widget.action == StockAction.writeOff
                        ? 'Причина списания *'
                        : 'Примечание',
                  ),
                  validator: (value) {
                    if (widget.action == StockAction.writeOff &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Укажи причину списания';
                    }
                    return null;
                  },
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
                department: widget.action == StockAction.outgoing
                    ? _department.text.trim()
                    : '',
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
    required this.department,
    required this.note,
  });

  final int quantity;
  final String recipient;
  final String department;
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
        department: request.department,
        note: request.note,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  Future<void> _delete(StockMovement movement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переместить в корзину?'),
        content: Text(
          '${movement.type}: ${movement.itemName}, '
          '${movement.quantity} ${movement.unit}.\n\n'
          'Остаток будет пересчитан. Операцию можно восстановить из корзины.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('В корзину'),
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
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const TrashScreen()),
    );
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История операций'),
        actions: [
          IconButton(
            tooltip: 'Корзина',
            onPressed: _openTrash,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
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
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_movementIcon(movement.type)),
                title: Text(movement.itemName),
                subtitle: Text(_movementDetails(movement).join('\n')),
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
                          child: Text('В корзину'),
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
  late final TextEditingController _department;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(text: '${widget.movement.quantity}');
    _recipient = TextEditingController(text: widget.movement.recipient);
    _department = TextEditingController(text: widget.movement.department);
    _note = TextEditingController(text: widget.movement.note);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _recipient.dispose();
    _department.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsPerson =
        widget.movement.type == 'Выдача' || widget.movement.type == 'Возврат';
    final isWriteOff = widget.movement.type == 'Списание';

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
              if (widget.movement.type == 'Выдача')
                TextFormField(
                  controller: _department,
                  decoration: const InputDecoration(
                    labelText: 'Подразделение',
                  ),
                ),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isWriteOff ? 'Причина списания *' : 'Примечание',
                ),
                validator: (value) {
                  if (isWriteOff &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Укажи причину списания';
                  }
                  return null;
                },
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
                department: widget.movement.type == 'Выдача'
                    ? _department.text.trim()
                    : '',
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
    required this.department,
    required this.note,
  });

  final int quantity;
  final String recipient;
  final String department;
  final String note;
}

String _formatDateTime(DateTime value) {
  final date = value.toLocal();
  return '${_two(date.day)}.${_two(date.month)}.${date.year} '
      '${_two(date.hour)}:${_two(date.minute)}';
}

String _formatDate(DateTime value) {
  final date = value.toLocal();
  return '${_two(date.day)}.${_two(date.month)}.${date.year}';
}

String _fileDate(DateTime value) {
  final date = value.toLocal();
  return '${date.year}${_two(date.month)}${_two(date.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

IconData _movementIcon(String type) {
  return switch (type) {
    'Выдача' => Icons.remove_circle_outline,
    'Возврат' => Icons.undo,
    'Списание' => Icons.delete_sweep_outlined,
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

List<String> _movementDetails(StockMovement movement) {
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
  if (movement.department.trim().isNotEmpty) {
    parts.add('Подразделение: ${movement.department.trim()}');
  }
  if (movement.note.isNotEmpty) parts.add(movement.note);
  return parts;
}

String _csvCell(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

String _cleanError(Object error) {
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst('Invalid argument: ', '');
}
