import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'local_database_service.dart';

class IcsExportService {
  static Future<void> exportCurrentSemester(BuildContext context) async {
    try {
      final db = LocalDatabaseService.instance;
      final user = db.getCurrentUser();
      
      if (user == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay usuario activo.')),
          );
        }
        return;
      }
      
      // Obtener semestres activos
      final semesters = db.getSemesters(user.uid);
      if (semesters.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay un semestre activo para exportar.')),
          );
        }
        return;
      }
      
      // Para exportar tomamos el semestre activo más reciente o el primero
      final semester = semesters.first;
      final subjects = db.getSubjects(semester.syncId);
      final schedules = db.getAllSchedulesForSemester(semester.syncId);
      
      if (schedules.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El semestre activo no tiene horarios.')),
          );
        }
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('BEGIN:VCALENDAR');
      buffer.writeln('VERSION:2.0');
      buffer.writeln('PRODID:-//UniCal//ES');
      buffer.writeln('CALSCALE:GREGORIAN');
      buffer.writeln('METHOD:PUBLISH');
      
      final dtStamp = _formatIcsDateTime(DateTime.now().toUtc());
      final untilDate = _formatIcsDateTime(DateTime(
        semester.endDate.year,
        semester.endDate.month,
        semester.endDate.day,
        23,
        59,
        59,
      ).toUtc());

      for (final schedule in schedules) {
        final subject = subjects.firstWhere(
          (s) => s.syncId == schedule.subjectId,
          orElse: () => SubjectModel(
            syncId: '', semesterId: '', name: 'Materia Desconocida', passingGrade: 0, colorValue: 0xFF6B7FD7,
          ),
        );
        
        DateTime firstDate = _findFirstOccurrence(semester.startDate, schedule.dayOfWeek);
        
        final partsStart = schedule.startTime.split(':');
        final partsEnd = schedule.endTime.split(':');
        
        if (partsStart.length == 2 && partsEnd.length == 2) {
          final startDateTime = DateTime(
            firstDate.year, firstDate.month, firstDate.day,
            int.parse(partsStart[0]), int.parse(partsStart[1])
          );
          
          final endDateTime = DateTime(
            firstDate.year, firstDate.month, firstDate.day,
            int.parse(partsEnd[0]), int.parse(partsEnd[1])
          );
          
          final dtStart = _formatIcsDateTime(startDateTime.toUtc());
          final dtEnd = _formatIcsDateTime(endDateTime.toUtc());
          final byDay = _getIcsDay(schedule.dayOfWeek);
          
          buffer.writeln('BEGIN:VEVENT');
          buffer.writeln('UID:${schedule.syncId}@unical.app');
          buffer.writeln('DTSTAMP:$dtStamp');
          buffer.writeln('DTSTART:$dtStart');
          buffer.writeln('DTEND:$dtEnd');
          buffer.writeln('RRULE:FREQ=WEEKLY;UNTIL=$untilDate;BYDAY=$byDay');
          buffer.writeln('SUMMARY:${subject.name}');
          if (subject.professor != null && subject.professor!.isNotEmpty) {
            buffer.writeln('DESCRIPTION:Profesor: ${subject.professor}');
          }
          if (schedule.classroom != null && schedule.classroom!.isNotEmpty) {
            buffer.writeln('LOCATION:${schedule.classroom}');
          }
          buffer.writeln('END:VEVENT');
        }
      }
      
      buffer.writeln('END:VCALENDAR');
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/horario_${semester.name.replaceAll(' ', '_')}.ics');
      await file.writeAsString(buffer.toString());
      
      if (context.mounted) {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(file.path)], 
          subject: 'Horario: ${semester.name}',
          sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }
  
  static DateTime _findFirstOccurrence(DateTime start, int targetWeekday) {
    int diff = targetWeekday - start.weekday;
    if (diff < 0) diff += 7;
    return start.add(Duration(days: diff));
  }
  
  static String _formatIcsDateTime(DateTime dt) {
    final format = DateFormat("yyyyMMdd'T'HHmmss'Z'");
    return format.format(dt);
  }
  
  static String _getIcsDay(int weekday) {
    switch (weekday) {
      case 1: return 'MO';
      case 2: return 'TU';
      case 3: return 'WE';
      case 4: return 'TH';
      case 5: return 'FR';
      case 6: return 'SA';
      case 7: return 'SU';
      default: return 'MO';
    }
  }
}
