import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/models.dart';
import 'local_database_service.dart';
import 'auth_service.dart';

/// Servicio de sincronización offline-first con Firestore
class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();

  SyncService._();

  final _db = LocalDatabaseService.instance;
  final _firestore = FirebaseFirestore.instance;
  final _connectivity = Connectivity();

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  DateTime? _lastSyncAt;

  /// Inicializa el monitoreo de conectividad (solo para saber si hay internet)
  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _isOnline = !results.contains(ConnectivityResult.none);
      _notifyStatus();
    });

    // NO auto-sync: el usuario decide cuándo subir/descargar datos
  }

  // Auto-sync deshabilitado - solo sync manual via backupData() y restoreData()

  void _notifyStatus({bool isSyncing = false, String? error}) {
    _syncStatusController.add(
      SyncStatus(
        isOnline: _isOnline,
        isSyncing: isSyncing,
        lastSyncAt: _lastSyncAt ?? DateTime.now(),
        pendingChanges: _db.getPendingSync().length,
        error: error,
      ),
    );
  }

  /// Sincroniza todos los datos con Firestore
  Future<SyncResult> syncNow() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      return SyncResult(
        success: false,
        message: 'No hay sesión activa',
        syncedCount: 0,
      );
    }

    if (!_isOnline) {
      return SyncResult(
        success: false,
        message: 'Sin conexión a internet',
        syncedCount: 0,
      );
    }

    _notifyStatus(isSyncing: true);

    int syncedCount = 0;

    try {
      // Sincronizar semestres
      syncedCount += await _syncSemesters(user.uid);

      // Sincronizar materias
      syncedCount += await _syncSubjects(user.uid);

      // Sincronizar cortes
      syncedCount += await _syncGradePeriods(user.uid);

      // Sincronizar eventos
      syncedCount += await _syncEvents(user.uid);

      // Sincronizar horarios
      syncedCount += await _syncSchedules(user.uid);

      _lastSyncAt = DateTime.now();
      _notifyStatus();

      debugPrint(
        'SyncService: Sincronización completada. $syncedCount registros.',
      );

      return SyncResult(
        success: true,
        message: 'Sincronización completada',
        syncedCount: syncedCount,
      );
    } catch (e) {
      debugPrint('SyncService: Error de sincronización: $e');
      _notifyStatus(error: e.toString());

      return SyncResult(
        success: false,
        message: 'Error: $e',
        syncedCount: syncedCount,
      );
    }
  }

  Future<int> _syncSemesters(String userId) async {
    int count = 0;
    // Get ALL semesters including soft-deleted for upload
    final allLocal = _db.getAllSemestersForSync(userId);

    // Subir locales no sincronizados (incluyendo eliminados)
    for (final semester in allLocal.where((s) => !s.isSynced)) {
      try {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('semesters')
            .doc(semester.syncId)
            .set(semester.toJson());

        await _db.saveSemester(semester.copyWith(isSynced: true));
        count++;
      } catch (e) {
        debugPrint(
          'SyncService: Error sincronizando semestre ${semester.syncId}: $e',
        );
      }
    }

    // Descargar remotos
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('semesters')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // If local version exists and is soft-deleted, don't overwrite
        final localSemester = _db.getSemester(doc.id);
        if (localSemester != null && localSemester.deletedAt != null) continue;

        final remote = SemesterModel(
          syncId: doc.id,
          userId: data['userId'],
          name: data['name'],
          startDate: DateTime.parse(data['startDate']),
          endDate: DateTime.parse(data['endDate']),
          status: data['status'] == 'archived'
              ? SemesterStatus.archived
              : SemesterStatus.active,
          isSynced: true,
          deletedAt: data['deletedAt'] != null
              ? DateTime.parse(data['deletedAt'])
              : null,
        );
        // Don't restore items that are deleted in Firestore
        if (remote.deletedAt != null) continue;

        await _db.saveSemester(remote);
        count++;
      }
    } catch (e) {
      debugPrint('SyncService: Error descargando semestres: $e');
    }

    return count;
  }

  Future<int> _syncSubjects(String userId) async {
    int count = 0;

    // Get ALL subjects including soft-deleted for upload
    final allLocal = _db.getAllSubjectsForSync();

    // Subir no sincronizados (incluyendo eliminados)
    for (final subject in allLocal.where((s) => !s.isSynced)) {
      try {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('subjects')
            .doc(subject.syncId)
            .set(subject.toJson());

        await _db.saveSubject(subject.copyWith(isSynced: true));
        count++;
      } catch (e) {
        debugPrint('SyncService: Error sincronizando materia: $e');
      }
    }

    // Descargar remotos
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('subjects')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // If local version exists and is soft-deleted, don't overwrite
        final localSubject = _db.getSubject(doc.id);
        if (localSubject != null && localSubject.deletedAt != null) continue;

        final remote = SubjectModel(
          syncId: doc.id,
          semesterId: data['semesterId'],
          name: data['name'],
          professor: data['professor'],
          colorValue: data['colorValue'] ?? 0xFF6B7FD7,
          passingGrade: (data['passingGrade'] as num).toDouble(),
          credits: data['credits'],
          isSynced: true,
          deletedAt: data['deletedAt'] != null
              ? DateTime.parse(data['deletedAt'])
              : null,
        );
        // Don't restore items that are deleted in Firestore
        if (remote.deletedAt != null) continue;

        await _db.saveSubject(remote);
        count++;
      }
    } catch (e) {
      debugPrint('SyncService: Error descargando materias: $e');
    }

    return count;
  }

  Future<int> _syncGradePeriods(String userId) async {
    int count = 0;
    final semesters = _db.getSemesters(userId, includeArchived: true);

    for (final semester in semesters) {
      final subjects = _db.getSubjects(semester.syncId);
      for (final subject in subjects) {
        final periods = _db.getGradePeriods(subject.syncId);

        // Subir
        for (final p in periods.where((p) => !p.isSynced)) {
          try {
            await _firestore
                .collection('users')
                .doc(userId)
                .collection('grade_periods')
                .doc(p.syncId)
                .set(p.toJson());
            await _db.saveGradePeriod(p.copyWith(isSynced: true));
            count++;
          } catch (e) {
            debugPrint('SyncService: Error sync grade_period: $e');
          }
        }
      }
    }

    // Descargar
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('grade_periods')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final p = GradePeriodModel(
          syncId: doc.id,
          subjectId: data['subjectId'],
          name: data['name'],
          percentage: (data['percentage'] as num).toDouble(),
          obtainedGrade: data['obtainedGrade'] != null
              ? (data['obtainedGrade'] as num).toDouble()
              : null,
          grades: data['grades'] != null
              ? (data['grades'] as List)
                    .map(
                      (g) => GradeEntry.fromJson(Map<String, dynamic>.from(g)),
                    )
                    .toList()
              : [],
          order: data['order'],
          createdAt: DateTime.parse(data['createdAt']),
          updatedAt: data['updatedAt'] != null
              ? DateTime.parse(data['updatedAt'])
              : null,
          isSynced: true,
        );
        await _db.saveGradePeriod(p);
        count++;
      }
    } catch (e) {
      debugPrint('SyncService: Error download grade_periods: $e');
    }
    return count;
  }

  Future<int> _syncSchedules(String userId) async {
    int count = 0;
    // Subir

    final semesters = _db.getSemesters(userId, includeArchived: true);
    for (final s in semesters) {
      final schedules = _db.getAllSchedulesForSemester(s.syncId);
      for (final sch in schedules.where((x) => !x.isSynced)) {
        try {
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('schedules')
              .doc(sch.syncId)
              .set(sch.toJson());
          await _db.saveSchedule(sch.copyWith(isSynced: true));
          count++;
        } catch (e) {
          debugPrint('SyncService: Error sync schedule: $e');
        }
      }
    }

    // Descargar
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final s = ScheduleModel(
          syncId: doc.id,
          subjectId: data['subjectId'],
          dayOfWeek: data['dayOfWeek'],
          startTime: data['startTime'],
          endTime: data['endTime'],
          classroom: data['classroom'],
          createdAt: DateTime.parse(data['createdAt']),
          isSynced: true,
        );
        await _db.saveSchedule(s);
        count++;
      }
    } catch (e) {
      debugPrint('SyncService: Error download schedules: $e');
    }
    return count;
  }

  Future<int> _syncEvents(String userId) async {
    int count = 0;
    final semesters = _db.getSemesters(userId, includeArchived: true);
    for (final s in semesters) {
      final events = _db.getEventsForSemester(s.syncId);
      for (final e in events.where((x) => !x.isSynced)) {
        try {
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('events')
              .doc(e.syncId)
              .set(e.toJson());
          await _db.saveEvent(e.copyWith(isSynced: true));
          count++;
        } catch (ex) {
          debugPrint('SyncService: Error sync event: $ex');
        }
      }
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('events')
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final e = EventModel(
          syncId: doc.id,
          subjectId: data['subjectId'],
          title: data['title'],
          notes: data['notes'],
          dateTime: DateTime.parse(data['dateTime']),
          type: EventType.values.firstWhere(
            (v) => v.name == data['type'],
            orElse: () => EventType.other,
          ),
          isSynced: true,
        );
        await _db.saveEvent(e);
        count++;
      }
    } catch (ex) {
      debugPrint('SyncService: Error download events: $ex');
    }
    return count;
  }

  /// Realiza una copia de seguridad forzada (Sube todo local a Firestore)
  Future<SyncResult> backupData() async {
    if (!_isOnline) {
      return SyncResult(
        success: false,
        message: 'Sin conexión',
        syncedCount: 0,
      );
    }

    try {
      final user = AuthService.instance.currentUser;
      if (user == null) throw Exception('No usuario');

      int count = 0;
      final userDoc = _firestore.collection('users').doc(user.uid);

      // 1. Subir semestres
      final semesters = _db.getSemesters(user.uid, includeArchived: true);
      for (final s in semesters) {
        await userDoc.collection('semesters').doc(s.syncId).set(s.toJson());
        await _db.saveSemester(s.copyWith(isSynced: true));
        count++;
      }

      // 2. Subir materias
      for (final s in semesters) {
        final subjects = _db.getSubjects(s.syncId);
        for (final sub in subjects) {
          await userDoc
              .collection('subjects')
              .doc(sub.syncId)
              .set(sub.toJson());
          await _db.saveSubject(sub.copyWith(isSynced: true));
          count++;

          // 3. Subir cortes de cada materia
          final periods = _db.getGradePeriods(sub.syncId);
          for (final p in periods) {
            await userDoc
                .collection('grade_periods')
                .doc(p.syncId)
                .set(p.toJson());
            await _db.saveGradePeriod(p.copyWith(isSynced: true));
            count++;
          }
        }

        // 4. Subir horarios del semestre
        final schedules = _db.getAllSchedulesForSemester(s.syncId);
        for (final sch in schedules) {
          await userDoc
              .collection('schedules')
              .doc(sch.syncId)
              .set(sch.toJson());
          await _db.saveSchedule(sch.copyWith(isSynced: true));
          count++;
        }
      }

      // 5. Subir eventos (buscando por semestre)
      for (final s in semesters) {
        final events = _db.getEventsForSemester(s.syncId);
        for (final e in events) {
          await userDoc.collection('events').doc(e.syncId).set(e.toJson());
          await _db.saveEvent(e.copyWith(isSynced: true));
          count++;
        }
      }

      _lastSyncAt = DateTime.now();
      _notifyStatus();

      return SyncResult(
        success: true,
        message: 'Backup completado',
        syncedCount: count,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Fallo backup: $e',
        syncedCount: 0,
      );
    }
  }

  /// Restaura datos desde Firestore (Descarga todo y sobrescribe local si es necesario)
  Future<SyncResult> restoreData() async {
    if (!_isOnline) {
      return SyncResult(
        success: false,
        message: 'Sin conexión',
        syncedCount: 0,
      );
    }

    try {
      final user = AuthService.instance.currentUser;
      if (user == null) throw Exception('No usuario');

      int count = 0;
      final userDoc = _firestore.collection('users').doc(user.uid);

      // 1. Descargar Semestres
      final semSnap = await userDoc.collection('semesters').get();
      for (final doc in semSnap.docs) {
        final data = doc.data();
        data['syncId'] = doc.id;
        data['isSynced'] = true;
        final s = SemesterModel.fromJson(data);
        await _db.saveSemester(s);
        count++;
      }

      // 2. Descargar Materias
      final subSnap = await userDoc.collection('subjects').get();
      for (final doc in subSnap.docs) {
        final data = doc.data();
        data['syncId'] = doc.id;
        data['isSynced'] = true;
        final s = SubjectModel.fromJson(data);
        await _db.saveSubject(s);
        count++;
      }

      // 3. Descargar Cortes (grade_periods)
      final gpSnap = await userDoc.collection('grade_periods').get();
      for (final doc in gpSnap.docs) {
        final data = doc.data();
        final p = GradePeriodModel(
          syncId: doc.id,
          subjectId: data['subjectId'],
          name: data['name'],
          percentage: (data['percentage'] as num).toDouble(),
          obtainedGrade: data['obtainedGrade'] != null
              ? (data['obtainedGrade'] as num).toDouble()
              : null,
          grades: data['grades'] != null
              ? (data['grades'] as List)
                    .map(
                      (g) => GradeEntry.fromJson(Map<String, dynamic>.from(g)),
                    )
                    .toList()
              : [],
          order: data['order'],
          createdAt: DateTime.parse(data['createdAt']),
          updatedAt: data['updatedAt'] != null
              ? DateTime.parse(data['updatedAt'])
              : null,
          isSynced: true,
        );
        await _db.saveGradePeriod(p);
        count++;
      }

      // 4. Descargar Horarios
      final schSnap = await userDoc.collection('schedules').get();
      for (final doc in schSnap.docs) {
        final data = doc.data();
        final s = ScheduleModel(
          syncId: doc.id,
          subjectId: data['subjectId'],
          dayOfWeek: data['dayOfWeek'],
          startTime: data['startTime'],
          endTime: data['endTime'],
          classroom: data['classroom'],
          createdAt: DateTime.parse(data['createdAt']),
          isSynced: true,
        );
        await _db.saveSchedule(s);
        count++;
      }

      // 5. Descargar Eventos
      final evSnap = await userDoc.collection('events').get();
      for (final doc in evSnap.docs) {
        final data = doc.data();
        final e = EventModel(
          syncId: doc.id,
          subjectId: data['subjectId'],
          title: data['title'],
          notes: data['notes'],
          dateTime: DateTime.parse(data['dateTime']),
          type: EventType.values.firstWhere(
            (v) => v.name == data['type'],
            orElse: () => EventType.other,
          ),
          isSynced: true,
        );
        await _db.saveEvent(e);
        count++;
      }

      _lastSyncAt = DateTime.now();
      _notifyStatus();

      return SyncResult(
        success: true,
        message: 'Restauración completada',
        syncedCount: count,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Fallo restauración: $e',
        syncedCount: 0,
      );
    }
  }

  /// Detiene el servicio
  void dispose() {
    _subscription?.cancel();
    _syncStatusController.close();
  }
}

/// Estado de sincronización
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final DateTime lastSyncAt;
  final int pendingChanges;
  final String? error;

  SyncStatus({
    required this.isOnline,
    this.isSyncing = false,
    required this.lastSyncAt,
    required this.pendingChanges,
    this.error,
  });
}

/// Resultado de sincronización
class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;

  SyncResult({
    required this.success,
    required this.message,
    required this.syncedCount,
  });
}
