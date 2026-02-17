import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/local_database_service.dart';
import '../semesters/subject_form_screen.dart';

/// Pantalla de detalle de una materia
class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen>
    with SingleTickerProviderStateMixin {
  final _db = LocalDatabaseService.instance;
  late TabController _tabController;

  SubjectModel? _subject;
  List<GradePeriodModel> _periods = [];
  List<EventModel> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final subject = _db.getSubject(widget.subjectId);
    if (subject != null) {
      var periods = _db.getGradePeriods(subject.syncId);
      final events = _db.getEvents(subject.syncId);

      // Si no hay cortes, inicializar los por defecto (Universidad Colombiana típico)
      if (periods.isEmpty) {
        final defaults = [
          GradePeriodModel(
            syncId: const Uuid().v4(),
            subjectId: subject.syncId,
            name: 'Primer Corte',
            percentage: 0.30,
            order: 1,
          ),
          GradePeriodModel(
            syncId: const Uuid().v4(),
            subjectId: subject.syncId,
            name: 'Segundo Corte',
            percentage: 0.35,
            order: 2,
          ),
          GradePeriodModel(
            syncId: const Uuid().v4(),
            subjectId: subject.syncId,
            name: 'Tercer Corte',
            percentage: 0.35,
            order: 3,
          ),
        ];

        for (final p in defaults) {
          await _db.saveGradePeriod(p);
        }
        periods = defaults;
      }

      setState(() {
        _subject = subject;
        _periods = periods;
        _events = events;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double get _currentGrade {
    double total = 0, pct = 0;
    for (final p in _periods) {
      final grade = p.computedGrade;
      if (grade != null) {
        total += grade * p.percentage;
        pct += p.percentage;
      }
    }
    return pct > 0 ? total / pct : 0;
  }

  double get _accumulated {
    return _periods
        .where((p) => p.computedGrade != null)
        .fold(0.0, (s, p) => s + p.computedGrade! * p.percentage);
  }

  double get _required {
    if (_subject == null) return 0;
    final rem = _periods
        .where((p) => p.computedGrade == null)
        .fold(0.0, (s, p) => s + p.percentage);
    return rem > 0 ? (_subject!.passingGrade - _accumulated) / rem : 0;
  }

  SubjectStatus get _status {
    if (_subject == null) return SubjectStatus.inProgress;

    if (_periods.every((p) => p.computedGrade != null)) {
      return _accumulated >= _subject!.passingGrade
          ? SubjectStatus.approved
          : SubjectStatus.failed;
    }

    final maxGrade = AuthService.instance.currentUser?.gradeScaleMax ?? 5.0;

    if (_required > maxGrade) return SubjectStatus.failed;
    if (_required > maxGrade * 0.8) return SubjectStatus.atRisk;
    return SubjectStatus.inProgress;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_subject == null) {
      return const Scaffold(body: Center(child: Text('Materia no encontrada')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_subject!.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar materia',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubjectFormScreen(
                    semesterId: _subject!.semesterId,
                    existing: _subject!,
                  ),
                ),
              );
              if (result == true) _loadData();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Notas'),
            Tab(text: 'Eventos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_gradesTab(), _eventsTab()],
      ),
    );
  }

  Widget _gradesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryCard(),
          const SizedBox(height: 24),
          _statusCard(),
          const SizedBox(height: 24),
          Text(
            'Cortes de evaluación',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._periods.map((p) => _periodCard(p)),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final completed = _periods
        .where((p) => p.obtainedGrade != null)
        .fold(0.0, (s, p) => s + p.percentage);

    final color = Color(_subject!.colorValue);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _subject!.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_subject!.professor != null)
                      Text(
                        _subject!.professor!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
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
                      _currentGrade.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Nota actual',
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
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: completed,
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final (color, icon, title, desc) = switch (_status) {
      SubjectStatus.approved => (
        AppTheme.successColor,
        Icons.check_circle,
        '¡Aprobada!',
        'Felicitaciones',
      ),
      SubjectStatus.failed => (
        AppTheme.errorColor,
        Icons.cancel,
        'Reprobada',
        'No se alcanzó el mínimo',
      ),
      SubjectStatus.atRisk => (
        AppTheme.warningColor,
        Icons.warning_amber,
        'En riesgo',
        'Necesitas promediar ${_required.toStringAsFixed(2)} en lo restante',
      ),
      SubjectStatus.inProgress => (
        AppTheme.infoColor,
        Icons.trending_up,
        'En curso',
        'Necesitas promediar ${_required.toStringAsFixed(2)} en lo restante',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                Text(desc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodCard(GradePeriodModel p) {
    final color = Color(_subject!.colorValue);
    final computed = p.computedGrade;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _editGrade(p),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Text(
                      '${(p.percentage * 100).toInt()}%',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          computed != null
                              ? 'Puntos: ${(computed * p.percentage).toStringAsFixed(2)}'
                              : 'Sin calificar',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  computed != null
                      ? Text(
                          computed.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        )
                      : TextButton(
                          onPressed: () => _editGrade(p),
                          child: const Text('Ingresar'),
                        ),
                ],
              ),
              // Mostrar sub-notas si existen
              if (p.grades.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...p.grades.map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: color.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${g.label} (${(g.weight * 100).toInt()}%)',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          g.grade?.toStringAsFixed(1) ?? '—',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: g.grade != null
                                ? color
                                : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _editGrade(GradePeriodModel p) {
    final maxGrade = AuthService.instance.currentUser?.gradeScaleMax ?? 5.0;
    final nameCtrl = TextEditingController(text: p.name);
    final percentageCtrl = TextEditingController(
      text: (p.percentage * 100).toStringAsFixed(0),
    );

    // Initialize sub-grades list
    List<_GradeEntryUI> entries = p.grades.isEmpty
        ? [] // Empty initially, user can add
        : p.grades
              .map(
                (g) => _GradeEntryUI(
                  labelCtrl: TextEditingController(text: g.label),
                  weightCtrl: TextEditingController(
                    text: (g.weight * 100).toStringAsFixed(0),
                  ),
                  gradeCtrl: TextEditingController(
                    text: g.grade?.toStringAsFixed(1) ?? '',
                  ),
                  id: g.id,
                ),
              )
              .toList();

    // If no entries and no old grade, start with 3 defaults
    if (entries.isEmpty && p.obtainedGrade == null && p.grades.isEmpty) {
      // Don't add defaults — let user choose between simple grade or sub-notes
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double weightSum = entries.fold(0.0, (s, e) {
            final w =
                double.tryParse(e.weightCtrl.text.replaceAll(',', '.')) ?? 0.0;
            return s + w;
          });
          bool weightsValid = entries.isEmpty || (weightSum - 100).abs() < 0.01;

          return AlertDialog(
            title: const Text('Editar Corte'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del corte',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: percentageCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Peso del corte (%)',
                        suffixText: '%',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Notas',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () => setDialogState(() {
                            entries.add(
                              _GradeEntryUI(
                                labelCtrl: TextEditingController(),
                                weightCtrl: TextEditingController(),
                                gradeCtrl: TextEditingController(),
                                id: const Uuid().v4(),
                              ),
                            );
                          }),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Sin sub-notas. Puedes agregar quizzes, talleres, parciales, etc.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    else
                      ...entries.asMap().entries.map((entry) {
                        final i = entry.key;
                        final e = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: e.labelCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Ej: Quiz ${i + 1}',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: e.weightCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: '%',
                                    suffixText: '%',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: e.gradeCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: '/$maxGrade',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppTheme.errorColor,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      setDialogState(() => entries.removeAt(i)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    if (entries.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Suma pesos: ${weightSum.toStringAsFixed(0)}%${weightsValid ? ' ✓' : ' (debe ser 100%)'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: weightsValid
                                ? Colors.green
                                : AppTheme.errorColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: (entries.isNotEmpty && !weightsValid)
                    ? null
                    : () async {
                        final pText = percentageCtrl.text
                            .replaceAll(',', '.')
                            .trim();
                        final pct = double.tryParse(pText);

                        if (pct == null || pct <= 0 || pct > 100) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Porcentaje del corte inválido'),
                            ),
                          );
                          return;
                        }

                        // Build grades list
                        final gradeEntries = <GradeEntry>[];
                        for (final e in entries) {
                          final label = e.labelCtrl.text.trim();
                          final wt = double.tryParse(
                            e.weightCtrl.text.replaceAll(',', '.'),
                          );
                          final gr = e.gradeCtrl.text.trim().isEmpty
                              ? null
                              : double.tryParse(
                                  e.gradeCtrl.text.replaceAll(',', '.'),
                                );

                          if (label.isEmpty || wt == null || wt <= 0) continue;
                          if (gr != null && (gr < 0 || gr > maxGrade)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Nota inválida en "$label"'),
                              ),
                            );
                            return;
                          }
                          gradeEntries.add(
                            GradeEntry(
                              id: e.id,
                              label: label,
                              weight: wt / 100.0,
                              grade: gr,
                            ),
                          );
                        }

                        final updated = GradePeriodModel(
                          syncId: p.syncId,
                          subjectId: p.subjectId,
                          name: nameCtrl.text.isEmpty ? p.name : nameCtrl.text,
                          percentage: pct / 100.0,
                          obtainedGrade: null, // Use grades list instead
                          grades: gradeEntries,
                          order: p.order,
                          dueDate: p.dueDate,
                          createdAt: p.createdAt,
                          updatedAt: DateTime.now(),
                          isSynced: false,
                        );

                        await _db.saveGradePeriod(updated);
                        if (!mounted) return;
                        _loadData();
                        Navigator.pop(context);
                      },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _eventsTab() {
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Sin eventos para esta materia'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        return Card(
          child: ListTile(
            leading: Icon(
              (event.type == EventType.partial ||
                      event.type == EventType.finalExam)
                  ? Icons.quiz_outlined
                  : Icons.assignment_outlined,
              color: Color(_subject!.colorValue),
            ),
            title: Text(event.title),
            subtitle: Text(
              '${event.dateTime.day}/${event.dateTime.month}/${event.dateTime.year} - ${event.dateTime.hour}:${event.dateTime.minute.toString().padLeft(2, '0')}',
            ),
          ),
        );
      },
    );
  }
}

/// Helper para manejar controladores de cada nota en el dialog
class _GradeEntryUI {
  final TextEditingController labelCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController gradeCtrl;
  final String id;

  _GradeEntryUI({
    required this.labelCtrl,
    required this.weightCtrl,
    required this.gradeCtrl,
    required this.id,
  });
}
