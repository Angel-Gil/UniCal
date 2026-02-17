import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../models/models.dart';
import 'local_database_service.dart';

/// Servicio para sincronizar datos del horario y eventos con el Android Home Widget
class WidgetService {
  static const _widgetName = 'NextClassWidgetProvider';

  /// Serializa los datos PRE-ROCESADOS en strings simples para el widget
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

    // 1. Calcular Próxima Clase (Lógica en Dart)
    final now = DateTime.now();
    final todayDow = now.weekday; // 1=Mon, 7=Sun
    final currentTime = TimeOfDay.fromDateTime(now);

    ScheduleModel? nextClass;

    // Buscar hoy
    final todayClasses = schedules.where((s) => s.dayOfWeek == todayDow).where((
      s,
    ) {
      final start = _parseTime(s.startTime);
      return _isAfter(start, currentTime);
    }).toList()..sort((a, b) => _compareTimes(a.startTime, b.startTime));

    if (todayClasses.isNotEmpty) {
      nextClass = todayClasses.first;
    } else {
      // Buscar días siguientes
      for (int i = 1; i <= 7; i++) {
        final nextDow = ((todayDow - 1 + i) % 7) + 1;
        final nextDayClasses =
            schedules.where((s) => s.dayOfWeek == nextDow).toList()
              ..sort((a, b) => _compareTimes(a.startTime, b.startTime));

        if (nextDayClasses.isNotEmpty) {
          nextClass = nextDayClasses.first;
          break;
        }
      }
    }

    // 2. Guardar datos de Próxima Clase como Strings
    if (nextClass != null) {
      final subject = db.getSubject(nextClass.subjectId);
      final subjectName = subject?.name ?? 'Clase';
      final formattedTime = _formatTime12H(nextClass.startTime);
      final room = nextClass.classroom ?? '';

      await HomeWidget.saveWidgetData('next_subject', subjectName);
      await HomeWidget.saveWidgetData(
        'next_time',
        'Inicia a las $formattedTime',
      );
      await HomeWidget.saveWidgetData(
        'next_room',
        room.isNotEmpty ? '📍 $room' : '',
      );

      // Calcular día (si no es hoy)
      // Por simplicidad, el widget nativo calculará el nombre del día actual,
      // pero si la clase es mañana, deberíamos indicarlo.
      // Para simplificar "otra forma", dejaremos que el widget muestre el día actual
      // y la info de la clase. O mejor:
      // Si la clase no es hoy, el "Inicia a las X" podría ser confuso.
      // Vamos a agregar el día si no es hoy.
      if (nextClass.dayOfWeek != todayDow) {
        final dayName = _getDayName(nextClass.dayOfWeek);
        await HomeWidget.saveWidgetData(
          'next_time',
          '$dayName, $formattedTime',
        );
      }
    } else {
      await HomeWidget.saveWidgetData('next_subject', '🎉 Sin clases');
      await HomeWidget.saveWidgetData(
        'next_time',
        'No hay más clases programadas',
      );
      await HomeWidget.saveWidgetData('next_room', '');
    }

    // 3. Calcular Eventos (Lógica en Dart)
    final events = db.getUpcomingEvents(user.uid, days: 14);

    // Limpiar claves anteriores
    await HomeWidget.saveWidgetData('event_1', '');
    await HomeWidget.saveWidgetData('event_2', '');
    await HomeWidget.saveWidgetData('event_3', '');
    await HomeWidget.saveWidgetData('events_count', events.length);

    if (events.isNotEmpty) {
      await HomeWidget.saveWidgetData('event_1', _formatEvent(events[0], db));
    }
    if (events.length > 1) {
      await HomeWidget.saveWidgetData('event_2', _formatEvent(events[1], db));
    }
    if (events.length > 2) {
      await HomeWidget.saveWidgetData('event_3', _formatEvent(events[2], db));
    }

    await HomeWidget.updateWidget(androidName: _widgetName);
  }

  static String _formatEvent(EventModel event, LocalDatabaseService db) {
    final subject = db.getSubject(event.subjectId);
    final subjectName = subject?.name ?? 'Evento';
    final date = '${event.dateTime.day}/${event.dateTime.month}';
    return '${event.title} – $date – $subjectName';
  }

  static TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static bool _isAfter(TimeOfDay t1, TimeOfDay t2) {
    if (t1.hour > t2.hour) return true;
    if (t1.hour == t2.hour && t1.minute > t2.minute) return true;
    return false;
  }

  static int _compareTimes(String t1, String t2) {
    final time1 = _parseTime(t1);
    final time2 = _parseTime(t2);
    if (time1.hour != time2.hour) return time1.hour - time2.hour;
    return time1.minute - time2.minute;
  }

  static String _formatTime12H(String time24) {
    final time = _parseTime(time24);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final hour12 = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final min = time.minute.toString().padLeft(2, '0');
    return '$hour12:$min $period';
  }

  static String _getDayName(int day) {
    const days = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    return days[day - 1];
  }

  static Future<void> _clearWidget() async {
    await HomeWidget.saveWidgetData('next_subject', '—');
    await HomeWidget.saveWidgetData('next_time', 'Iniciar sesión');
    await HomeWidget.saveWidgetData('next_room', '');
    await HomeWidget.saveWidgetData('event_1', '');
    await HomeWidget.saveWidgetData('events_count', 0);
    await HomeWidget.updateWidget(androidName: _widgetName);
  }
}
