import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../services/local_database_service.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../services/share_service.dart'; // Ensure it's available or via services.dart
import 'scan_qr_screen.dart';
import 'trash_screen.dart';

/// Pantalla de lista de semestres
class SemestersScreen extends StatefulWidget {
  const SemestersScreen({super.key});

  @override
  State<SemestersScreen> createState() => _SemestersScreenState();
}

class _SemestersScreenState extends State<SemestersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = LocalDatabaseService.instance;

  List<SemesterModel> _activeSemesters = [];
  List<SemesterModel> _archivedSemesters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSemesters();
  }

  Future<void> _loadSemesters() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() => _isLoading = true);

    final all = _db.getSemesters(user.uid, includeArchived: true);

    setState(() {
      _activeSemesters = all
          .where((s) => s.status == SemesterStatus.active)
          .toList();
      _archivedSemesters = all
          .where((s) => s.status == SemesterStatus.archived)
          .toList();
      _isLoading = false;
    });

    // Check for import parameter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = GoRouterState.of(context);
      final importId = state.uri.queryParameters['import'];
      if (importId != null) {
        // Clear param to avoid loop
        context.replace('/semesters');
        // Auto-execute import from deep link
        _executeImport(importId);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semestres'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _importSemesterDialog(context),
            tooltip: 'Importar Semestre',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () => _backupData(),
            tooltip: 'Subir cambios',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              );
              _loadSemesters();
            },
            tooltip: 'Papelera',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Activos'),
            Tab(text: 'Archivados'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSemesterList(_activeSemesters, isArchived: false),
                _buildSemesterList(_archivedSemesters, isArchived: true),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSemesterDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Semestre'),
      ),
    );
  }

  // ... existing methods ...

  void _importSemesterDialog(BuildContext context, {String? initialCode}) {
    final controller = TextEditingController(text: initialCode ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar Semestre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa el código compartido o escanea el QR.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Código',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final code = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScanQrScreen()),
                );
                if (code != null && code is String) {
                  final extractedId = _extractShareId(code);
                  controller.text = extractedId;

                  if (extractedId.isNotEmpty) {
                    Navigator.pop(context);
                    _executeImport(extractedId);
                  }
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear QR'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) {
                return;
              }
              Navigator.pop(context);
              _executeImport(controller.text);
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeImport(String code) async {
    setState(() => _isLoading = true);
    try {
      await ShareService.instance.importSemester(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semestre importado correctamente')),
        );
        _loadSemesters();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _extractShareId(String code) {
    if (code.contains('/p/share_')) {
      final uri = Uri.tryParse(code);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        if (last.startsWith('share_')) {
          return last.substring(6);
        }
      }
    }
    if (code.startsWith('share_')) {
      return code.substring(6);
    }
    return code;
  }

  Widget _buildSemesterList(
    List<SemesterModel> semesters, {
    required bool isArchived,
  }) {
    if (semesters.isEmpty) {
      return _buildEmptyState(
        icon: isArchived ? Icons.archive_outlined : Icons.school_outlined,
        title: isArchived
            ? 'Sin semestres archivados'
            : 'Sin semestres activos',
        subtitle: isArchived
            ? 'Los semestres archivados aparecerán aquí'
            : 'Crea tu primer semestre para comenzar',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSemesters,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: semesters.length,
        itemBuilder: (context, index) {
          final semester = semesters[index];
          final subjects = _db.getSubjects(semester.syncId);

          return _SemesterCard(
            semester: semester,
            subjectCount: subjects.length,
            onTap: () => context.push('/semester/${semester.syncId}'),
            onArchive: isArchived ? null : () => _archiveSemester(semester),
            onRestore: isArchived ? () => _restoreSemester(semester) : null,
            onDelete: () => _deleteSemester(semester),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSemesterDialog(
    BuildContext context, [
    SemesterModel? existing,
  ]) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    DateTime startDate = existing?.startDate ?? DateTime.now();
    DateTime endDate =
        existing?.endDate ?? DateTime.now().add(const Duration(days: 150));
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nuevo Semestre' : 'Editar Semestre'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del semestre',
                  hintText: 'Ej: 2026-1',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha de inicio'),
                subtitle: Text(
                  '${startDate.day}/${startDate.month}/${startDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: startDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) setDialogState(() => startDate = date);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha de fin'),
                subtitle: Text(
                  '${endDate.day}/${endDate.month}/${endDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: endDate,
                    firstDate: startDate,
                    lastDate: DateTime(2030),
                  );
                  if (date != null) setDialogState(() => endDate = date);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (nameController.text.isEmpty) {
                        return;
                      }
                      setDialogState(() => isLoading = true);

                      final user = AuthService.instance.currentUser;
                      if (user == null) {
                        return;
                      }

                      final semester = SemesterModel(
                        syncId: existing?.syncId ?? const Uuid().v4(),
                        userId: user.uid,
                        name: nameController.text,
                        startDate: startDate,
                        endDate: endDate,
                        status: existing?.status ?? SemesterStatus.active,
                        isSynced: false,
                      );

                      await _db.saveSemester(semester);

                      if (mounted) {
                        Navigator.pop(context);
                        _loadSemesters();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              existing == null
                                  ? 'Semestre creado'
                                  : 'Semestre actualizado',
                            ),
                          ),
                        );
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(existing == null ? 'Crear' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveSemester(SemesterModel semester) async {
    await _db.saveSemester(semester.copyWith(status: SemesterStatus.archived));
    _loadSemesters();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Semestre archivado')));
    }
  }

  Future<void> _restoreSemester(SemesterModel semester) async {
    await _db.saveSemester(semester.copyWith(status: SemesterStatus.active));
    _loadSemesters();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Semestre restaurado')));
    }
  }

  Future<void> _deleteSemester(SemesterModel semester) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar semestre?'),
        content: const Text(
          'El semestre se moverá a la papelera. Podrás restaurarlo desde ahí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deleteSemester(semester.syncId);
      _loadSemesters();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Semestre eliminado')));
      }
    }
  }

  Future<void> _backupData() async {
    if (AuthService.instance.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para hacer backup')),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Subiendo datos...')));

    try {
      await SyncService.instance.backupData();
      _loadSemesters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos subidos correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Card de semestre
class _SemesterCard extends StatelessWidget {
  final SemesterModel semester;
  final int subjectCount;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  const _SemesterCard({
    required this.semester,
    required this.subjectCount,
    required this.onTap,
    this.onArchive,
    this.onRestore,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArchived = semester.status == SemesterStatus.archived;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isArchived ? Icons.archive_outlined : Icons.school,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Semestre ${semester.name}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$subjectCount materias',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (!semester.isSynced)
                    Tooltip(
                      message: 'Pendiente de sincronizar',
                      child: Icon(
                        Icons.cloud_off,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDateRange(semester.startDate, semester.endDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onArchive != null)
                        TextButton.icon(
                          onPressed: onArchive,
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          label: const Text('Archivar'),
                        ),
                      if (onRestore != null)
                        TextButton.icon(
                          onPressed: onRestore,
                          icon: const Icon(Icons.unarchive_outlined, size: 18),
                          label: const Text('Restaurar'),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppTheme.errorColor,
                        ),
                        onPressed: onDelete,
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${months[start.month - 1]} ${start.year} - ${months[end.month - 1]} ${end.year}';
  }
}
