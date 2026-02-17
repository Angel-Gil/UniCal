import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'auth_service.dart';
import 'local_database_service.dart';

class ShareService {
  static final ShareService instance = ShareService._();
  ShareService._();

  final _firestore = FirebaseFirestore.instance;
  final _db = LocalDatabaseService.instance;

  /// Comparte un semestre subiéndolo a Firestore y retornando un ID único.
  /// Incluye materias, cortes (sin notas) y horarios.
  Future<String> shareSemester(String semesterId) async {
    final semester = _db
        .getSemesters(AuthService.instance.currentUser!.uid) // Buscar en lista
        .firstWhere((s) => s.syncId == semesterId);

    final subjects = _db.getSubjects(semesterId);

    final subjectsData = <Map<String, dynamic>>[];
    final schedulesData = <Map<String, dynamic>>[];

    for (final subject in subjects) {
      final periods = _db.getGradePeriods(subject.syncId);
      final schedules = _db
          .getAllSchedulesForSemester(semesterId)
          .where((s) => s.subjectId == subject.syncId);

      // Limpiar notas al compartir
      final cleanPeriods = periods
          .map(
            (p) => {
              'name': p.name,
              'percentage': p.percentage,
              'order': p.order,
              // No incluimos obtainedGrade ni IDs
            },
          )
          .toList();

      subjectsData.add({
        'tempId': subject.syncId, // Para mapear horarios
        'name': subject.name,
        'professor': subject.professor,
        'credits': subject.credits,
        'colorValue': subject.colorValue,
        'passingGrade': subject.passingGrade,
        'periods': cleanPeriods,
      });

      for (final schedule in schedules) {
        schedulesData.add({
          'subjectTempId': schedule.subjectId,
          'dayOfWeek': schedule.dayOfWeek,
          'startTime': schedule.startTime,
          'endTime': schedule.endTime,
          'classroom': schedule.classroom,
        });
      }
    }

    // Caducidad: 7 días desde la creación
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 7));

    final data = {
      'semesterName': semester.name,
      'startDate': semester.startDate.toIso8601String(),
      'endDate': semester.endDate.toIso8601String(),
      'subjects': subjectsData,
      'schedules': schedulesData,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': AuthService.instance.currentUser?.uid,
      'expiresAt': Timestamp.fromDate(expiresAt),
    };

    // Usar un ID corto de 6 caracteres si es posible, o UUID
    // Firestore auto-id es seguro.
    final docRef = await _firestore.collection('shared_semesters').add(data);
    return docRef.id;
  }

  /// Genera un enlace para compartir el semestre
  String getShareLink(String shareId) {
    // URL Web Fallback que redirige a calendario://app/p/share_{id}
    return 'https://cu-rose.vercel.app/p/share_$shareId';
  }

  /// Comparte solo el horario para visualización web
  Future<String> shareSchedule(String semesterId) async {
    final semester = _db
        .getSemesters(AuthService.instance.currentUser!.uid)
        .firstWhere((s) => s.syncId == semesterId);

    final subjects = _db.getSubjects(semesterId);
    final schedules = _db.getAllSchedulesForSemester(semesterId);

    final blocks = <Map<String, dynamic>>[];

    for (final schedule in schedules) {
      final subject = subjects
          .where((s) => s.syncId == schedule.subjectId)
          .firstOrNull; // Use firstOrNull safe navigation
      // Fallback if subject not found in list (shouldn't happen if integrity maintained)
      if (subject == null) continue;

      blocks.add({
        'dayOfWeek': schedule.dayOfWeek, // 1-7
        'startTime': schedule.startTime, // HH:MM
        'endTime': schedule.endTime, // HH:MM
        'colorValue': subject.colorValue,
        'subjectName': subject.name,
        'classroom': schedule.classroom ?? '',
        // 'professor': subject.professor, // Optional if needed by web
      });
    }

    // JSON structure matching pagina_web/horario.html & api/schedule.js
    final data = {
      'semesterName': semester.name,
      'blocks': blocks,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': AuthService.instance.currentUser?.uid,
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      ), // 30 days retention
    };

    final docRef = await _firestore.collection('shared_schedules').add(data);
    return docRef.id;
  }

  /// Genera el enlace específico para compartir horario
  String getScheduleShareLink(String shareId) {
    return 'https://cu-rose.vercel.app/horario/hid_$shareId';
  }

  /// Importa un semestre compartido usando su ID.
  Future<void> importSemester(String shareId) async {
    // Limpiar códigos expirados en segundo plano
    _cleanupExpiredShares();

    final doc = await _firestore
        .collection('shared_semesters')
        .doc(shareId)
        .get();
    if (!doc.exists) {
      throw Exception('El semestre compartido no existe o ha expirado.');
    }

    final data = doc.data()!;

    // Verificar caducidad
    final expiresAt = data['expiresAt'] as Timestamp?;
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      // Borrar el documento expirado
      await _firestore.collection('shared_semesters').doc(shareId).delete();
      throw Exception('Este código de compartir ha expirado.');
    }

    final user = AuthService.instance.currentUser;
    if (user == null) throw Exception('Debes iniciar sesión para importar.');

    // 1. Crear Semestre
    final newSemesterId = const Uuid().v4();
    final newSemester = SemesterModel(
      syncId: newSemesterId,
      userId: user.uid,
      name: '${data['semesterName']} (Importado)',
      startDate: DateTime.parse(data['startDate']),
      endDate: DateTime.parse(data['endDate']),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    await _db.saveSemester(newSemester);

    // Mapa de IDs temporales a nuevos IDs reales
    final tempIdToRealId = <String, String>{};

    // 2. Crear Materias y Cortes
    final subjectsList = List<Map<String, dynamic>>.from(data['subjects']);
    for (final subjData in subjectsList) {
      final newSubjectId = const Uuid().v4();
      tempIdToRealId[subjData['tempId']] = newSubjectId;

      final newSubject = SubjectModel(
        syncId: newSubjectId,
        semesterId: newSemesterId,
        name: subjData['name'],
        professor: subjData['professor'],
        credits: subjData['credits'],
        colorValue: subjData['colorValue'],
        passingGrade: (subjData['passingGrade'] as num).toDouble(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isSynced: false,
      );
      await _db.saveSubject(newSubject);

      // Cortes
      final periodsList = List<Map<String, dynamic>>.from(subjData['periods']);
      for (final pData in periodsList) {
        final newPeriod = GradePeriodModel(
          syncId: const Uuid().v4(),
          subjectId: newSubjectId,
          name: pData['name'],
          percentage: (pData['percentage'] as num).toDouble(),
          obtainedGrade: null, // Sin nota
          order: pData['order'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isSynced: false,
        );
        await _db.saveGradePeriod(newPeriod);
      }
    }

    // 3. Crear Horarios
    final schedulesList = List<Map<String, dynamic>>.from(data['schedules']);
    for (final schData in schedulesList) {
      final realSubjectId = tempIdToRealId[schData['subjectTempId']];
      if (realSubjectId != null) {
        final newSchedule = ScheduleModel(
          syncId: const Uuid().v4(),
          subjectId: realSubjectId,
          dayOfWeek: schData['dayOfWeek'],
          startTime: schData['startTime'],
          endTime: schData['endTime'],
          classroom: schData['classroom'],
          createdAt: DateTime.now(),
          isSynced: false,
        );
        await _db.saveSchedule(newSchedule);
      }
    }
  }

  /// Limpia códigos compartidos que ya expiraron.
  Future<void> _cleanupExpiredShares() async {
    try {
      final expired = await _firestore
          .collection('shared_semesters')
          .where('expiresAt', isLessThan: Timestamp.now())
          .limit(20) // Limitar para no hacer queries muy grandes
          .get();

      for (final doc in expired.docs) {
        await doc.reference.delete();
      }

      if (expired.docs.isNotEmpty) {
        debugPrint(
          'ShareService: ${expired.docs.length} códigos expirados eliminados.',
        );
      }
    } catch (e) {
      debugPrint('ShareService: Error limpiando expirados: $e');
    }
  }

  /// Obtiene la fecha de expiración para mostrar en UI.
  DateTime getExpirationDate() {
    return DateTime.now().add(const Duration(days: 7));
  }
}
