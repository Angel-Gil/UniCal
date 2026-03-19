/// Modelo de usuario para la aplicación (sin código generado)
class UserModel {
  final String uid;
  final String name;
  final String email;
  final double gradeScaleMin;
  final double gradeScaleMax;
  final DateTime createdAt;
  final DateTime? lastSyncAt;
  final bool isSynced;
  final DateTime updatedAt;
  final List<int> notificationOffsets; // Minutos antes del evento
  final bool notificationsEnabled;
  final String themeMode; // 'light', 'dark', 'system'
  final String timeFormat; // '12h', '24h'
  final bool showWeekends;
  final int startOfWeek; // 1 = Lunes, 7 = Domingo

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.gradeScaleMin = 0.0,
    this.gradeScaleMax = 5.0,
    DateTime? createdAt,
    this.lastSyncAt,
    this.isSynced = false,
    DateTime? updatedAt,
    List<int>? notificationOffsets,
    this.notificationsEnabled = true,
    this.themeMode = 'system',
    this.timeFormat = '12h',
    this.showWeekends = true,
    this.startOfWeek = 1,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       notificationOffsets = notificationOffsets ?? [15]; // Default: 15 min

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'email': email,
    'gradeScaleMin': gradeScaleMin,
    'gradeScaleMax': gradeScaleMax,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'notificationOffsets': notificationOffsets,
    'notificationsEnabled': notificationsEnabled,
    'themeMode': themeMode,
    'timeFormat': timeFormat,
    'showWeekends': showWeekends,
    'startOfWeek': startOfWeek,
  };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    uid: json['uid'],
    name: json['name'],
    email: json['email'],
    gradeScaleMin: (json['gradeScaleMin'] as num?)?.toDouble() ?? 0.0,
    gradeScaleMax: (json['gradeScaleMax'] as num?)?.toDouble() ?? 5.0,
    isSynced: true,
    notificationOffsets: (json['notificationOffsets'] as List?)
        ?.map((e) => e as int)
        .toList(),
    notificationsEnabled: json['notificationsEnabled'] ?? true,
    themeMode: json['themeMode'] ?? 'system',
    timeFormat: json['timeFormat'] ?? '12h',
    showWeekends: json['showWeekends'] ?? true,
    startOfWeek: json['startOfWeek'] ?? 1,
  );

  UserModel copyWith({
    String? name,
    double? gradeScaleMin,
    double? gradeScaleMax,
    List<int>? notificationOffsets,
    bool? notificationsEnabled,
    String? themeMode,
    String? timeFormat,
    bool? showWeekends,
    int? startOfWeek,
  }) => UserModel(
    uid: uid,
    name: name ?? this.name,
    email: email,
    gradeScaleMin: gradeScaleMin ?? this.gradeScaleMin,
    gradeScaleMax: gradeScaleMax ?? this.gradeScaleMax,
    createdAt: createdAt,
    lastSyncAt: lastSyncAt,
    isSynced: false,
    updatedAt: DateTime.now(),
    notificationOffsets: notificationOffsets ?? this.notificationOffsets,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    themeMode: themeMode ?? this.themeMode,
    timeFormat: timeFormat ?? this.timeFormat,
    showWeekends: showWeekends ?? this.showWeekends,
    startOfWeek: startOfWeek ?? this.startOfWeek,
  );
}
