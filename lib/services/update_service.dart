import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Servicio de verificación de actualizaciones usando GitHub Tags/Releases.
class UpdateService {
  static UpdateService? _instance;
  static UpdateService get instance => _instance ??= UpdateService._();

  UpdateService._();

  static const String _githubRepo = 'Angel-Gil/UniCal';
  static const String _releasesUrl =
      'https://github.com/Angel-Gil/UniCal/releases';

  String? _currentVersion;

  /// Inicializa el servicio obteniendo la versión actual de la app.
  Future<void> initialize() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version; // e.g., "1.0.0"
    debugPrint('UpdateService: Versión actual: $_currentVersion');
  }

  /// Verifica si hay una nueva versión disponible.
  /// Retorna la nueva versión si existe, null si está al día.
  Future<String?> checkForUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/$_githubRepo/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestTag = data['tag_name'] as String; // e.g., "v1.0.1"
        final latestVersion = latestTag.replaceFirst('v', ''); // "1.0.1"

        debugPrint('UpdateService: Última versión en GitHub: $latestVersion');

        if (_isNewerVersion(latestVersion, _currentVersion ?? '0.0.0')) {
          return latestVersion;
        }
      } else if (response.statusCode == 404) {
        debugPrint('UpdateService: No hay releases publicados aún.');
      } else {
        debugPrint('UpdateService: Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('UpdateService: Error verificando actualización: $e');
    }
    return null;
  }

  /// Compara dos versiones semánticas. Retorna true si [remote] es más nueva que [local].
  bool _isNewerVersion(String remote, String local) {
    final remoteParts = remote.split('.').map(int.tryParse).toList();
    final localParts = local.split('.').map(int.tryParse).toList();

    for (int i = 0; i < 3; i++) {
      final r = (i < remoteParts.length ? remoteParts[i] : 0) ?? 0;
      final l = (i < localParts.length ? localParts[i] : 0) ?? 0;

      if (r > l) return true;
      if (r < l) return false;
    }
    return false; // Son iguales
  }

  /// Abre la página de releases en GitHub para descargar.
  Future<void> openReleasesPage() async {
    final uri = Uri.parse('$_releasesUrl/latest');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Muestra un diálogo de actualización disponible.
  static Future<void> showUpdateDialogIfNeeded(BuildContext context) async {
    final service = UpdateService.instance;
    if (service._currentVersion == null) {
      await service.initialize();
    }

    final newVersion = await service.checkForUpdate();
    if (newVersion != null && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update, size: 48, color: Colors.blue),
          title: const Text('Actualización disponible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Versión actual: ${service._currentVersion}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                'Nueva versión: v$newVersion',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Te recomendamos actualizar para obtener las últimas mejoras y correcciones.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Después'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                service.openReleasesPage();
              },
              icon: const Icon(Icons.download),
              label: const Text('Descargar'),
            ),
          ],
        ),
      );
    }
  }
}
