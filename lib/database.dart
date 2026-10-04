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
    this.isDeleted = false,
    this.deletedAt,
  });

  final int id;
  final String name;
  final String category;
  final int quantity;
  final String unit;
  final String location;
  final String note;
  final DateTime createdAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  factory InventoryItem.fromMap(Map<String, Object?> map) {
    final deletedAtRaw = map['deleted_at'] as String?;
    return InventoryItem(
      id: map['id'] as int,
      name: map['name'] as String,
      category: map['category'] as String? ?? '',
      quantity: map['quantity'] as int,
      unit: map['unit'] as String? ?? 'шт.',
      location: map['location'] as String? ?? '',
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: deletedAtRaw == null ? null : DateTime.parse(deletedAtRaw),
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
    required this.department,
    required this.note,
    required this.createdAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  final int id;
  final int itemId;
  final String itemName;
  final String unit;
  final String type;
  final int quantity;
  final int delta;
  final String recipient;
  final String department;
  final String note;
  final DateTime createdAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  bool get canEdit =>
      type == 'Приход' ||
      type == 'Выдача' ||
      type == 'Возврат' ||
      type == 'Списание';

  factory StockMovement.fromMap(Map<String, Object?> map) {
    final deletedAtRaw = map['deleted_at'] as String?;
    return StockMovement(
      id: map['id'] as int,
      itemId: map['item_id'] as int,
      itemName: map['item_name'] as String,
      unit: map['unit'] as String? ?? '',
      type: map['type'] as String,
      quantity: map['quantity'] as int,
      delta: map['delta'] as int? ?? 0,
      recipient: map['recipient'] as String? ?? '',
      department: map['department'] as String? ?? '',
      note: map['note'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: deletedAtRaw == null ? null : DateTime.parse(deletedAtRaw),
    );
  }
}

class ReportRow {
  const ReportRow({
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.opening,
    required this.incoming,
    required this.outgoing,
    required this.returned,
    required this.writeOff,
    required this.adjustment,
    required this.closing,
  });

  final int itemId;
  final String itemName;
  final String unit;
  final int opening;
  final int incoming;
  final int outgoing;
  final int returned;
  final int writeOff;
  final int adjustment;
  final int closing;

  bool get hasData =>
      opening != 0 ||
      incoming != 0 ||
      outgoing != 0 ||
      returned != 0 ||
      writeOff != 0 ||
      adjustment != 0 ||
      closing != 0;

  factory ReportRow.fromMap(Map<String, Object?> map) {
    int asInt(String key) => (map[key] as num?)?.toInt() ?? 0;
    return ReportRow(
      itemId: asInt('item_id'),
      itemName: map['item_name'] as String,
      unit: map['unit'] as String? ?? '',
      opening: asInt('opening'),
      incoming: asInt('incoming'),
      outgoing: asInt('outgoing'),
      returned: asInt('returned'),
      writeOff: asInt('write_off'),
      adjustment: asInt('adjustment'),
      closing: asInt('closing'),
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
      version: 4,
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
            created_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT
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
            department TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT,
            FOREIGN KEY(item_id) REFERENCES inventory_items(id)
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_movements_item_id ON stock_movements(item_id)',
        );
        await db.execute(
          'CREATE INDEX idx_movements_created_at ON stock_movements(created_at)',
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
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE stock_movements "
            "ADD COLUMN department TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE stock_movements '
            'ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE stock_movements ADD COLUMN deleted_at TEXT',
          );
          await db.execute(
            'ALTER TABLE inventory_items '
            'ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE inventory_items ADD COLUMN deleted_at TEXT',
          );
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
        ? await db.query(
            'inventory_items',
            where: 'is_deleted = 0',
            orderBy: 'name COLLATE NOCASE ASC',
          )
        : await db.query(
            'inventory_items',
            where:
                'is_deleted = 0 AND '
                '(name LIKE ? OR category LIKE ? OR location LIKE ?)',
            whereArgs: ['%$trimmed%', '%$trimmed%', '%$trimmed%'],
            orderBy: 'name COLLATE NOCASE ASC',
          );

    return rows.map(InventoryItem.fromMap).toList(growable: false);
  }

  Future<List<InventoryItem>> getDeletedItems() async {
    final db = await database;
    final rows = await db.query(
      'inventory_items',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(InventoryItem.fromMap).toList(growable: false);
  }

  Future<InventoryItem?> getItem(int itemId, {bool includeDeleted = true}) async {
    final db = await database;
    final rows = await db.query(
      'inventory_items',
      where: includeDeleted ? 'id = ?' : 'id = ? AND is_deleted = 0',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InventoryItem.fromMap(rows.first);
  }

  Future<int> addItem({
    required String name,
    required String category,
    required int initialQuantity,
    required String unit,
    required String location,
    required String note,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Наименование не может быть пустым.');
    }
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
        'is_deleted': 0,
      });

      if (initialQuantity > 0) {
        await txn.insert('stock_movements', {
          'item_id': itemId,
          'type': 'Начальный остаток',
          'quantity': initialQuantity,
          'delta': initialQuantity,
          'recipient': '',
          'department': '',
          'note': '',
          'created_at': now,
          'is_deleted': 0,
        });
      }

      return itemId;
    });
  }

  Future<void> updateItem({
    required int itemId,
    required String name,
    required String category,
    required String unit,
    required String location,
    required String note,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Наименование не может быть пустым.');
    }
    final db = await database;
    final changed = await db.update(
      'inventory_items',
      {
        'name': name.trim(),
        'category': category.trim(),
        'unit': unit.trim().isEmpty ? 'шт.' : unit.trim(),
        'location': location.trim(),
        'note': note.trim(),
      },
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [itemId],
    );
    if (changed == 0) throw StateError('Позиция не найдена.');
  }

  Future<void> deleteItem(int itemId) async {
    final db = await database;
    final changed = await db.update(
      'inventory_items',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [itemId],
    );
    if (changed == 0) throw StateError('Позиция не найдена.');
  }

  Future<void> restoreItem(int itemId) async {
    final db = await database;
    final changed = await db.update(
      'inventory_items',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ? AND is_deleted = 1',
      whereArgs: [itemId],
    );
    if (changed == 0) throw StateError('Удалённая позиция не найдена.');
  }

  Future<void> changeStock({
    required int itemId,
    required int delta,
    required String type,
    String recipient = '',
    String department = '',
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
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [itemId],
      );

      await txn.insert('stock_movements', {
        'item_id': itemId,
        'type': type,
        'quantity': delta.abs(),
        'delta': delta,
        'recipient': recipient.trim(),
        'department': department.trim(),
        'note': note.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'is_deleted': 0,
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
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [itemId],
      );

      await txn.insert('stock_movements', {
        'item_id': itemId,
        'type': 'Инвентаризация',
        'quantity': delta.abs(),
        'delta': delta,
        'recipient': '',
        'department': '',
        'note': fullNote,
        'created_at': DateTime.now().toIso8601String(),
        'is_deleted': 0,
      });
    });
  }

  Future<void> editMovement({
    required int movementId,
    required int quantity,
    required String recipient,
    required String department,
    required String note,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Количество должно быть больше нуля.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_movements',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [movementId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Операция не найдена.');

      final row = rows.first;
      final type = row['type'] as String;
      if (type != 'Приход' &&
          type != 'Выдача' &&
          type != 'Возврат' &&
          type != 'Списание') {
        throw StateError('Эту операцию нельзя редактировать.');
      }

      final itemId = row['item_id'] as int;
      final oldDelta = row['delta'] as int;
      final isDecrease = type == 'Выдача' || type == 'Списание';
      final newDelta = isDecrease ? -quantity : quantity;
      final current = await _getCurrentQuantity(txn, itemId, allowDeleted: true);
      final next = current + (newDelta - oldDelta);
      if (next < 0) {
        throw StateError(
          'После исправления остаток стал бы отрицательным. '
          'Текущий остаток: $current.',
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
          'department': department.trim(),
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
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [movementId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Операция не найдена.');

      final row = rows.first;
      final itemId = row['item_id'] as int;
      final oldDelta = row['delta'] as int;
      final current = await _getCurrentQuantity(txn, itemId, allowDeleted: true);
      final next = current - oldDelta;
      if (next < 0) {
        throw StateError(
          'Нельзя убрать эту операцию в корзину: остаток стал бы отрицательным.',
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
          'is_deleted': 1,
          'deleted_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [movementId],
      );
    });
  }

  Future<void> restoreMovement(int movementId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_movements',
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [movementId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Операция в корзине не найдена.');

      final row = rows.first;
      final itemId = row['item_id'] as int;
      final delta = row['delta'] as int;
      final current = await _getCurrentQuantity(txn, itemId, allowDeleted: true);
      final next = current + delta;
      if (next < 0) {
        throw StateError(
          'Нельзя восстановить операцию: остаток стал бы отрицательным.',
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
        {'is_deleted': 0, 'deleted_at': null},
        where: 'id = ?',
        whereArgs: [movementId],
      );
    });
  }

  Future<List<StockMovement>> getMovements({
    String? type,
    int? itemId,
    bool deletedOnly = false,
  }) async {
    final db = await database;
    final conditions = <String>[
      deletedOnly ? 'm.is_deleted = 1' : 'm.is_deleted = 0',
    ];
    final args = <Object?>[];

    if (type != null) {
      conditions.add('m.type = ?');
      args.add(type);
    }
    if (itemId != null) {
      conditions.add('m.item_id = ?');
      args.add(itemId);
    }

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
        m.department,
        m.note,
        m.created_at,
        m.is_deleted,
        m.deleted_at
      FROM stock_movements m
      JOIN inventory_items i ON i.id = m.item_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY m.created_at DESC, m.id DESC
    ''', args);

    return rows.map(StockMovement.fromMap).toList(growable: false);
  }

  Future<List<StockMovement>> getIssuedMovements({
    String recipient = '',
    String item = '',
    String department = '',
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await database;
    final conditions = <String>[
      "m.type = 'Выдача'",
      'm.is_deleted = 0',
    ];
    final args = <Object?>[];

    if (recipient.trim().isNotEmpty) {
      conditions.add('m.recipient LIKE ?');
      args.add('%${recipient.trim()}%');
    }
    if (item.trim().isNotEmpty) {
      conditions.add('i.name LIKE ?');
      args.add('%${item.trim()}%');
    }
    if (department.trim().isNotEmpty) {
      conditions.add('m.department LIKE ?');
      args.add('%${department.trim()}%');
    }
    if (from != null) {
      final start = DateTime(from.year, from.month, from.day);
      conditions.add('m.created_at >= ?');
      args.add(start.toIso8601String());
    }
    if (to != null) {
      final endExclusive = DateTime(to.year, to.month, to.day + 1);
      conditions.add('m.created_at < ?');
      args.add(endExclusive.toIso8601String());
    }

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
        m.department,
        m.note,
        m.created_at,
        m.is_deleted,
        m.deleted_at
      FROM stock_movements m
      JOIN inventory_items i ON i.id = m.item_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY m.created_at DESC, m.id DESC
    ''', args);

    return rows.map(StockMovement.fromMap).toList(growable: false);
  }

  Future<List<StockMovement>> getTrashMovements() {
    return getMovements(deletedOnly: true);
  }

  Future<List<ReportRow>> getReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await database;
    final start = DateTime(from.year, from.month, from.day).toIso8601String();
    final endExclusive =
        DateTime(to.year, to.month, to.day + 1).toIso8601String();

    final rows = await db.rawQuery('''
      SELECT
        i.id AS item_id,
        i.name AS item_name,
        i.unit AS unit,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at < ? THEN m.delta ELSE 0 END), 0)
          AS opening,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at >= ? AND m.created_at < ?
            AND m.type IN ('Приход', 'Начальный остаток')
          THEN m.quantity ELSE 0 END), 0) AS incoming,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at >= ? AND m.created_at < ?
            AND m.type = 'Выдача'
          THEN m.quantity ELSE 0 END), 0) AS outgoing,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at >= ? AND m.created_at < ?
            AND m.type = 'Возврат'
          THEN m.quantity ELSE 0 END), 0) AS returned,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at >= ? AND m.created_at < ?
            AND m.type = 'Списание'
          THEN m.quantity ELSE 0 END), 0) AS write_off,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at >= ? AND m.created_at < ?
            AND m.type = 'Инвентаризация'
          THEN m.delta ELSE 0 END), 0) AS adjustment,
        COALESCE(SUM(CASE
          WHEN m.is_deleted = 0 AND m.created_at < ? THEN m.delta ELSE 0 END), 0)
          AS closing
      FROM inventory_items i
      LEFT JOIN stock_movements m ON m.item_id = i.id
      GROUP BY i.id, i.name, i.unit
      ORDER BY i.name COLLATE NOCASE ASC
    ''', [
      start,
      start,
      endExclusive,
      start,
      endExclusive,
      start,
      endExclusive,
      start,
      endExclusive,
      start,
      endExclusive,
      endExclusive,
    ]);

    return rows
        .map(ReportRow.fromMap)
        .where((row) => row.hasData)
        .toList(growable: false);
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

    await database;
  }

  Future<int> _getCurrentQuantity(
    DatabaseExecutor txn,
    int itemId, {
    bool allowDeleted = false,
  }) async {
    final rows = await txn.query(
      'inventory_items',
      columns: ['quantity'],
      where: allowDeleted ? 'id = ?' : 'id = ? AND is_deleted = 0',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Позиция не найдена.');
    return rows.first['quantity'] as int;
  }
}
