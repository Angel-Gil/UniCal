import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../services/local_database_service.dart';
import '../../services/auth_service.dart';
import '../../services/update_service.dart';
import '../../services/widget_service.dart';
import '../../services/sync_service.dart';

/// Pantalla principal / Dashboard
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = LocalDatabaseService.instance;
  final _auth = AuthService.instance;

  List<SemesterModel> _semesters = [];
  List<SubjectModel> _currentSubjects = [];
  List<EventModel> _upcomingEvents = [];
  SemesterModel? _activeSemester;
  UserModel? _currentUser;
  bool _isLoading = true;

  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _auth.authState.addListener(_loadData);
    _dataSubscription = _db.onDataChanged.listen((_) {
      if (mounted) _loadData();
    });
    _loadData();
    // Verificar actualizaciones después de un breve delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.showUpdateDialogIfNeeded(context);
    });
  }

  @override
  void dispose() {
    _auth.authState.removeListener(_loadData);
    _dataSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final user = _db.getCurrentUser();
    if (user != null) {
      final semesters = _db.getSemesters(user.uid);
      final activeSemester = semesters.isEmpty ? null : semesters.first;
      final subjects = activeSemester != null
          ? _db.getSubjects(activeSemester.syncId)
          : <SubjectModel>[];
      final events = _db.getUpcomingEvents(user.uid);

      setState(() {
        _currentUser = user;
        _semesters = semesters;
        _activeSemester = activeSemester;
        _currentSubjects = subjects;
        _upcomingEvents = events;
        _isLoading = false;
      });

      // Update home widget with latest schedule
      WidgetService.updateNextClassWidget();

      // Silent auto-backup (no notification to user)
      if (!AuthService.instance.isGuest) {
        // ignore errors silently
        try {
          await SyncService.instance.backupData();
        } catch (_) {}
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('UniCal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notificaciones próximamente')),
              );
            },
            tooltip: 'Notificaciones',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreetingCard(context),
                    const SizedBox(height: 24),
                    _buildQuickActions(context),
                    const SizedBox(height: 24),
                    _buildCurrentSemesterSection(context),
                    const SizedBox(height: 24),
                    _buildUpcomingEventsSection(context),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showAddOptions(context);
        },
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }

  Widget _buildGreetingCard(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    String greeting;
    IconData icon;

    if (hour < 12) {
      greeting = 'Buenos días';
      icon = Icons.wb_sunny_outlined;
    } else if (hour < 18) {
      greeting = 'Buenas tardes';
      icon = Icons.wb_cloudy_outlined;
    } else {
      greeting = 'Buenas noches';
      icon = Icons.nightlight_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      greeting,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _currentUser?.name ?? 'Estudiante',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _activeSemester?.name ?? 'Sin semestre activo',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  '${_currentSubjects.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Materias',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.school_outlined,
            label: 'Semestres',
            color: AppTheme.primaryColor,
            onTap: () => context.push('/semesters'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.book_outlined,
            label: 'Materias',
            color: AppTheme.secondaryColor,
            onTap: () {
              if (_activeSemester != null) {
                context.push('/semester/${_activeSemester!.syncId}');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Crea un semestre primero')),
                );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.history_outlined,
            label: 'Historial',
            color: AppTheme.accentColor,
            onTap: () {
              context.push('/semesters');
              // Navegar a semestres archivados
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Activa "Mostrar archivados" para ver el historial',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentSemesterSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Materias actuales',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_currentSubjects.isNotEmpty)
              TextButton(
                onPressed: () {
                  if (_activeSemester != null) {
                    context.push('/semester/${_activeSemester!.syncId}');
                  }
                },
                child: const Text('Ver todas'),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_currentSubjects.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No hay materias',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_activeSemester != null) {
                        context.push('/semester/${_activeSemester!.syncId}');
                      } else {
                        context.push('/semesters');
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: Text(
                      _activeSemester != null
                          ? 'Agregar materia'
                          : 'Crear semestre',
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(
            _currentSubjects.length > 3 ? 3 : _currentSubjects.length,
            (index) {
              final subject = _currentSubjects[index];
              final schedules = _db.getSchedules(subject.syncId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SubjectCard(
                  subject: subject,
                  schedules: schedules,
                  onTap: () => context.push('/subject/${subject.syncId}'),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildUpcomingEventsSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Próximos eventos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/calendar'),
              child: const Text('Ver calendario'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_upcomingEvents.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Sin eventos próximos',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          )
        else
          ...List.generate(
            _upcomingEvents.length > 3 ? 3 : _upcomingEvents.length,
            (index) {
              final event = _upcomingEvents[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EventCard(event: event),
              );
            },
          ),
      ],
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Nuevo semestre'),
              onTap: () {
                Navigator.pop(context);
                context.push('/semesters');
              },
            ),
            ListTile(
              leading: const Icon(Icons.book_outlined),
              title: const Text('Nueva materia'),
              onTap: () {
                Navigator.pop(context);
                if (_activeSemester != null) {
                  context.push('/semester/${_activeSemester!.syncId}');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Crea un semestre primero')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Nuevo evento'),
              onTap: () {
                Navigator.pop(context);
                context.go('/calendar');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de acción rápida
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de materia
class _SubjectCard extends StatelessWidget {
  final SubjectModel subject;
  final List<ScheduleModel> schedules;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.subject,
    required this.schedules,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(subject.colorValue);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subject.professor != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subject.professor!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                    if (schedules.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        schedules
                            .map((s) => '${s.shortDayName} ${s.startTime}')
                            .join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card de evento
class _EventCard extends StatelessWidget {
  final EventModel event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.primaryColor;

    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            (event.type == EventType.partial ||
                    event.type == EventType.finalExam)
                ? Icons.quiz_outlined
                : Icons.assignment_outlined,
            color: color,
          ),
        ),
        title: Text(event.title, style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${event.dateTime.day}/${event.dateTime.month}/${event.dateTime.year} • ${event.dateTime.hour}:${event.dateTime.minute.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}
