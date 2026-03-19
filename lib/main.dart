import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'services/local_database_service.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notification_service.dart';
import 'models/models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Firebase
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyBuPf_cLwcAJdwPwAupRMOjatXB0fa_JJY',
      appId: '1:359464262173:android:7352c78dac28da3150c4f4',
      messagingSenderId: '359464262173',
      projectId: 'calendario-a0750',
      storageBucket: 'calendario-a0750.firebasestorage.app',
    ),
  );

  // Inicializar servicios
  await LocalDatabaseService.instance.initialize();
  await AuthService.instance.initialize();
  await SyncService.instance.initialize();
  await NotificationService.instance.initialize(); // Init Notifications

  // Inicializar formato de fechas
  await initializeDateFormatting('es_ES', null);

  runApp(const CalendarioAcademicoApp());
}

class CalendarioAcademicoApp extends StatelessWidget {
  const CalendarioAcademicoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: AuthService.instance.authState,
      builder: (context, user, _) {
        ThemeMode themeMode = ThemeMode.system;
        if (user != null) {
          switch (user.themeMode) {
            case 'light':
              themeMode = ThemeMode.light;
              break;
            case 'dark':
              themeMode = ThemeMode.dark;
              break;
            case 'system':
            default:
              themeMode = ThemeMode.system;
              break;
          }
        }

        return MaterialApp.router(
          title: 'UniCal',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}
