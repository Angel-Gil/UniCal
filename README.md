<p align="center">
  <img src="assets/images/logo.png" alt="UniCal Logo" width="120">
</p>

<h1 align="center">📅 UniCal</h1>

<p align="center">
  <strong>Tu vida académica, perfectamente organizada.</strong><br>
  Aplicación integral para la gestión universitaria de semestres, materias, horarios dinámicos, cortes de notas, cálculo de promedios ponderados y widgets nativos.
</p>

<p align="center">
  <a href="https://unical.web.app"><img src="https://img.shields.io/badge/Web-unical.web.app-4285F4?style=for-the-badge&logo=firebase&logoColor=white" alt="Sitio Web"></a>
  <a href="https://unical.web.app/app"><img src="https://img.shields.io/badge/App_Web-Disponible-673AB7?style=for-the-badge&logo=flutter&logoColor=white" alt="App Web"></a>
  <a href="https://github.com/Angel-Gil/UniCal/releases/latest"><img src="https://img.shields.io/badge/Android-Disponible-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Versión  Android"></a>
  <a href="https://buymeacoffee.com/angelgil05"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me a Coffee"></a>
</p>

---

## 🌐 Ecosistema Web en Firebase Hosting

UniCal cuenta con una arquitectura web unificada alojada en **Firebase Hosting** (`https://unical.web.app`):

- **Landing Page (`/`)**: Presentación oficial de la app con simulador interactivo de widgets, ficha técnica y enlaces de descarga directa del APK.
- **UniCal Web (`/app`)**: La aplicación completa compilada con Flutter Web (soporte SPA con `go_router`).
- **Visor Autónomo QR (`/data?d=...`)**: Visor ultraligero en cliente para previsualizar horarios o semestres compartidos sin base de datos ni servidores intermediarios.

---

## ✨ Características Principales

| Módulo | Descripción |
|---|---|
| 📚 **Gestión de Semestres** | Organiza tus periodos académicos, materias asociadas y promedios históricos. |
| 📝 **Cortes y Calificaciones** | Configuración flexible de cortes evaluativos con pesos porcentuales, notas acumuladas y definitivas en tiempo real. |
| 🎯 **Simulador Dinámico de Notas** | Simula notas faltantes materia por materia conservando las calificaciones ya registradas. Calcula la nota requerida para aprobar o alcanzar un PGA meta. |
| 🗓️ **Horario Inteligente Dinámico** | Cuadrícula semanal que ajusta sus horas límite automáticamente según tu jornada real de clases, evitando horas vacías innecesarias. |
| 🔄 **Compartir sin Base de Datos** | Comparte horarios y semestres completos vía código QR o enlaces cortos comprimidos (`ZLib + Base64Url`) de forma 100% autónoma. |
| 📱 **Widgets Nativos Android** | Consulta tu próxima clase, salón y promedios directamente desde la pantalla de inicio de tu celular. |
| 📄 **Exportación a PDF** | Genera reportes elegantes en PDF de tus horarios semanales y boletas de calificaciones. |
| ☁️ **Offline-First & Sincronización** | Base de datos local cifrada con **Hive + AES-256** y sincronización incremental opcional con Firebase. |
| 🔔 **Notificaciones Inteligentes** | Recordatorios configurables antes de iniciar cada clase o evaluación. |
| 🎓 **Integración SIRES (FUP)** | Asistente de importación para estudiantes de la Fundación Universitaria de Popayán con soporte 2FA. |

---

## 📱 Plataformas Soportadas

| Plataforma | Estado | Canal |
|---|---|---|
| **Android** | ✅ Disponible | [Descargar APK en GitHub Releases](https://github.com/Angel-Gil/UniCal/releases/latest) |
| **Web (SPA)** | ✅ Disponible | [unical.web.app/app](https://unical.web.app/app) |
| **Windows** | 🔜 Próximamente | En desarrollo nativo |

---

## 🛠️ Tecnologías y Arquitectura

- **Framework:** [Flutter](https://flutter.dev/) (canal stable, Dart 3)
- **Gestión de Estado:** [Riverpod 2.x](https://riverpod.dev/) (`ChangeNotifierProvider`, `StateNotifierProvider`, inmutabilidad)
- **Ruteo:** [go_router](https://pub.dev/packages/go_router) con soporte de deep links y App Links Android
- **Persistencia Local:** [Hive](https://pub.dev/packages/hive) cifrado con `HiveAesCipher` (AES-256) + `FlutterSecureStorage`
- **Infraestructura Cloud:**
  - **Firebase Auth:** Autenticación con Google, correo y modo invitado.
  - **Cloud Firestore:** Respaldo y sincronización en la nube.
  - **Firebase Hosting:** Distribución web global con CDN.
  - **GitHub Actions:** CI/CD para compilación y despliegue automático ante cada Release.

---

## 💻 Desarrollo Local

### Requisitos previos:
- Flutter SDK (≥ 3.24.0)
- Android Studio / VS Code con extensiones de Flutter y Dart
- Dispositivo Android físico o emulador

### Pasos de instalación:

```bash
# 1. Clonar el repositorio
git clone https://github.com/Angel-Gil/UniCal.git
cd UniCal

# 2. Descargar dependencias
flutter pub get

# 3. Ejecutar en tu dispositivo o emulador
flutter run

# 4. (Opcional) Compilar para la web
flutter build web --release --base-href /app/
```

---

## 📄 Licencia y Créditos

Desarrollado con ❤️ por **[Angel Gil](https://github.com/Angel-Gil)**.  
Distribuido bajo la licencia MIT. Consulta el archivo `LICENSE` para más información.

