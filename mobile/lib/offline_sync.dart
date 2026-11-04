import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// SQLite-backed record cache and durable outbox for Amar Hisab sync.
class OfflineSyncStore {
  OfflineSyncStore._();
  static final OfflineSyncStore instance = OfflineSyncStore._();

  static const _uuid = Uuid();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      p.join(root, 'amar_hisab_offline.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_records (
            collection TEXT NOT NULL,
            record_id TEXT NOT NULL,
            data TEXT,
            version INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            has_conflict INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(collection, record_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_operations (
            operation_id TEXT PRIMARY KEY,
            collection TEXT NOT NULL,
            record_id TEXT NOT NULL,
            operation_type TEXT NOT NULL CHECK(operation_type IN ('upsert','delete')),
            base_version INTEGER NOT NULL,
            data TEXT,
            created_at TEXT NOT NULL,
            UNIQUE(collection, record_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.insert('sync_metadata', {'key': 'cursor', 'value': '0'});
      },
    );
    return _database!;
  }

  String newRecordId() => _uuid.v4();

  Future<List<Map<String, dynamic>>> records(String collection) async {
    final db = await database;
    final rows = await db.query('local_records',
      where: 'collection = ? AND is_deleted = 0 AND data IS NOT NULL',
      whereArgs: [collection], orderBy: 'updated_at DESC');
    return rows.map((row) => jsonDecode(row['data']! as String) as Map<String, dynamic>).toList();
  }


  Future<void> cacheRemoteRecords(String collection, List<dynamic> items) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final raw in items) {
        if (raw is! Map) {
          continue;
        }
        final data = Map<String, dynamic>.from(raw);
        final id = (data['_syncId'] ?? data['id'] ?? '').toString();
        if (id.isEmpty) continue;
        data['_syncId'] = id;
        final existing = await txn.query('local_records',
          where: 'collection = ? AND record_id = ?', whereArgs: [collection, id], limit: 1);
        if (existing.isNotEmpty &&
            (existing.first['is_dirty'] == 1 || existing.first['has_conflict'] == 1)) continue;
        await txn.insert('local_records', {
          'collection': collection, 'record_id': id, 'data': jsonEncode(data),
          'version': existing.isEmpty ? 0 : existing.first['version'],
          'is_deleted': 0, 'is_dirty': 0, 'has_conflict': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> save(String collection, Map<String, dynamic> input) async {
    final db = await database;
    await db.transaction((txn) async {
      final data = Map<String, dynamic>.from(input);
      final id = (data['_syncId'] ?? '').toString().trim().isNotEmpty
          ? data['_syncId'].toString() : newRecordId();
      data['_syncId'] = id;
      final now = DateTime.now().toUtc().toIso8601String();
      final existing = await txn.query('local_records',
        where: 'collection = ? AND record_id = ?', whereArgs: [collection, id], limit: 1);
      final version = existing.isEmpty ? 0 : existing.first['version'] as int;
      await txn.insert('local_records', {
        'collection': collection, 'record_id': id, 'data': jsonEncode(data),
        'version': version, 'is_deleted': 0, 'is_dirty': 1,
        'has_conflict': 0, 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final queued = await txn.query('pending_operations',
        where: 'collection = ? AND record_id = ?', whereArgs: [collection, id], limit: 1);
      final operationId = queued.isEmpty ? _uuid.v4() : queued.first['operation_id'] as String;
      final baseVersion = queued.isEmpty ? version : queued.first['base_version'] as int;
      await txn.insert('pending_operations', {
        'operation_id': operationId, 'collection': collection, 'record_id': id,
        'operation_type': 'upsert', 'base_version': baseVersion,
        'data': jsonEncode(data), 'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> delete(String collection, String recordId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('local_records',
        where: 'collection = ? AND record_id = ?', whereArgs: [collection, recordId], limit: 1);
      if (rows.isEmpty) return;
      final now = DateTime.now().toUtc().toIso8601String();
      final queued = await txn.query('pending_operations',
        where: 'collection = ? AND record_id = ?', whereArgs: [collection, recordId], limit: 1);
      final operationId = queued.isEmpty ? _uuid.v4() : queued.first['operation_id'] as String;
      final baseVersion = queued.isEmpty ? rows.first['version'] as int : queued.first['base_version'] as int;
      await txn.update('local_records', {
        'is_deleted': 1, 'is_dirty': 1, 'updated_at': now,
      }, where: 'collection = ? AND record_id = ?', whereArgs: [collection, recordId]);
      await txn.insert('pending_operations', {
        'operation_id': operationId, 'collection': collection, 'record_id': recordId,
        'operation_type': 'delete', 'base_version': baseVersion,
        'data': null, 'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, Object?>>> pending({int limit = 200}) async {
    final db = await database;
    return db.query('pending_operations', orderBy: 'created_at ASC', limit: limit.clamp(1, 200));
  }

  Future<int> get cursor async {
    final db = await database;
    final rows = await db.query('sync_metadata', where: 'key = ?', whereArgs: ['cursor'], limit: 1);
    return rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String) ?? 0;
  }

  Future<void> applyPushResults(List<dynamic> results) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['operationId']?.toString();
        if (id == null) continue;
        final ops = await txn.query('pending_operations',
          where: 'operation_id = ?', whereArgs: [id], limit: 1);
        if (ops.isEmpty) continue;
        final op = ops.first;
        if (item['status'] == 'accepted') {
          await txn.delete('pending_operations', where: 'operation_id = ?', whereArgs: [id]);
          await txn.update('local_records', {
            'version': item['version'], 'is_dirty': 0, 'has_conflict': 0,
          }, where: 'collection = ? AND record_id = ?',
            whereArgs: [op['collection'], op['record_id']]);
        } else if (item['status'] == 'conflict') {
          await txn.update('local_records', {'has_conflict': 1},
            where: 'collection = ? AND record_id = ?',
            whereArgs: [op['collection'], op['record_id']]);
        }
      }
    });
  }

  Future<void> applyRemoteEvents(List<dynamic> events, int nextCursor) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final event in events) {
        if (event is! Map<String, dynamic>) continue;
        final collection = event['collection']?.toString();
        final id = event['recordId']?.toString();
        if (collection == null || id == null) continue;
        final local = await txn.query('local_records',
          where: 'collection = ? AND record_id = ?', whereArgs: [collection, id], limit: 1);
        if (local.isNotEmpty && (local.first['is_dirty'] == 1 || local.first['has_conflict'] == 1)) {
          continue; // Never overwrite unsynced local edits.
        }
        final deleted = event['operation'] == 'delete';
        final data = event['data'];
        await txn.insert('local_records', {
          'collection': collection, 'record_id': id,
          'data': deleted || data == null ? null : jsonEncode(data),
          'version': event['version'] ?? 0, 'is_deleted': deleted ? 1 : 0,
          'is_dirty': 0, 'has_conflict': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('sync_metadata', {'key': 'cursor', 'value': '$nextCursor'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<int> pendingCount() async => (await database).rawQuery(
    'SELECT COUNT(*) AS count FROM pending_operations').then((r) => Sqflite.firstIntValue(r) ?? 0);

  Future<void> close() async { await _database?.close(); _database = null; }
}

/// Uses the authenticated session cookie already held by the app.
class OfflineSyncEngine {
  OfflineSyncEngine({
    required this.baseUrl,
    required this.sessionCookie,
    OfflineSyncStore? store,
  }) : store = store ?? OfflineSyncStore.instance;

  final String baseUrl;
  final String sessionCookie;
  final OfflineSyncStore store;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  bool _running = false;

  Future<Map<String, dynamic>> _request(String method, String path, [Object? body]) async {
    final uri = Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');
    final request = method == 'POST' ? await _client.postUrl(uri) : await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.cookieHeader, sessionCookie);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 25));
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(decoded is Map ? (decoded['error']?.toString() ?? 'Sync request failed') : 'Sync request failed',
        uri: uri);
    }
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid sync response');
    return decoded;
  }

  Future<void> syncOnce() async {
    if (_running) return;
    _running = true;
    try {
      // Pull first so a newly cached record learns its authoritative server version
      // before a local edit is pushed.
      var cursor = await store.cursor;
      for (var page = 0; page < 10; page++) {
        final pulled = await _request('GET', '/sync/pull?cursor=$cursor&limit=500');
        final events = (pulled['events'] as List?) ?? const [];
        final next = pulled['nextCursor'] is int ? pulled['nextCursor'] as int : cursor;
        await store.applyRemoteEvents(events, next);
        cursor = next;
        if (pulled['hasMore'] != true || events.isEmpty) break;
      }

      final operations = await store.pending();
      if (operations.isNotEmpty) {
        final payload = operations.map((op) {
          final item = <String, dynamic>{
            'operationId': op['operation_id'], 'collection': op['collection'],
            'recordId': op['record_id'], 'type': op['operation_type'],
            'baseVersion': op['base_version'],
          };
          if (op['operation_type'] == 'upsert') item['data'] = jsonDecode(op['data']! as String);
          return item;
        }).toList();
        final pushed = await _request('POST', '/sync/push', {'operations': payload});
        await store.applyPushResults((pushed['results'] as List?) ?? const []);
      }

      cursor = await store.cursor;
      for (var page = 0; page < 10; page++) {
        final pulled = await _request('GET', '/sync/pull?cursor=$cursor&limit=500');
        final events = (pulled['events'] as List?) ?? const [];
        final next = pulled['nextCursor'] is int ? pulled['nextCursor'] as int : cursor;
        await store.applyRemoteEvents(events, next);
        cursor = next;
        if (pulled['hasMore'] != true || events.isEmpty) break;
      }
    } finally {
      _running = false;
    }
  }

  void dispose() => _client.close(force: true);
}
