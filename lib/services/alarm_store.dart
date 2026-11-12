import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/alarm_state.dart';
import 'alarm_storage_platform.dart';

/// Giao diện lưu trữ bền vững cho danh sách `AlarmRecord` (tách biệt khỏi Schema v7).
abstract class AlarmStore {
  Future<List<AlarmRecord>> loadAll();
  Future<void> saveAll(List<AlarmRecord> records);
  Future<void> clearAll();
}

/// Kho lưu trữ JSON trên thiết bị (Application Support Directory trên Android/Desktop)
/// hoặc `localStorage` trên Web Preview.
class LocalAlarmStore implements AlarmStore {
  final bool useMemoryOnly;
  static const String _fileName = 'exampilot_alarms_v1.json';
  List<AlarmRecord>? _memoryFallback;

  LocalAlarmStore({this.useMemoryOnly = false});

  @override
  Future<List<AlarmRecord>> loadAll() async {
    if (useMemoryOnly) {
      return List<AlarmRecord>.from(_memoryFallback ?? const []);
    }

    String? raw;
    if (kIsWeb) {
      raw = WebAlarmStorage.loadRawJson();
    } else {
      try {
        final file = await _resolveFile();
        if (await file.exists()) {
          raw = await file.readAsString();
        }
      } catch (_) {
        raw = WebAlarmStorage.loadRawJson();
      }
    }

    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = <AlarmRecord>[];
      for (final item in decoded) {
        if (item is Map) {
          final parsed = AlarmRecord.fromMap(Map<String, dynamic>.from(item));
          if (parsed.alarmKey.isNotEmpty) {
            records.add(parsed);
          }
        }
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveAll(List<AlarmRecord> records) async {
    if (useMemoryOnly) {
      _memoryFallback = List<AlarmRecord>.from(records);
      return;
    }

    final encoded = jsonEncode(records.map((r) => r.toMap()).toList());
    if (kIsWeb) {
      WebAlarmStorage.saveRawJson(encoded);
      return;
    }

    try {
      final file = await _resolveFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    } catch (_) {
      WebAlarmStorage.saveRawJson(encoded);
    }
  }

  @override
  Future<void> clearAll() async {
    if (useMemoryOnly) {
      _memoryFallback = [];
      return;
    }

    if (kIsWeb) {
      WebAlarmStorage.clear();
      return;
    }

    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    WebAlarmStorage.clear();
  }

  Future<File> _resolveFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }
}
