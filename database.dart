import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.location,
    required this.note,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String category;
  final int quantity;
  final String unit;
  final String location;
  final String note;
  final DateTime createdAt;

  factory InventoryItem.fromMap(Map<String, Object?> map) {
    return InventoryItem(
      id: map['id'] as int,
      name: map['name'] as String,
      category: map['category'] as String,
      quantity: map['quantity'] as int,
      unit: map['unit'] as String,
      location: map['location'] as String,
      note: map['note'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.type,
    required this.quantity,
    required this.recipient,
    required this.note,
    required this.createdAt,
  });

  final int id;
  final int itemId;
  final String itemName;
  final String unit;
  final String type;
  final int quantity;
  final String recipient;
  final String note;
  final DateTime createdAt;

  factory StockMovement.fromMap(Map<String, Object?> map) {
    return StockMovement(
      id: map['id'] as int,
      itemId: map['item_id'] as int,
      itemName: map['item_name'] as String,
      unit: map['unit'] as String? ?? '',
      type: map['type'] as String,
      quantity: map['quantity'] as int,
      recipient: map['recipient'] as String? ?? '',
      note: map['note'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class WarehouseDatabase {
  WarehouseDatabase._();

  static final WarehouseDatabase instance = WarehouseDatabase._();

  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null) return current;

    final dbPath = p.join(await getDatabasesPath(), 'warehouse.db');
    final opened = await openDatabase(
      dbPath,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE inventory_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT '',
            quantity INTEGER NOT NULL DEFAULT 0,
            unit TEXT NOT NULL DEFAULT 'шт.',
            location TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE stock_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            recipient TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY(item_id) REFERENCES inventory_items(id)
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_movements_item_id ON stock_movements(item_id)',
        );
        await db.execute(
          'CREATE INDEX idx_items_name ON inventory_items(name)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE stock_movements "
            "ADD COLUMN recipient TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );

    _database = opened;
    return opened;
  }

  Future<List<InventoryItem>> getItems({String query = ''}) async {
    final db = await database;
    final trimmed = query.trim();

    final rows = trimmed.isEmpty
        ? await db.query('inventory_items', orderBy: 'name COLLATE NOCASE ASC')
        : await db.query(
            'inventory_items',
            where: 'name LIKE ? OR category LIKE ? OR location LIKE ?',
            whereArgs: ['%$trimmed%', '%$trimmed%', '%$trimmed%'],
            orderBy: 'name COLLATE NOCASE ASC',
          );

    return rows.map(InventoryItem.fromMap).toList(growable: false);
  }

  Future<int> addItem({
    required String name,
    required String category,
    required int initialQuantity,
    required String unit,
    required String location,
    required String note,
  }) async {
    if (initialQuantity < 0) {
      throw ArgumentError('Начальный остаток не может быть отрицательным.');
    }

    final db = await database;
    final now = DateTime.now().toIso8601String();

    return db.transaction((txn) async {
      final itemId = await txn.insert('inventory_items', {
        'name': name.trim(),
        'category': category.trim(),
        'quantity': initialQuantity,
        'unit': unit.trim().isEmpty ? 'шт.' : unit.trim(),
        'location': location.trim(),
        'note': note.trim(),
        'created_at': now,
      });

      if (initialQuantity > 0) {
        await txn.insert('stock_movements', {
          'item_id': itemId,
          'type': 'Начальный остаток',
          'quantity': initialQuantity,
          'recipient': '',
          'note': '',
          'created_at': now,
        });
      }

      return itemId;
    });
  }

  Future<void> changeStock({
    required int itemId,
    required int delta,
    required String type,
    String recipient = '',
    String note = '',
  }) async {
    if (delta == 0) return;

    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_items',
        columns: ['quantity'],
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Позиция не найдена.');
      }

      final current = rows.first['quantity'] as int;
      final next = current + delta;
      if (next < 0) {
        throw StateError('Недостаточный остаток. Сейчас на складе: $current.');
      }

      await txn.update(
        'inventory_items',
        {'quantity': next},
        where: 'id = ?',
        whereArgs: [itemId],
      );

      await txn.insert('stock_movements', {
        'item_id': itemId,
        'type': type,
        'quantity': delta.abs(),
        'recipient': recipient.trim(),
        'note': note.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<StockMovement>> getMovements({String? type}) async {
    final db = await database;
    final where = type == null ? '' : 'WHERE m.type = ?';
    final args = type == null ? <Object?>[] : <Object?>[type];

    final rows = await db.rawQuery('''
      SELECT
        m.id,
        m.item_id,
        i.name AS item_name,
        i.unit AS unit,
        m.type,
        m.quantity,
        m.recipient,
        m.note,
        m.created_at
      FROM stock_movements m
      JOIN inventory_items i ON i.id = m.item_id
      $where
      ORDER BY m.created_at DESC, m.id DESC
    ''', args);

    return rows.map(StockMovement.fromMap).toList(growable: false);
  }

  Future<List<StockMovement>> getIssuedMovements() {
    return getMovements(type: 'Выдача');
  }
}
