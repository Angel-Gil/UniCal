import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../services/academic_history_pdf.dart';
import '../../services/ics_export_service.dart';

/// Pantalla de configuración
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.authState.addListener(_updateState);
  }

  @override
  void dispose() {
    AuthService.instance.authState.removeListener(_updateState);
    super.dispose();
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AuthService.instance.currentUser;
    final syncService = SyncService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Perfil
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  user?.name.isNotEmpty == true
                      ? user!.name[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(user?.name ?? 'Usuario'),
              subtitle: Text(user?.email ?? 'Sin correo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showEditProfileDialog(context),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Cuenta',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.grade_outlined,
            title: 'Escala de notas',
            subtitle:
                '${user?.gradeScaleMin.toStringAsFixed(0) ?? '0'} - ${user?.gradeScaleMax.toStringAsFixed(0) ?? '5'}',
            onTap: () => _showGradeScaleDialog(context),
          ),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notificaciones',
            onTap: () => _showNotificationSettings(),
          ),

          if (!AuthService.instance.isGuest) ...[
            const SizedBox(height: 24),
            Text(
              'Sincronización',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),

            StreamBuilder<SyncStatus>(
              stream: syncService.syncStatus,
              builder: (context, snapshot) {
                final status = snapshot.data;
                return Column(
                  children: [
                    _SettingsTile(
                      icon: syncService.isOnline
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      title: 'Estado',
                      subtitle: syncService.isOnline
                          ? 'Conectado'
                          : 'Sin conexión',
                    ),
                    _SettingsTile(
                      icon: Icons.sync,
                      title: 'Sincronizar ahora',
                      subtitle: _isSyncing
                          ? 'Sincronizando...'
                          : 'Última: ${_formatLastSync(status?.lastSyncAt)}',
                      trailing: _isSyncing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: _isSyncing ? null : () => _syncNow(),
                    ),
                    _SettingsTile(
                      icon: Icons.cloud_upload_outlined,
                      title: 'Copia de seguridad (Backup)',
                      subtitle: 'Forzar subida de datos',
                      onTap: _isSyncing ? null : () => _backupData(context),
                    ),
                    _SettingsTile(
                      icon: Icons.cloud_download_outlined,
                      title: 'Restaurar datos',
                      subtitle: 'Descargar desde nube',
                      onTap: _isSyncing ? null : () => _restoreData(context),
                    ),
                    _SettingsTile(
                      icon: Icons.picture_as_pdf,
                      title: 'Exportar Historial Académico',
                      subtitle: 'Descargar en PDF',
                      onTap: () => AcademicHistoryPdf.generateAndShare(context),
                    ),
                    _SettingsTile(
                      icon: Icons.calendar_month,
                      title: 'Exportar Horario',
                      subtitle: 'Descargar en formato .ics',
                      onTap: () => _exportIcs(context),
                    ),
                  ],
                );
              },
            ),
          ],

          const SizedBox(height: 24),
          Text(
            'Calendario y Tiempo',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.access_time,
            title: 'Formato de hora',
            trailing: DropdownButton<String>(
              value: user?.timeFormat ?? '12h',
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: '12h', child: Text('12 horas')),
                DropdownMenuItem(value: '24h', child: Text('24 horas')),
              ],
              onChanged: (v) {
                if (v != null) {
                  AuthService.instance.updateProfile(timeFormat: v);
                }
              },
            ),
          ),
          _SettingsTile(
            icon: Icons.view_week,
            title: 'Inicio de semana',
            trailing: DropdownButton<int>(
              value: user?.startOfWeek ?? 1,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('Lunes')),
                DropdownMenuItem(value: 7, child: Text('Domingo')),
              ],
              onChanged: (v) {
                if (v != null) {
                  AuthService.instance.updateProfile(startOfWeek: v);
                }
              },
            ),
          ),
          _SettingsTile(
            icon: Icons.weekend_outlined,
            title: 'Mostrar fines de semana',
            trailing: Switch(
              value: user?.showWeekends ?? true,
              onChanged: (v) {
                AuthService.instance.updateProfile(showWeekends: v);
              },
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Apariencia',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          if (!kIsWeb)
            _SettingsTile(
              icon: Icons.widgets_outlined,
              title: 'Personalizar Widget',
              subtitle: 'Colores, estilo y preferencias del widget de inicio',
              onTap: () => context.push('/settings/widget'),
            ),
          _SettingsTile(
            icon: Icons.color_lens_outlined,
            title: 'Tema visual',
            trailing: DropdownButton<String>(
              value: user?.themeMode ?? 'system',
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'light', child: Text('Claro')),
                DropdownMenuItem(value: 'dark', child: Text('Oscuro')),
                DropdownMenuItem(value: 'system', child: Text('Sistema')),
              ],
              onChanged: (v) {
                if (v != null) {
                  AuthService.instance.updateProfile(themeMode: v);
                }
              },
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Acerca de',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '...';
              return _SettingsTile(
                icon: Icons.info_outline,
                title: 'Versión',
                subtitle: 'v$version',
              );
            },
          ),
          _SettingsTile(
            icon: Icons.coffee,
            title: 'Apóyame ☕',
            subtitle: 'Invítame un café',
            onTap: () async {
              final uri = Uri.parse('https://buymeacoffee.com/angelgil05');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          _SettingsTile(
            icon: Icons.code,
            title: 'Código fuente',
            subtitle: 'Ver en GitHub',
            onTap: () async {
              final uri = Uri.parse(
                'https://github.com/Angel-Gil/UniCal',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),

          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: Icon(
              AuthService.instance.isGuest ? Icons.login : Icons.logout,
            ),
            label: Text(
              AuthService.instance.isGuest ? 'Iniciar sesión' : 'Cerrar sesión',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AuthService.instance.isGuest
                  ? theme.colorScheme.primary
                  : AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          if (!AuthService.instance.isGuest) ...[
            const SizedBox(height: 48),
            Text(
              'Zona de Peligro',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppTheme.errorColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: AppTheme.errorColor.withOpacity(0.1),
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: AppTheme.errorColor,
                ),
                title: const Text(
                  'Eliminar cuenta',
                  style: TextStyle(
                    color: AppTheme.errorColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Esta acción es irreversible',
                  style: TextStyle(color: AppTheme.errorColor),
                ),
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _exportIcs(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generando archivo .ics...'))
    );
    await IcsExportService.exportCurrentSemester(context);
  }

  String _formatLastSync(DateTime? date) {
    if (date == null) return 'Nunca';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    await SyncService.instance.syncNow();
    if (mounted) setState(() => _isSyncing = false);
  }

  Future<void> _backupData(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Crear copia de seguridad?'),
        content: const Text(
          'Esto subirá todos tus datos locales a la nube, sobrescribiendo lo que haya allí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSyncing = true);
    final result = await SyncService.instance.backupData();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success
              ? AppTheme.successColor
              : AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _restoreData(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Restaurar datos?'),
        content: const Text(
          'Esto descargará tus datos de la nube y podría sobrescribir cambios locales no guardados. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSyncing = true);
    final result = await SyncService.instance.restoreData();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success
              ? AppTheme.successColor
              : AppTheme.errorColor,
        ),
      );
    }
  }

  void _showEditProfileDialog(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    final nameController = TextEditingController(text: user.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar perfil'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await AuthService.instance.updateProfile(
                name: nameController.text,
              );
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showGradeScaleDialog(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    double minGrade = user.gradeScaleMin;
    double maxGrade = user.gradeScaleMax;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Escala de notas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Mínimo'),
                      controller: TextEditingController(
                        text: minGrade.toStringAsFixed(0),
                      ),
                      onChanged: (v) => minGrade = double.tryParse(v) ?? 0,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Máximo'),
                      controller: TextEditingController(
                        text: maxGrade.toStringAsFixed(0),
                      ),
                      onChanged: (v) => maxGrade = double.tryParse(v) ?? 5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('0-5'),
                    selected: minGrade == 0 && maxGrade == 5,
                    onSelected: (_) => setDialogState(() {
                      minGrade = 0;
                      maxGrade = 5;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('0-10'),
                    selected: minGrade == 0 && maxGrade == 10,
                    onSelected: (_) => setDialogState(() {
                      minGrade = 0;
                      maxGrade = 10;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('0-100'),
                    selected: minGrade == 0 && maxGrade == 100,
                    onSelected: (_) => setDialogState(() {
                      minGrade = 0;
                      maxGrade = 100;
                    }),
                  ),
                ],
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
                await AuthService.instance.updateProfile(
                  gradeScaleMin: minGrade,
                  gradeScaleMax: maxGrade,
                );
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationSettings() {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    bool enabled = user.notificationsEnabled;
    List<int> offsets = List.from(user.notificationOffsets);

    String _formatOffset(int minutes) {
      if (minutes >= 1440) {
        final days = minutes ~/ 1440;
        return '$days día${days > 1 ? 's' : ''} antes';
      } else if (minutes >= 60) {
        final hours = minutes ~/ 60;
        return '$hours hora${hours > 1 ? 's' : ''} antes';
      } else {
        return '$minutes min antes';
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Notificaciones'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Activar notificaciones'),
                value: enabled,
                onChanged: (v) => setDialogState(() => enabled = v),
              ),
              if (enabled) ...[
                const Divider(),
                const Text('Recordatorios:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: offsets
                      .map(
                        (offset) => Chip(
                          label: Text(
                            _formatOffset(offset),
                            style: const TextStyle(fontSize: 12),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setDialogState(() => offsets.remove(offset)),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    int amount = 15;
                    String unit = 'min';
                    showDialog(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setInner) => AlertDialog(
                          title: const Text('Agregar recordatorio'),
                          content: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Cantidad',
                                  ),
                                  onChanged: (v) =>
                                      amount = int.tryParse(v) ?? 15,
                                  controller: TextEditingController(text: '15'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: unit,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'min',
                                      child: Text('Minutos'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'hr',
                                      child: Text('Horas'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'day',
                                      child: Text('Días'),
                                    ),
                                  ],
                                  onChanged: (v) => setInner(() => unit = v!),
                                  decoration: const InputDecoration(
                                    labelText: 'Unidad',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                int minutes = amount;
                                if (unit == 'hr') minutes = amount * 60;
                                if (unit == 'day') minutes = amount * 1440;
                                if (minutes > 0 && !offsets.contains(minutes)) {
                                  setDialogState(() {
                                    offsets.add(minutes);
                                    offsets.sort();
                                  });
                                }
                                Navigator.pop(ctx);
                              },
                              child: const Text('Agregar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar recordatorio'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                await AuthService.instance.updateProfile(
                  notificationsEnabled: enabled,
                  notificationOffsets: offsets,
                );
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar cuenta permanentemente?'),
        content: const Text(
          'Se borrarán TODOS tus datos: semestres, materias, notas y eventos. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showDeleteAccountPasswordDialog(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountPasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Confirmar eliminación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ingresa tu contraseña para confirmar:'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty) return;

                      setState(() => isLoading = true);
                      try {
                        await AuthService.instance.deleteAccount(
                          passwordController.text,
                        );
                        if (context.mounted) {
                          Navigator.pop(context); // Close dialog
                          context.go('/login');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cuenta eliminada')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() => isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppTheme.errorColor,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
              ),
              child: const Text(
                'Confirmar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final isGuest = AuthService.instance.isGuest;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isGuest ? '¿Iniciar sesión?' : '¿Cerrar sesión?'),
        content: Text(
          isGuest
              ? 'Podrás acceder a tu cuenta o crear una nueva. Tus datos de invitado permanecerán en este dispositivo.'
              : 'Tus datos se mantendrán guardados localmente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (isGuest) {
                // Para invitado, solo navegamos al login. El AuthService se actualizará al loguearse.
                context.go('/login');
              } else {
                await AuthService.instance.logout();
                if (mounted) {
                  context.go('/login');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isGuest
                  ? Theme.of(context).colorScheme.primary
                  : AppTheme.errorColor,
            ),
            child: Text(isGuest ? 'Ir al Login' : 'Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing:
            trailing ??
            (onTap != null ? const Icon(Icons.chevron_right) : null),
        onTap: onTap,
      ),
    );
  }
}
