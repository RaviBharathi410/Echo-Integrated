import 'dart:convert';
import 'dart:io';

import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Persistence boundary for completed and historical screening sessions.
abstract interface class SessionRepository {
  Future<bool> saveSession(HearingSessionRecord record);
  Future<HearingSessionRecord?> getSession(String sessionId);
  Future<List<HearingSessionRecord>> loadAllSessions();
  Future<void> deleteAllSessions();
}

/// JSON file repository reading/writing `echo_sessions/session_<id>.json`.
///
/// Uses `getApplicationSupportDirectory()` (which maps to Android `context.filesDir`)
/// so existing Kotlin session JSON files remain directly readable on upgraded installs.
class LocalJsonSessionRepository implements SessionRepository {
  LocalJsonSessionRepository({Future<Directory> Function()? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryResolver;

  Future<Directory> _sessionsDir() async {
    final base = await _directoryResolver();
    final dir = Directory('${base.path}${Platform.pathSeparator}echo_sessions');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<bool> saveSession(HearingSessionRecord record) async {
    try {
      final dir = await _sessionsDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}session_${record.sessionId}.json',
      );
      await file.writeAsString(jsonEncode(record.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HearingSessionRecord?> getSession(String sessionId) async {
    final all = await loadAllSessions();
    return all.where((s) => s.sessionId == sessionId).firstOrNull;
  }

  @override
  Future<List<HearingSessionRecord>> loadAllSessions() async {
    final dir = await _sessionsDir();
    final entries = await dir.list().toList();
    final sessions = <HearingSessionRecord>[];
    for (final entity in entries) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          sessions.add(
            HearingSessionRecord.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Ignore corrupt or partially written session artifacts gracefully.
      }
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  @override
  Future<void> deleteAllSessions() async {
    final dir = await _sessionsDir();
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          await entity.delete();
        }
      }
    }
  }
}

/// In-memory repository for fast deterministic unit & widget testing.
class InMemorySessionRepository implements SessionRepository {
  final Map<String, HearingSessionRecord> _sessions = {};

  @override
  Future<bool> saveSession(HearingSessionRecord record) async {
    _sessions[record.sessionId] = record;
    return true;
  }

  @override
  Future<HearingSessionRecord?> getSession(String sessionId) async =>
      _sessions[sessionId];

  @override
  Future<List<HearingSessionRecord>> loadAllSessions() async {
    final list = _sessions.values.toList();
    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  @override
  Future<void> deleteAllSessions() async {
    _sessions.clear();
  }
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return LocalJsonSessionRepository();
});
