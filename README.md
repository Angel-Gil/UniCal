# 📅 UniCal

Aplicación móvil para gestionar tu vida académica: semestres, materias, horarios, notas y más.

<p align="center">
  <img src="assets/images/logo.png" alt="UniCal" width="200">
</p>

## 🌐 Versión Web

**[Accede a UniCal Web](https://unical-phi.vercel.app)** — Versión web de la aplicación  
⚠️ **Nota importante:** La versión web solo funciona correctamente en computadores. En dispositivos móviles la página se verá en blanco.

## ✨ Características

- 📚 **Gestión de Semestres** — Crea, edita, archiva y comparte tus semestres
- 📝 **Materias y Notas** — Registra materias con cortes de evaluación y calcula promedios
- 📊 **Proyección de Notas** — Calcula la nota mínima necesaria para aprobar
- 🗓️ **Horario Semanal** — Visualiza tu horario de clases en formato de grilla
- 📅 ** de Eventos** — Agrega y visualiza eventos académicos
- 🔔 **Notificaciones** — Recordatorios para clases y eventos
- ☁️ **Sincronización en la Nube** — Backup y restauración con Firebase
- 🔗 **Compartir Semestres** — Comparte tu semestre vía QR o enlace
- 🌗 **Tema Oscuro** — Interfaz moderna con soporte para modo oscuro
- 👤 **Modo Invitado** — Usa la app sin necesidad de registro

## 📱 Plataformas

| Plataforma | Estado |
|------------|--------|
| Android    | ✅ Disponible |
| Web        | ✅ Disponible (solo desktop) |
| Windows    | 🔜 Próximamente |

## 📥 Descarga

Descarga la última versión desde [**GitHub Releases**](https://github.com/Angel-Gil/-Universitario/releases/latest).

## 🛠️ Tecnologías

- **Flutter** — Framework multiplataforma
- **Firebase Auth** — Autenticación de usuarios
- **Cloud Firestore** — Base de datos en la nube
- **Hive** — Base de datos local (offline-first)
- **GoRouter** — Navegación declarativa

## 🚀 Desarrollo Local

### Requisitos

- Flutter SDK 3.10.7+
- Android Studio o VS Code
- Firebase CLI (para configurar Firebase)

### Instrucciones
```bash
# Clonar el repositorio
git clone https://github.com/Angel-Gil/UniCal.git
cd UniCal

# Instalar dependencias
flutter pub get

# Ejecutar en modo debug
flutter run
```

## 📂 Estructura del Proyecto
```
lib/
├── config/         # Tema y configuración
├── models/         # Modelos de datos
├── screens/        # Pantallas de la app
│   ├── auth/       # Login y registro
│   ├── calendar/   # Calendario de eventos
│   ├── home/       # Dashboard principal
│   ├── schedule/   # Horario semanal
│   ├── semesters/  # Semestres y materias
│   └── settings/   # Configuración
├── services/       # Servicios (Auth, DB, Sync, etc.)
└── main.dart       # Punto de entrada
pagina_web/         # Landing page (Vercel)
```

## ☕ Apóyame

Si te gusta esta app, ¡invítame un café!

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/angelgil05)

## 📄 Licencia

Este proyecto es de código abierto. Siéntete libre de usarlo y contribuir.

---

Hecho con ❤️ por [Angel Gil](https://github.com/Angel-Gil)