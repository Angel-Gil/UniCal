import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import 'local_database_service.dart';

/// Servicio de autenticación con Firebase Auth + respaldo local
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();

  AuthService._();

  final _db = LocalDatabaseService.instance;
  final _firebaseAuth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  User? get firebaseUser => _firebaseAuth.currentUser;

  bool get isGuest => _currentUser?.uid == 'guest_user';

  final _authNotifier = ValueNotifier<UserModel?>(null);
  ValueNotifier<UserModel?> get authState => _authNotifier;

  /// Inicializa el servicio y restaura la sesión si existe
  Future<void> initialize() async {
    await _db.initialize();

    // Verificar si hay sesión de Firebase activa
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      // Intentar cargar datos del usuario desde Firestore
      try {
        final doc = await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .get();
        if (doc.exists) {
          _currentUser = UserModel.fromJson(doc.data()!);
          await _db.saveUser(_currentUser!);
        }
      } catch (e) {
        debugPrint('AuthService: Error cargando usuario de Firestore: $e');
        // Intentar cargar desde local
        _currentUser = _db.getUser(firebaseUser.uid);
      }
    } else {
      // Sin sesión Firebase, intentar cargar local (posiblemente invitado)
      _currentUser = _db.getCurrentUser();
    }

    _authNotifier.value = _currentUser;
    debugPrint(
      'AuthService: Inicializado. Usuario: ${_currentUser?.email ?? "ninguno"}',
    );
  }

  /// Inicia sesión como invitado
  Future<void> loginAsGuest() async {
    debugPrint('AuthService: Iniciando como invitado');

    final guestUser = UserModel(
      uid: 'guest_user',
      name: 'Invitado',
      email: '',
      gradeScaleMin: 0.0,
      gradeScaleMax: 5.0,
    );

    // Guardar solo localmente
    await _db.saveUser(guestUser);

    _currentUser = guestUser;
    _authNotifier.value = guestUser;
  }

  /// Registra un nuevo usuario con Firebase Auth

  /// Registra un nuevo usuario con Firebase Auth
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    double gradeScaleMin = 0.0,
    double gradeScaleMax = 5.0,
  }) async {
    debugPrint('AuthService: Registrando usuario $email');

    try {
      // Crear cuenta en Firebase Auth
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      // Actualizar nombre en Firebase Auth
      await credential.user!.updateDisplayName(name);

      // Crear modelo de usuario
      final user = UserModel(
        uid: uid,
        name: name,
        email: email,
        gradeScaleMin: gradeScaleMin,
        gradeScaleMax: gradeScaleMax,
      );

      // Guardar en Firestore
      await _firestore.collection('users').doc(uid).set(user.toJson());

      // Guardar localmente
      await _db.saveUser(user);

      // Migrar datos del guest si existen
      final migrated = await _db.migrateUserData('guest_user', uid);
      if (migrated > 0) {
        debugPrint('AuthService: Migrados $migrated items del guest a $uid');
      }
      // Delete guest user to prevent getCurrentUser returning it
      await _db.deleteUser('guest_user');

      _currentUser = user;
      _authNotifier.value = user;

      debugPrint('AuthService: Usuario registrado exitosamente: $uid');
      return user;
    } on FirebaseException catch (e) {
      debugPrint('AuthService: Error Firebase Auth: ${e.code}');
      throw _mapFirebaseError(e);
    }
  }

  /// Inicia sesión con Firebase Auth
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    debugPrint('AuthService: Iniciando sesión $email');

    try {
      // Autenticar con Firebase
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      // Cargar datos de Firestore
      final doc = await _firestore.collection('users').doc(uid).get();

      UserModel user;
      if (doc.exists) {
        user = UserModel.fromJson(doc.data()!);
      } else {
        // Si no existe en Firestore, crear registro
        user = UserModel(
          uid: uid,
          name: credential.user!.displayName ?? 'Usuario',
          email: email,
          gradeScaleMin: 0.0,
          gradeScaleMax: 5.0,
        );
        await _firestore.collection('users').doc(uid).set(user.toJson());
      }

      // Guardar localmente
      await _db.saveUser(user);

      // Migrar datos del guest si existen
      final migrated = await _db.migrateUserData('guest_user', uid);
      if (migrated > 0) {
        debugPrint('AuthService: Migrados $migrated items del guest a $uid');
      }
      // Delete guest user
      await _db.deleteUser('guest_user');

      _currentUser = user;
      _authNotifier.value = user;

      debugPrint('AuthService: Sesión iniciada exitosamente: $uid');
      return user;
    } on FirebaseException catch (e) {
      debugPrint('AuthService: Error Firebase Auth: ${e.code}');
      throw _mapFirebaseError(e);
    }
  }

  /// Cierra sesión
  Future<void> logout() async {
    debugPrint('AuthService: Cerrando sesión');
    await _firebaseAuth.signOut();
    if (_currentUser != null) {
      await _db.deleteUser(_currentUser!.uid);
    }
    _currentUser = null;
    _authNotifier.value = null;
  }

  /// Actualiza el perfil del usuario
  Future<void> updateProfile({
    String? name,
    double? gradeScaleMin,
    double? gradeScaleMax,
    List<int>? notificationOffsets,
    bool? notificationsEnabled,
  }) async {
    if (_currentUser == null) return;

    final updated = _currentUser!.copyWith(
      name: name,
      gradeScaleMin: gradeScaleMin,
      gradeScaleMax: gradeScaleMax,
      notificationOffsets: notificationOffsets,
      notificationsEnabled: notificationsEnabled,
    );

    // Actualizar en Firestore
    try {
      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .update(updated.toJson());
    } catch (e) {
      debugPrint('AuthService: Error actualizando Firestore: $e');
    }

    // Actualizar localmente
    await _db.saveUser(updated);
    _currentUser = updated;
    _authNotifier.value = updated;
  }

  /// Eliminar cuenta (requiere re-autenticación)
  Future<void> deleteAccount(String password) async {
    debugPrint('AuthService: Iniciando eliminación de cuenta');
    final user = _firebaseAuth.currentUser;
    if (user == null || user.email == null)
      throw Exception('No hay usuario autenticado');

    try {
      // 1. Re-autenticar
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // 2. Borrar datos de Firestore
      await _deleteSubcollection(user.uid, 'semesters');
      await _deleteSubcollection(user.uid, 'subjects');
      await _deleteSubcollection(user.uid, 'grade_periods');
      await _deleteSubcollection(user.uid, 'schedules');
      await _deleteSubcollection(user.uid, 'events');

      await _firestore.collection('users').doc(user.uid).delete();

      // 3. Borrar usuario de Auth
      await user.delete();

      // 4. Borrar datos locales
      await _db.clearAll();

      _currentUser = null;
      _authNotifier.value = null;
      debugPrint('AuthService: Cuenta eliminada correctamente');
    } on FirebaseException catch (e) {
      debugPrint('AuthService: Error eliminando cuenta: ${e.code}');
      throw _mapFirebaseError(e);
    }
  }

  Future<void> _deleteSubcollection(String uid, String collectionName) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection(collectionName);
    final snapshot = await ref.get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// Recuperar contraseña
  /// Usa el handler por defecto de Firebase (no requiere configuración extra).
  Future<void> resetPassword(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      debugPrint('AuthService: Email de recuperación enviado a $email');
    } catch (e) {
      debugPrint('AuthService: Error enviando email de recuperación: $e');
      rethrow;
    }
  }

  /// Mapea errores de Firebase a mensajes legibles
  String _mapFirebaseError(FirebaseException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Este correo ya está registrado';
      case 'invalid-email':
        return 'Correo electrónico inválido';
      case 'weak-password':
        return 'La contraseña es muy débil';
      case 'user-not-found':
        return 'No existe una cuenta con este correo';
      case 'wrong-password':
        return 'Contraseña incorrecta';
      case 'invalid-credential':
        return 'Credenciales inválidas';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada';
      default:
        return 'Error de autenticación: ${e.message}';
    }
  }
}
