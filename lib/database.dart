import 'dart:io';

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
    required this.delta,
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
  final int delta;
  final String recipient;
  final String note;
  final DateTime createdAt;

  bool get canEdit => type == 'Приход' || type == 'Выдача' || type == 'Возврат';

  factory StockMovement.fromMap(Map<String, Object?> map) {
    return StockMovement(
      id: map['id'] as int,
      itemId: map['item_id'] as int,
      itemName: map['item_name'] as String,
      unit: map['unit'] as String? ?? '',
      type: map['type'] as String,
      quantity: map['quantity'] as int,
      delta: map['delta'] as int? ?? 0,
      recipient: map['recipient'] as String? ?? '',
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class WarehouseDatabase {
  WarehouseDatabase._();

  static final WarehouseDatabase instance = WarehouseDatabase._();

  Database? _database;

  Future<String> get databasePath async {
    return p.join(await getDatabasesPath(), 'warehouse.db');
  }

  Future<Database> get database async {
    final current = _database;
    if (current != null) return current;

    final opened = await openDatabase(
      await databasePath,
      version: 3,
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
            delta INTEGER NOT NULL DEFAULT 0,
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
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE stock_movements '
            'ADD COLUMN delta INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('''
            UPDATE stock_movements
            SET delta = CASE
              WHEN type = 'Выдача' THEN -quantity
              ELSE quantity
            END
          ''');
        }
      },
    );

    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
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
          'delta': initialQuantity,
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
      final current = await _getCurrentQuantity(txn, itemId);
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
        'delta': delta,
        'recipient': recipient.trim(),
        'note': note.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> setInventoryQuantity({
    required int itemId,
    required int actualQuantity,
    String note = '',
  }) async {
    if (actualQuantity < 0) {
      throw ArgumentError('Фактический остаток не может быть отрицательным.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final current = await _getCurrentQuantity(txn, itemId);
      final delta = actualQuantity - current;
      final details = 'Было: $current → Факт: $actualQuantity';
      final fullNote = note.trim().isEmpty ? details : '$details\n${note.trim()}';

      await txn.update(
        'inventory_items',
        {'quantity': actualQuantity},
        where: 'id = ?',
        whereArgs: [itemId],
      );

      await txn.insert('stock_movements', {
        'item_id': itemId,
        'type': 'Инвентаризация',
        'quantity': delta.abs(),
        'delta': delta,
        'recipient': '',
        'note': fullNote,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> editMovement({
    required int movementId,
    required int quantity,
    required String recipient,
    required String note,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Количество должно быть больше нуля.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_movements',
        where: 'id = ?',
        whereArgs: [movementId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Операция не найдена.');

      final row = rows.first;
      final type = row['type'] as String;
      if (type != 'Приход' && type != 'Выдача' && type != 'Возврат') {
        throw StateError('Эту операцию нельзя редактировать.');
      }

      final itemId = row['item_id'] as int;
      final oldDelta = row['delta'] as int;
      final newDelta = type == 'Выдача' ? -quantity : quantity;
      final current = await _getCurrentQuantity(txn, itemId);
      final next = current + (newDelta - oldDelta);
      if (next < 0) {
        throw StateError(
          'После исправления остаток стал бы отрицательным. Текущий остаток: $current.',
        );
      }

      await txn.update(
        'inventory_items',
        {'quantity': next},
        where: 'id = ?',
        whereArgs: [itemId],
      );

      await txn.update(
        'stock_movements',
        {
          'quantity': quantity,
          'delta': newDelta,
          'recipient': recipient.trim(),
          'note': note.trim(),
        },
        where: 'id = ?',
        whereArgs: [movementId],
      );
    });
  }

  Future<void> deleteMovement(int movementId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_movements',
        where: 'id = ?',
        whereArgs: [movementId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Операция не найдена.');

      final row = rows.first;
      final itemId = row['item_id'] as int;
      final oldDelta = row['delta'] as int;
      final current = await _getCurrentQuantity(txn, itemId);
      final next = current - oldDelta;
      if (next < 0) {
        throw StateError(
          'Нельзя удалить эту операцию: остаток стал бы отрицательным.',
        );
      }

      await txn.update(
        'inventory_items',
        {'quantity': next},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      await txn.delete(
        'stock_movements',
        where: 'id = ?',
        whereArgs: [movementId],
      );
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
        m.delta,
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

  Future<File> createBackupFile(String targetPath) async {
    await database;
    await close();

    final source = File(await databasePath);
    if (!await source.exists()) {
      throw StateError('Файл базы данных не найден.');
    }

    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    return source.copy(targetPath);
  }

  Future<void> restoreBackup(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Файл резервной копии не найден.');
    }

    Database? checkDb;
    try {
      checkDb = await openDatabase(sourcePath, readOnly: true);
      final rows = await checkDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name IN ('inventory_items', 'stock_movements')",
      );
      final names = rows.map((row) => row['name']).toSet();
      if (!names.contains('inventory_items') ||
          !names.contains('stock_movements')) {
        throw StateError('Это не резервная копия приложения «Склад».');
      }
    } finally {
      await checkDb?.close();
    }

    await close();
    final destinationPath = await databasePath;
    final destination = File(destinationPath);
    if (await destination.exists()) {
      await destination.delete();
    }
    await source.copy(destinationPath);

    // Открытие запускает миграцию, если резервная копия старой версии.
    await database;
  }

  Future<int> _getCurrentQuantity(DatabaseExecutor txn, int itemId) async {
    final rows = await txn.query(
      'inventory_items',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Позиция не найдена.');
    return rows.first['quantity'] as int;
  }
}
