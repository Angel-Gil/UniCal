import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

// Screens
import '../screens/splash/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/semesters/semesters_screen.dart';
import '../screens/semesters/semester_detail_screen.dart';
import '../screens/subjects/subject_detail_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/auth_service.dart';

/// Configuración de rutas de la aplicación
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: AuthService.instance.authState,
    redirect: (context, state) {
      final isLoggedIn = AuthService.instance.isLoggedIn;
      final path = state.uri.path;

      // Rutas públicas (no requieren auth)
      const publicRoutes = ['/', '/login', '/register'];
      final isPublicRoute = publicRoutes.contains(path);

      // Deep links son públicos
      final isDeepLink = path.startsWith('/p/');

      if (!isLoggedIn && !isPublicRoute && !isDeepLink) {
        return '/login';
      }

      final isGuest = AuthService.instance.isGuest;
      if (isLoggedIn && !isGuest && (path == '/login' || path == '/register')) {
        return '/home';
      }

      return null;
    },
    routes: [
      // Deep Link Handler
      GoRoute(
        path: '/p/:code',
        redirect: (context, state) {
          final code = state.pathParameters['code'];
          if (code == null) return '/home';

          if (code.startsWith('share_')) {
            final shareId = code.substring(6);
            // Redirigir a pantalla de semestres con diálogo de importar
            // Como no podemos pasar argumentos complejos fácilmente en redirect,
            // podemos usar query parameters o una ruta específica de importación.
            return '/semesters?import=$shareId';
          } else if (code.startsWith('auth_')) {
            // Firebase envía oobCode en query params
            final oobCode = state.uri.queryParameters['oobCode'];
            if (oobCode != null) {
              return '/login?resetToken=$oobCode';
            }
            // Fallback para token en path
            if (code.length > 5 && code != 'auth_reset') {
              final token = code.substring(5);
              return '/login?resetToken=$token';
            }
            return '/login';
          } else if (code.startsWith('event_')) {
            final eventId = code.substring(6);
            // Redirigir a calendario y enfocar evento (complejo, por ahora calendario)
            return '/calendar?eventId=$eventId';
          }

          return '/home';
        },
      ),
      // Splash Screen
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth Routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // Main App Routes (con shell para bottom nav)
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/schedule',
            name: 'schedule',
            builder: (context, state) => const ScheduleScreen(),
          ),
          GoRoute(
            path: '/calendar',
            name: 'calendar',
            builder: (context, state) => const CalendarScreen(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      // Semesters
      GoRoute(
        path: '/semesters',
        name: 'semesters',
        builder: (context, state) => const SemestersScreen(),
      ),
      GoRoute(
        path: '/semester/:id',
        name: 'semester-detail',
        builder: (context, state) {
          final semesterId = state.pathParameters['id']!;
          return SemesterDetailScreen(semesterId: semesterId);
        },
      ),

      // Subjects
      GoRoute(
        path: '/subject/:id',
        name: 'subject-detail',
        builder: (context, state) {
          final subjectId = state.pathParameters['id']!;
          return SubjectDetailScreen(subjectId: subjectId);
        },
      ),
    ],

    // Manejo de errores
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Página no encontrada',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.uri.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('Ir al inicio'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shell principal con navegación inferior
class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _routes = ['/home', '/schedule', '/calendar', '/settings'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateIndex();
  }

  void _updateIndex() {
    final location = GoRouterState.of(context).uri.path;
    final index = _routes.indexWhere((route) => location.startsWith(route));
    if (index != -1 && index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          context.go(_routes[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Horario',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
