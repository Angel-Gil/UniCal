import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../models/enums.dart'; // Importante para EventType
import '../../services/local_database_service.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';

/// Pantalla de calendario con eventos
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _db = LocalDatabaseService.instance;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  UserModel? _user;

  // Mapa de eventos agrupados por día normalizado (sin hora)
  Map<DateTime, List<EventModel>> _events = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _user = _db.getCurrentUser();
    AuthService.instance.authState.addListener(_onAuthChanged);
    _loadEvents();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {
        _user = AuthService.instance.authState.value;
      });
      _loadEvents();
    }
  }

  @override
  void dispose() {
    AuthService.instance.authState.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    final user = _user; // Usar el usuario actualizado

    if (user != null) {
      final allEvents = _db.getAllEvents(user.uid);
      final grouped = <DateTime, List<EventModel>>{};

      for (final event in allEvents) {
        final dateKey = DateTime(
          event.dateTime.year,
          event.dateTime.month,
          event.dateTime.day,
        );
        if (grouped.containsKey(dateKey)) {
          grouped[dateKey]!.add(event);
        } else {
          grouped[dateKey] = [event];
        }
      }

      setState(() {
        _events = grouped;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  List<EventModel> _getEventsForDay(DateTime day) {
    final dateKey = DateTime(day.year, day.month, day.day);
    return _events[dateKey] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario')),
      body: Column(
        children: [
          TableCalendar<EventModel>(
            firstDay: DateTime(2024),
            lastDay: DateTime(2030),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            locale: 'es_ES',
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            startingDayOfWeek: (_user?.startOfWeek ?? 1) == 7 
                ? StartingDayOfWeek.sunday 
                : StartingDayOfWeek.monday,
            calendarStyle: CalendarStyle(
              markerDecoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
            ),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) =>
                setState(() => _calendarFormat = format),
            onPageChanged: (focusedDay) => _focusedDay = focusedDay,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _selectedDay != null
                ? ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _getEventsForDay(
                      _selectedDay!,
                    ).map((e) => _buildEventCard(e)).toList(),
                  )
                : Center(
                    child: Text(
                      'Selecciona un día',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddEventDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEventCard(EventModel event) {
    // Intentar buscar el color de la materia, si no usar primario
    final subject = _db.getSubject(event.subjectId);
    final color = subject != null
        ? Color(subject.colorValue)
        : AppTheme.primaryColor;

    String timeStr = '';
    if (_user?.timeFormat == '24h') {
        timeStr = '${event.dateTime.hour.toString().padLeft(2, '0')}:${event.dateTime.minute.toString().padLeft(2, '0')}';
    } else {
        int hour = event.dateTime.hour;
        final ampm = hour >= 12 ? 'PM' : 'AM';
        if (hour == 0) hour = 12;
        if (hour > 12) hour -= 12;
        timeStr = '${hour.toString().padLeft(2, '0')}:${event.dateTime.minute.toString().padLeft(2, '0')} $ampm';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _showAddEventDialog(eventToEdit: event),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(
            (event.type == EventType.partial ||
                    event.type == EventType.finalExam)
                ? Icons.quiz_outlined
                : Icons.assignment_outlined,
            color: color,
            size: 20,
          ),
        ),
        title: Text(event.title),
        subtitle: Text('${event.type.nameEs} • $timeStr'),
        trailing: subject != null
            ? Text(
                subject.name,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              )
            : null,
      ),
    );
  }

  void _showAddEventDialog({EventModel? eventToEdit}) async {
    final titleController = TextEditingController(
      text: eventToEdit?.title ?? '',
    );
    EventType selectedType = eventToEdit?.type ?? EventType.assignment;
    DateTime selectedDate =
        eventToEdit?.dateTime ?? _selectedDay ?? DateTime.now();
    TimeOfDay selectedTime = eventToEdit != null
        ? TimeOfDay(
            hour: eventToEdit.dateTime.hour,
            minute: eventToEdit.dateTime.minute,
          )
        : TimeOfDay.now();
    SubjectModel? selectedSubject;

    // Cargar materias disponibles
    final user = _db.getCurrentUser();
    if (user == null) return;
    final semesters = _db.getSemesters(user.uid);
    final activeSemester = semesters.isNotEmpty ? semesters.first : null;
    final subjects = activeSemester != null
        ? _db.getSubjects(activeSemester.syncId)
        : <SubjectModel>[];

    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitas crear materias primero')),
      );
      return;
    }

    if (eventToEdit != null) {
      try {
        selectedSubject = subjects.firstWhere(
          (s) => s.syncId == eventToEdit.subjectId,
        );
      } catch (e) {
        selectedSubject = subjects.first; // Fallback
      }
    } else {
      selectedSubject = subjects.first;
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(eventToEdit == null ? 'Nuevo Evento' : 'Editar Evento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Título del evento',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<EventType>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: EventType.values
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t, child: Text(t.nameEs)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedType = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<SubjectModel>(
                  value: selectedSubject,
                  decoration: const InputDecoration(labelText: 'Materia'),
                  items: subjects
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedSubject = v!),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha'),
                  subtitle: Text(
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setDialogState(() => selectedDate = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hora'),
                  subtitle: Text(
                    '${selectedTime.hour}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (t != null) setDialogState(() => selectedTime = t);
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (eventToEdit != null)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Eliminar evento'),
                      content: const Text(
                        '¿Estás seguro de eliminar este evento?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.errorColor,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await _db.deleteEvent(eventToEdit.syncId);
                    await NotificationService.instance.cancelNotification(
                      eventToEdit.syncId.hashCode,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _loadEvents();
                    }
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                ),
                child: const Text('Eliminar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty || selectedSubject == null)
                  return;

                final dateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final newEvent = EventModel(
                  syncId: eventToEdit?.syncId ?? const Uuid().v4(),
                  subjectId: selectedSubject!.syncId,
                  title: titleController.text,
                  type: selectedType,
                  dateTime: dateTime,
                  hasReminder: true, // Mantener o leer de preferencias (TODO)
                  isSynced: false,
                );

                await _db.saveEvent(newEvent);

                // Reprogramar notificación
                if (newEvent.hasReminder &&
                    user != null &&
                    user.notificationsEnabled) {
                  try {
                    // Cancelar anterior si existía
                    await NotificationService.instance.cancelNotification(
                      newEvent.syncId.hashCode,
                    );

                    for (final offset in user.notificationOffsets) {
                      final scheduledDate = newEvent.dateTime.subtract(
                        Duration(minutes: offset),
                      );
                      if (scheduledDate.isAfter(DateTime.now())) {
                        final id = newEvent.syncId.hashCode + offset; // Dif ID
                        String timeDesc;
                        if (offset < 60) {
                          timeDesc = 'en $offset min';
                        } else if (offset < 1440) {
                          timeDesc = 'en ${offset ~/ 60} horas';
                        } else {
                          timeDesc = 'mañana';
                        }

                        await NotificationService.instance.scheduleNotification(
                          id: id,
                          title: 'Recordatorio: ${newEvent.title}',
                          body:
                              '${selectedSubject!.name} - ${newEvent.type.nameEs} ($timeDesc)',
                          scheduledDate: scheduledDate,
                        );
                      }
                    }
                  } catch (e) {
                    debugPrint('Error programando notificaciones: $e');
                  }
                } else if (!user.notificationsEnabled) {
                  await NotificationService.instance.cancelNotification(
                    newEvent.syncId.hashCode,
                  );
                }

                if (mounted) {
                  Navigator.pop(context);
                  _loadEvents();
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
