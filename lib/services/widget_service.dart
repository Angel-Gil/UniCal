import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'local_database_service.dart';

/// Servicio para sincronizar datos del horario y eventos con el Android Home Widget
class WidgetService {
  static const _widgetName = 'NextClassWidgetProvider';

  /// Serializa los horarios y eventos completos como JSON para que el widget
  /// nativo calcule orgánicamente la próxima clase.
  static Future<void> updateNextClassWidget() async {
    final db = LocalDatabaseService.instance;
    final user = db.getCurrentUser();

    if (user == null) {
      await _clearWidget();
      return;
    }

    final semesters = db.getSemesters(user.uid);
    if (semesters.isEmpty) {
      await _clearWidget();
      return;
    }

    final activeSemester = semesters.first;
    final schedules = db.getAllSchedulesForSemester(activeSemester.syncId);

    // 1. Preparar lista de horarios para enviar como JSON
    final schedulesJson = schedules.map((s) {
      final subject = db.getSubject(s.subjectId);
      final subjectName = subject?.name ?? 'Clase';

      return {
        'dayOfWeek': s.dayOfWeek,
        'startTime': s.startTime,
        'endTime': s.endTime,
        'subjectName': subjectName,
        'classroom': s.classroom ?? '',
      };
    }).toList();

    // Guardar horarios json formados
    await HomeWidget.saveWidgetData(
      'schedules_json',
      jsonEncode(schedulesJson),
    );

    // 2. Preparar eventos próximos como JSON (hasta 14 días al futuro)
    final events = db.getUpcomingEvents(user.uid, days: 14);
    final eventsJson = events.map((e) {
      final subject = db.getSubject(e.subjectId);
      final subjectName = subject?.name ?? 'Evento';

      return {
        'title': e.title,
        'dateTime': e.dateTime.toIso8601String(), // '2023-11-20T14:30...'
        'subjectName': subjectName,
      };
    }).toList();

    await HomeWidget.saveWidgetData('events_json', jsonEncode(eventsJson));

    // 3. Notificar al widget
    await HomeWidget.updateWidget(androidName: _widgetName);
  }

  static Future<void> _clearWidget() async {
    await HomeWidget.saveWidgetData('schedules_json', '[]');
    await HomeWidget.saveWidgetData('events_json', '[]');
    await HomeWidget.updateWidget(androidName: _widgetName);
  }
}
