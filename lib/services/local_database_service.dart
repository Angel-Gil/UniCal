import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import 'auth_service.dart';

/// Servicio de base de datos local usando Hive
class LocalDatabaseService {
  static const String _usersBox = 'users';
  static const String _semestersBox = 'semesters';
  static const String _subjectsBox = 'subjects';
  static const String _schedulesBox = 'schedules';
  static const String _gradePeriodsBox = 'gradePeriods';
  static const String _eventsBox = 'events';

  static LocalDatabaseService? _instance;
  static LocalDatabaseService get instance =>
      _instance ??= LocalDatabaseService._();

  LocalDatabaseService._();

  bool _isInitialized = false;

  /// Inicializa Hive y abre las cajas
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    await Future.wait([
      Hive.openBox<Map>(_usersBox),
      Hive.openBox<Map>(_semestersBox),
      Hive.openBox<Map>(_subjectsBox),
      Hive.openBox<Map>(_schedulesBox),
      Hive.openBox<Map>(_gradePeriodsBox),
      Hive.openBox<Map>(_eventsBox),
    ]);

    _isInitialized = true;
  }

  final _changeController = StreamController<void>.broadcast();
  Stream<void> get onDataChanged => _changeController.stream;

  void _notifyChange() {
    _changeController.add(null);
  }

  // ==================== USUARIOS ====================

  Box<Map> get _userBox => Hive.box<Map>(_usersBox);

  Future<void> saveUser(UserModel user) async {
    await _userBox.put(user.uid, user.toJson());
    // No notificamos cambio de usuario para backup generalmente, pero mal no hace.
  }

  UserModel? getUser(String uid) {
    final data = _userBox.get(uid);
    if (data == null) return null;
    return UserModel.fromJson(Map<String, dynamic>.from(data));
  }

  UserModel? getCurrentUser() {
    if (_userBox.isEmpty) return null;
    final data = _userBox.values.first;
    return UserModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deleteUser(String uid) async {
    await _userBox.delete(uid);
  }

  // ==================== SEMESTRES ====================

  Box<Map> get _semesterBox => Hive.box<Map>(_semestersBox);

  Future<void> saveSemester(SemesterModel semester) async {
    await _semesterBox.put(semester.syncId, semester.toJson());
    if (!semester.isSynced) _notifyChange();
  }

  List<SemesterModel> getSemesters(
    String userId, {
    bool includeArchived = false,
  }) {
    return _semesterBox.values
        .map((data) => _semesterFromMap(data))
        .where((s) => s.userId == userId && s.deletedAt == null)
        .where((s) => includeArchived || s.status == SemesterStatus.active)
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
  }

  /// Obtiene TODOS los semestres incluyendo eliminados (para sync)
  List<SemesterModel> getAllSemestersForSync(String userId) {
    return _semesterBox.values
        .map((data) => _semesterFromMap(data))
        .where((s) => s.userId == userId)
        .toList();
  }

  /// Obtiene TODAS las materias incluyendo eliminadas (para sync)
  List<SubjectModel> getAllSubjectsForSync() {
    return _subjectBox.values.map((data) => _subjectFromMap(data)).toList();
  }

  SemesterModel? getSemester(String syncId) {
    final data = _semesterBox.get(syncId);
    if (data == null) return null;
    return _semesterFromMap(data);
  }

  Future<void> deleteSemester(String syncId) async {
    // Soft delete: set deletedAt instead of removing
    final semester = getSemester(syncId);
    if (semester == null) return;

    // Soft delete all subjects for this semester
    final subjects = getSubjects(syncId);
    for (final subject in subjects) {
      await deleteSubject(subject.syncId);
    }

    await saveSemester(
      semester.copyWith(deletedAt: DateTime.now(), isSynced: false),
    );
    _notifyChange();
  }

  SemesterModel _semesterFromMap(Map data) {
    final json = Map<String, dynamic>.from(data);
    return SemesterModel(
      syncId: json['syncId'],
      userId: json['userId'],
      name: json['name'],
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      status: json['status'] == 'archived'
          ? SemesterStatus.archived
          : SemesterStatus.active,
      isSynced: json['isSynced'] ?? false,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'])
          : null,
    );
  }

  // ==================== MATERIAS ====================

  Box<Map> get _subjectBox => Hive.box<Map>(_subjectsBox);

  Future<void> saveSubject(SubjectModel subject) async {
    await _subjectBox.put(subject.syncId, subject.toJson());
    if (!subject.isSynced) _notifyChange();
  }

  List<SubjectModel> getSubjects(String semesterId) {
    return _subjectBox.values
        .map((data) => _subjectFromMap(data))
        .where((s) => s.semesterId == semesterId && s.deletedAt == null)
        .toList();
  }

  SubjectModel? getSubject(String syncId) {
    final data = _subjectBox.get(syncId);
    if (data == null) return null;
    return _subjectFromMap(data);
  }

  Future<void> deleteSubject(String syncId) async {
    // Soft delete: set deletedAt instead of removing
    final subject = getSubject(syncId);
    if (subject == null) return;

    await saveSubject(
      subject.copyWith(deletedAt: DateTime.now(), isSynced: false),
    );
    _notifyChange();
  }

  // ==================== PAPELERA ====================

  /// Obtiene semestres en la papelera
  List<SemesterModel> getDeletedSemesters(String userId) {
    return _semesterBox.values
        .map((data) => _semesterFromMap(data))
        .where((s) => s.userId == userId && s.deletedAt != null)
        .toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
  }

  /// Obtiene materias en la papelera
  List<SubjectModel> getDeletedSubjects() {
    return _subjectBox.values
        .map((data) => _subjectFromMap(data))
        .where((s) => s.deletedAt != null)
        .toList();
  }

  /// Restaura un semestre de la papelera
  Future<void> restoreSemester(String syncId) async {
    final semester = getSemester(syncId);
    if (semester == null) return;

    await saveSemester(
      semester.copyWith(clearDeletedAt: true, isSynced: false),
    );

    // Restore subjects too
    final deletedSubjects = _subjectBox.values
        .map((data) => _subjectFromMap(data))
        .where((s) => s.semesterId == syncId && s.deletedAt != null)
        .toList();
    for (final subject in deletedSubjects) {
      await restoreSubject(subject.syncId);
    }
    _notifyChange();
  }

  /// Restaura una materia de la papelera
  Future<void> restoreSubject(String syncId) async {
    final subject = getSubject(syncId);
    if (subject == null) return;

    await saveSubject(subject.copyWith(clearDeletedAt: true, isSynced: false));
    _notifyChange();
  }

  /// Elimina permanentemente un semestre (de Hive y Firestore)
  Future<void> permanentlyDeleteSemester(String syncId) async {
    // Delete all subjects permanently
    final subjects = _subjectBox.values
        .map((data) => _subjectFromMap(data))
        .where((s) => s.semesterId == syncId)
        .toList();
    for (final subject in subjects) {
      await permanentlyDeleteSubject(subject.syncId);
    }
    await _semesterBox.delete(syncId);
    _deleteFromCloud('semesters', syncId);
    _notifyChange();
  }

  /// Elimina permanentemente una materia (de Hive y Firestore)
  Future<void> permanentlyDeleteSubject(String syncId) async {
    // Delete grade periods
    final periods = getGradePeriods(syncId);
    for (final period in periods) {
      await _gradePeriodBox.delete(period.syncId);
      _deleteFromCloud('gradePeriods', period.syncId);
    }
    // Delete schedules
    final schedules = _scheduleBox.values
        .map((data) => ScheduleModel.fromJson(Map<String, dynamic>.from(data)))
        .where((s) => s.subjectId == syncId)
        .toList();
    for (final schedule in schedules) {
      await _scheduleBox.delete(schedule.syncId);
      _deleteFromCloud('schedules', schedule.syncId);
    }
    await _subjectBox.delete(syncId);
    _deleteFromCloud('subjects', syncId);
    _notifyChange();
  }

  /// Vacía toda la papelera
  Future<void> emptyTrash(String userId) async {
    final deletedSemesters = getDeletedSemesters(userId);
    for (final semester in deletedSemesters) {
      await permanentlyDeleteSemester(semester.syncId);
    }
    _notifyChange();
  }

  SubjectModel _subjectFromMap(Map data) {
    final json = Map<String, dynamic>.from(data);
    return SubjectModel(
      syncId: json['syncId'],
      semesterId: json['semesterId'],
      name: json['name'],
      professor: json['professor'],
      colorValue: json['colorValue'] ?? 0xFF6B7FD7,
      passingGrade: (json['passingGrade'] as num).toDouble(),
      credits: json['credits'],
      isSynced: json['isSynced'] ?? false,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'])
          : null,
    );
  }

  // ==================== HORARIOS ====================

  Box<Map> get _scheduleBox => Hive.box<Map>(_schedulesBox);

  Future<void> saveSchedule(ScheduleModel schedule) async {
    await _scheduleBox.put(schedule.syncId, schedule.toJson());
    if (!schedule.isSynced) _notifyChange();
  }

  List<ScheduleModel> getSchedules(String subjectId) {
    return _scheduleBox.values
        .map((data) => ScheduleModel.fromJson(Map<String, dynamic>.from(data)))
        .where((s) => s.subjectId == subjectId && s.deletedAt == null)
        .toList()
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
  }

  List<ScheduleModel> getAllSchedulesForSemester(String semesterId) {
    final subjects = getSubjects(semesterId);
    final subjectIds = subjects.map((s) => s.syncId).toSet();
    return _scheduleBox.values
        .map((data) => ScheduleModel.fromJson(Map<String, dynamic>.from(data)))
        .where((s) => subjectIds.contains(s.subjectId) && s.deletedAt == null)
        .toList();
  }

  List<ScheduleModel> getAllSchedules() {
    return _scheduleBox.values
        .map((data) => ScheduleModel.fromJson(Map<String, dynamic>.from(data)))
        .where((s) => s.deletedAt == null)
        .toList();
  }

  Future<void> deleteSchedule(String syncId) async {
    await _scheduleBox.delete(syncId);
    _notifyChange();
  }

  // ...

  List<EventModel> getEventsForSemester(String semesterId) {
    final subjects = getSubjects(semesterId);
    final subjectIds = subjects.map((s) => s.syncId).toSet();

    return _eventBox.values
        .map((data) => _eventFromMap(data))
        .where((e) => subjectIds.contains(e.subjectId) && e.deletedAt == null)
        .toList();
  }

  Future<void> deleteSchedulesForSubject(String subjectId) async {
    final keys = _scheduleBox.keys.where((key) {
      final data = _scheduleBox.get(key);
      if (data == null) return false;
      return data['subjectId'] == subjectId;
    }).toList();
    for (final key in keys) {
      await _scheduleBox.delete(key);
    }
    _notifyChange();
  }

  // ==================== CORTES ====================

  Box<Map> get _gradePeriodBox => Hive.box<Map>(_gradePeriodsBox);

  Future<void> saveGradePeriod(GradePeriodModel period) async {
    await _gradePeriodBox.put(period.syncId, period.toJson());
    if (!period.isSynced) _notifyChange();
  }

  List<GradePeriodModel> getGradePeriods(String subjectId) {
    return _gradePeriodBox.values
        .map((data) => _periodFromMap(data))
        .where((p) => p.subjectId == subjectId && p.deletedAt == null)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  Future<void> deleteGradePeriod(String syncId) async {
    await _gradePeriodBox.delete(syncId);
    _notifyChange();
  }

  GradePeriodModel _periodFromMap(Map data) {
    final json = Map<String, dynamic>.from(data);
    return GradePeriodModel(
      syncId: json['syncId'],
      subjectId: json['subjectId'],
      name: json['name'],
      percentage: (json['percentage'] as num).toDouble(),
      obtainedGrade: json['obtainedGrade'] != null
          ? (json['obtainedGrade'] as num).toDouble()
          : null,
      grades: json['grades'] != null
          ? (json['grades'] as List)
                .map((g) => GradeEntry.fromJson(Map<String, dynamic>.from(g)))
                .toList()
          : [],
      order: json['order'],
      isSynced: json['isSynced'] ?? false,
    );
  }

  // ==================== EVENTOS ====================

  Box<Map> get _eventBox => Hive.box<Map>(_eventsBox);

  Future<void> saveEvent(EventModel event) async {
    await _eventBox.put(event.syncId, event.toJson());
    if (!event.isSynced) _notifyChange();
  }

  List<EventModel> getEvents(String subjectId) {
    return _eventBox.values
        .map((data) => _eventFromMap(data))
        .where((e) => e.subjectId == subjectId && e.deletedAt == null)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  List<EventModel> getAllEvents(String userId) {
    // En una app real, filtraríamos por userId en cada evento si los eventos tuvieran userId directo
    // Actualmente EventModel tiene subjectId. Necesitamos obtener las materias del usuario primero.
    final semesters = getSemesters(userId, includeArchived: true);
    final allSubjectIds = <String>{};
    for (final semester in semesters) {
      final subjects = getSubjects(semester.syncId);
      allSubjectIds.addAll(subjects.map((s) => s.syncId));
    }

    return _eventBox.values
        .map((data) => _eventFromMap(data))
        .where(
          (e) => allSubjectIds.contains(e.subjectId) && e.deletedAt == null,
        )
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  List<EventModel> getUpcomingEvents(String userId, {int days = 7}) {
    final now = DateTime.now();
    final limit = now.add(Duration(days: days));

    // Get user's subject IDs to filter events
    final semesters = getSemesters(userId, includeArchived: true);
    final allSubjectIds = <String>{};
    for (final semester in semesters) {
      final subjects = getSubjects(semester.syncId);
      allSubjectIds.addAll(subjects.map((s) => s.syncId));
    }

    return _eventBox.values
        .map((data) => _eventFromMap(data))
        .where(
          (e) =>
              allSubjectIds.contains(e.subjectId) && // Added filter
              e.deletedAt == null &&
              e.dateTime.isAfter(now) &&
              e.dateTime.isBefore(limit),
        )
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  Future<void> deleteEvent(String syncId) async {
    await _eventBox.delete(syncId);
    _notifyChange();
  }

  EventModel _eventFromMap(Map data) {
    final json = Map<String, dynamic>.from(data);
    return EventModel(
      syncId: json['syncId'],
      subjectId: json['subjectId'],
      title: json['title'],
      notes: json['notes'],
      type: EventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => EventType.other,
      ),
      dateTime: DateTime.parse(json['dateTime']),
      hasReminder: json['hasReminder'] ?? false,
      isCompleted: json['isCompleted'] ?? false,
      isSynced: json['isSynced'] ?? false,
    );
  }

  // ==================== UTILIDADES ====================

  /// Marca todos los registros como no sincronizados
  Future<void> markAllUnsynced() async {
    // Implementar si es necesario
  }

  /// Obtiene todos los registros pendientes de sincronizar
  List<Map<String, dynamic>> getPendingSync() {
    final pending = <Map<String, dynamic>>[];
    // Agregar lógica para obtener registros no sincronizados
    return pending;
  }

  /// Limpia toda la base de datos local
  Future<void> clearAll() async {
    await _userBox.clear();
    await _semesterBox.clear();
    await _subjectBox.clear();
    await _gradePeriodBox.clear();
    await _eventBox.clear();
  }

  /// Elimina un documento de Firestore para que no se re-descargue en sync.
  void _deleteFromCloud(String collection, String docId) {
    final user = AuthService.instance.currentUser;
    if (user == null || AuthService.instance.isGuest) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection(collection)
        .doc(docId)
        .delete()
        .then((_) => debugPrint('Cloud: Eliminado $collection/$docId'))
        .catchError(
          (e) => debugPrint('Cloud: Error eliminando $collection/$docId: $e'),
        );
  }

  /// Migra datos del guest al nuevo usuario autenticado
  Future<int> migrateUserData(String oldUserId, String newUserId) async {
    int count = 0;

    // Migrar semestres
    final semesters = _semesterBox.values
        .map((data) => _semesterFromMap(data))
        .where((s) => s.userId == oldUserId)
        .toList();

    for (final semester in semesters) {
      final updated = SemesterModel(
        syncId: semester.syncId,
        userId: newUserId,
        name: semester.name,
        startDate: semester.startDate,
        endDate: semester.endDate,
        status: semester.status,
        isSynced: false, // Mark for sync
        deletedAt: semester.deletedAt,
      );
      await _semesterBox.put(updated.syncId, updated.toJson());
      count++;

      // Migrar materias del semestre
      final subjects = _subjectBox.values
          .map((data) => _subjectFromMap(data))
          .where((s) => s.semesterId == semester.syncId)
          .toList();

      for (final subject in subjects) {
        final updatedSubject = subject.copyWith(isSynced: false);
        await _subjectBox.put(updatedSubject.syncId, updatedSubject.toJson());
        count++;
      }
    }

    // Marcar grade periods y events como no sincronizados
    for (final key in _gradePeriodBox.keys) {
      final data = _gradePeriodBox.get(key);
      if (data != null) {
        final json = Map<String, dynamic>.from(data);
        json['isSynced'] = false;
        await _gradePeriodBox.put(key, json);
        count++;
      }
    }

    for (final key in _eventBox.keys) {
      final data = _eventBox.get(key);
      if (data != null) {
        final json = Map<String, dynamic>.from(data);
        json['isSynced'] = false;
        await _eventBox.put(key, json);
        count++;
      }
    }

    _notifyChange();
    debugPrint('LocalDB: Migrados $count items de $oldUserId a $newUserId');
    return count;
  }
}
