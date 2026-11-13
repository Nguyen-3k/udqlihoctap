import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/class_schedule.dart';
import '../models/study_activity.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/subject_repository.dart';
import '../repositories/task_repository.dart';
import 'backup_storage.dart';

/// Thông tin xem trước bản sao lưu trước khi người dùng xác nhận khôi phục.
class BackupPreview {
  final int formatVersion;
  final String appVersion;
  final DateTime createdAt;
  final int totalSubjects;
  final int totalTasks;
  final int totalActivities;
  final int totalSchedules;
  final String userName;
  final double weeklyTargetHours;
  final int weeklyTargetTasks;
  final String themeMode;

  const BackupPreview({
    required this.formatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.totalSubjects,
    required this.totalTasks,
    required this.totalActivities,
    this.totalSchedules = 0,
    required this.userName,
    required this.weeklyTargetHours,
    required this.weeklyTargetTasks,
    required this.themeMode,
  });
}

/// Kết quả kiểm tra tính hợp lệ của tệp sao lưu.
class BackupValidationResult {
  final bool isValid;
  final String? errorMessage;
  final BackupPreview? preview;
  final Map<String, dynamic>? backupMap;

  const BackupValidationResult.success({
    required this.preview,
    required this.backupMap,
  }) : isValid = true,
       errorMessage = null;

  const BackupValidationResult.failure(this.errorMessage)
    : isValid = false,
      preview = null,
      backupMap = null;
}

/// Dịch vụ quản lý Sao lưu và Khôi phục toàn diện cho ExamPilot.
/// Hỗ trợ cả cơ sở dữ liệu SQLite (Android) và bộ nhớ Web Preview.
class BackupService {
  static const int currentFormatVersion = 1;
  static const String appIdentifier = 'ExamPilot';
  static const String currentAppVersion = '1.0.0';

  static DateTime? lastBackupTime;

  /// Hook hỗ trợ kiểm thử tự động chọn tệp
  static Future<String?> Function()? testFilePicker;

  /// Hook hỗ trợ kiểm thử tự động chia sẻ tệp
  static Future<void> Function(String filePath, String fileName)?
  testFileSharer;

  final TaskRepository taskRepository;
  final SubjectRepository subjectRepository;
  final ProfileRepository profileRepository;
  final ScheduleRepository? scheduleRepository;
  final DatabaseHelper? dbHelper;

  BackupService({
    required this.taskRepository,
    required this.subjectRepository,
    required this.profileRepository,
    this.scheduleRepository,
    this.dbHelper,
  });

  /// Tính toán Checksum Adler-32 xác thực tính toàn vẹn của khối dữ liệu.
  static String computeChecksum(String jsonString) {
    final bytes = utf8.encode(jsonString);
    int a = 1;
    int b = 0;
    for (final byte in bytes) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    final checksumInt = (b << 16) | a;
    return checksumInt.toRadixString(16).padLeft(8, '0');
  }

  /// Thu thập toàn bộ dữ liệu hiện có và tạo đối tượng Map sao lưu hoàn chỉnh.
  Future<Map<String, dynamic>> createBackupData() async {
    final profile = await profileRepository.getProfile();
    final subjects = await subjectRepository.getAllSubjects();
    final tasks = await taskRepository.getAllTasks();
    final activities = await taskRepository.getAllActivities();
    final schedules = scheduleRepository != null
        ? await scheduleRepository!.getAllSchedules()
        : <ClassSchedule>[];

    final dataBlock = <String, dynamic>{
      'profile': profile.toMap(),
      'subjects': subjects.map((s) => s.toMap()).toList(),
      'tasks': tasks.map((t) => t.toMap()).toList(),
      'activities': activities.map((a) => a.toMap()).toList(),
      'schedules': schedules.map((s) => s.toMap()).toList(),
    };

    final canonicalDataJson = jsonEncode(dataBlock);
    final checksum = computeChecksum(canonicalDataJson);
    final now = DateTime.now();

    return {
      'app': appIdentifier,
      'formatVersion': currentFormatVersion,
      'appVersion': currentAppVersion,
      'createdAt': now.toIso8601String(),
      'metadata': {
        'totalSubjects': subjects.length,
        'totalTasks': tasks.length,
        'totalActivities': activities.length,
        'totalSchedules': schedules.length,
      },
      'data': dataBlock,
      'checksum': checksum,
    };
  }

  /// Chuyển đổi đối tượng sao lưu sang chuỗi JSON có thụt lề định dạng đẹp.
  String exportBackupJson(Map<String, dynamic> backupMap) {
    return const JsonEncoder.withIndent('  ').convert(backupMap);
  }

  /// Xuất và lưu tệp sao lưu vào thiết bị (Downloads / Local Storage) kèm sao chép vào Clipboard.
  Future<String> saveBackupToFile(
    String jsonString, {
    String? customFileName,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName =
        customFileName ?? 'exampilot_backup_${dateStr}_$timeStr.json';

    // 1. Sao chép vào bộ nhớ tạm (Clipboard) để chia sẻ nhanh
    try {
      await Clipboard.setData(ClipboardData(text: jsonString));
    } catch (_) {}

    // 2. Lưu vào tệp trên thiết bị / kích hoạt tải xuống trên Web
    final savedPath = await saveBackupFile(fileName, jsonString);
    lastBackupTime = now;
    return savedPath;
  }

  /// Mở trình chọn tệp của hệ thống (.json) và đọc nội dung văn bản.
  Future<String?> pickAndReadBackupFile() async {
    if (testFilePicker != null) {
      return await testFilePicker!();
    }
    return await pickBackupFileContent();
  }

  /// Chia sẻ tệp sao lưu ra ngoài ứng dụng thông qua hệ thống (Android Sharesheet).
  Future<void> shareBackup(String filePath, {String? fileName}) async {
    final name = fileName ?? (filePath.split(RegExp(r'[/\\]')).last);
    if (testFileSharer != null) {
      await testFileSharer!(filePath, name);
      return;
    }
    await shareBackupFileExternal(filePath, name);
  }

  /// Kiểm tra định dạng, phiên bản và tính toàn vẹn của chuỗi JSON sao lưu.
  BackupValidationResult validateBackupJson(String jsonString) {
    if (jsonString.trim().isEmpty) {
      return const BackupValidationResult.failure(
        'Nội dung tệp sao lưu rỗng. Vui lòng chọn tệp hợp lệ.',
      );
    }

    dynamic parsed;
    try {
      parsed = jsonDecode(jsonString);
    } catch (e) {
      return const BackupValidationResult.failure(
        'Tệp không đúng định dạng JSON hợp lệ.',
      );
    }

    if (parsed is! Map<String, dynamic> && parsed is! Map) {
      return const BackupValidationResult.failure(
        'Cấu trúc tệp sao lưu không hợp lệ.',
      );
    }

    final map = Map<String, dynamic>.from(parsed as Map);

    // 1. Kiểm tra ứng dụng nguồn
    final app = map['app']?.toString();
    if (app != appIdentifier) {
      return const BackupValidationResult.failure(
        'Tệp này không phải là bản sao lưu của ExamPilot.',
      );
    }

    // 2. Kiểm tra version định dạng
    final version = (map['formatVersion'] as num?)?.toInt();
    if (version == null) {
      return const BackupValidationResult.failure(
        'Tệp sao lưu thiếu thông tin phiên bản định dạng.',
      );
    }
    if (version > currentFormatVersion) {
      return BackupValidationResult.failure(
        'Phiên bản tệp sao lưu (v$version) mới hơn phiên bản ứng dụng hỗ trợ (v$currentFormatVersion). Vui lòng cập nhật ứng dụng.',
      );
    }

    // 3. Kiểm tra khối data
    final data = map['data'];
    if (data is! Map) {
      return const BackupValidationResult.failure(
        'Tệp sao lưu thiếu khối dữ liệu "data".',
      );
    }
    final dataMap = Map<String, dynamic>.from(data);

    // 4. Kiểm tra các trường danh sách bắt buộc trong data
    if (dataMap['subjects'] is! List) {
      return const BackupValidationResult.failure(
        'Tệp sao lưu thiếu danh mục môn học (subjects).',
      );
    }
    if (dataMap['tasks'] is! List) {
      return const BackupValidationResult.failure(
        'Tệp sao lưu thiếu danh mục công việc học tập (tasks).',
      );
    }
    if (dataMap['activities'] is! List) {
      return const BackupValidationResult.failure(
        'Tệp sao lưu thiếu lịch sử hoạt động học tập (activities).',
      );
    }

    // 5. Kiểm tra checksum tính toàn vẹn
    final storedChecksum = map['checksum']?.toString();
    if (storedChecksum != null && storedChecksum.isNotEmpty) {
      final canonicalDataJson = jsonEncode(dataMap);
      final calculatedChecksum = computeChecksum(canonicalDataJson);
      if (storedChecksum.toLowerCase() != calculatedChecksum.toLowerCase()) {
        return const BackupValidationResult.failure(
          'Tệp sao lưu bị hỏng hoặc đã bị chỉnh sửa bất hợp lệ (Checksum không khớp).',
        );
      }
    }

    // 6. Kiểm tra cấu trúc từng môn học và công việc
    final subjectsRaw = dataMap['subjects'] as List;
    final subjectIds = <String>{};
    for (final s in subjectsRaw) {
      if (s is! Map) {
        return const BackupValidationResult.failure(
          'Dữ liệu môn học trong tệp bị lỗi định dạng.',
        );
      }
      final sId = s['id']?.toString() ?? '';
      final sName = s['name']?.toString() ?? '';
      if (sId.isEmpty || sName.isEmpty) {
        return const BackupValidationResult.failure(
          'Môn học trong tệp sao lưu thiếu id hoặc tên môn.',
        );
      }
      subjectIds.add(sId);
    }

    final tasksRaw = dataMap['tasks'] as List;
    for (final t in tasksRaw) {
      if (t is! Map) {
        return const BackupValidationResult.failure(
          'Dữ liệu công việc trong tệp bị lỗi định dạng.',
        );
      }
      final tId = t['id']?.toString() ?? '';
      final tTitle = t['title']?.toString() ?? '';
      if (tId.isEmpty || tTitle.isEmpty) {
        return const BackupValidationResult.failure(
          'Công việc trong tệp sao lưu thiếu id hoặc tiêu đề.',
        );
      }
    }

    final activitiesRaw = dataMap['activities'] as List;
    for (final a in activitiesRaw) {
      if (a is! Map) {
        return const BackupValidationResult.failure(
          'Dữ liệu hoạt động trong tệp bị lỗi định dạng.',
        );
      }
      final aId = a['id']?.toString() ?? '';
      if (aId.isEmpty) {
        return const BackupValidationResult.failure(
          'Bản ghi hoạt động học tập thiếu id bắt buộc.',
        );
      }
    }

    // Kiểm tra cấu trúc danh sách lịch học (nếu có trong bản sao lưu mới)
    final schedulesRaw = dataMap['schedules'] is List
        ? (dataMap['schedules'] as List)
        : const [];
    for (final s in schedulesRaw) {
      if (s is! Map) {
        return const BackupValidationResult.failure(
          'Dữ liệu lịch học trong tệp bị lỗi định dạng.',
        );
      }
    }

    // 7. Trích xuất thông tin xem trước (Preview)
    final profileMap = dataMap['profile'] is Map
        ? Map<String, dynamic>.from(dataMap['profile'] as Map)
        : <String, dynamic>{};
    final userName = profileMap['name']?.toString() ?? '';
    final targetHours =
        (profileMap['weekly_target_hours'] as num?)?.toDouble() ?? 10.0;
    final targetTasks =
        (profileMap['weekly_target_tasks'] as num?)?.toInt() ?? 5;
    final themeMode = profileMap['theme_mode']?.toString() ?? 'system';
    final createdAt =
        DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now();
    final appVersion = map['appVersion']?.toString() ?? '1.0.0';

    final preview = BackupPreview(
      formatVersion: version,
      appVersion: appVersion,
      createdAt: createdAt,
      totalSubjects: subjectsRaw.length,
      totalTasks: tasksRaw.length,
      totalActivities: activitiesRaw.length,
      totalSchedules: schedulesRaw.length,
      userName: userName,
      weeklyTargetHours: targetHours,
      weeklyTargetTasks: targetTasks,
      themeMode: themeMode,
    );

    return BackupValidationResult.success(preview: preview, backupMap: map);
  }

  /// Khôi phục toàn bộ dữ liệu từ bản sao lưu đã được xác thực an toàn.
  /// Sử dụng Transaction trong SQLite để bảo đảm Rollback nếu có lỗi xảy ra.
  Future<void> restoreBackup(Map<String, dynamic> backupMap) async {
    final validation = validateBackupJson(jsonEncode(backupMap));
    if (!validation.isValid || validation.backupMap == null) {
      throw Exception(
        validation.errorMessage ?? 'Bản sao lưu không hợp lệ để khôi phục.',
      );
    }

    final data = Map<String, dynamic>.from(
      validation.backupMap!['data'] as Map,
    );

    // 1. Phân giải các mô hình dữ liệu
    final subjects = (data['subjects'] as List)
        .map((m) => Subject.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();

    final tasks = (data['tasks'] as List)
        .map((m) => StudyTask.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();

    final activities = (data['activities'] as List)
        .map((m) => StudyActivity.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();

    final schedulesRaw = data['schedules'] is List
        ? (data['schedules'] as List)
        : const [];
    final schedules = schedulesRaw
        .whereType<Map>()
        .map((m) => ClassSchedule.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    final rawProfile = data['profile'] is Map
        ? UserProfile.fromMap(Map<String, dynamic>.from(data['profile'] as Map))
        : const UserProfile();
    final profile = rawProfile.copyWith(id: UserProfile.defaultId);

    // 2. Bảo đảm toàn vẹn liên kết: Nếu công việc có subjectId chưa có trong subjects, tự động bổ sung
    final existingSubjectIds = subjects.map((s) => s.id).toSet();
    for (final task in tasks) {
      if (!existingSubjectIds.contains(task.subjectId)) {
        subjects.add(
          Subject(
            id: task.subjectId,
            name: task.subject.isNotEmpty ? task.subject : 'Môn học chung',
            description: 'Tự động tạo khi khôi phục dữ liệu',
          ),
        );
        existingSubjectIds.add(task.subjectId);
      }
    }

    // 3. Thực hiện ghi dữ liệu an toàn
    if (!taskRepository.isWebPreview && dbHelper != null) {
      final db = await dbHelper!.database;

      // Sử dụng Transaction: Nếu bất kỳ bước nào thất bại, toàn bộ dữ liệu cũ được Rollback nguyên vẹn!
      await db.transaction((txn) async {
        // Đảm bảo bảng class_schedules và các cột v8 của study_tasks tồn tại nếu DB chưa có
        await DatabaseHelper.createClassSchedulesTable(txn);
        await DatabaseHelper.upgradeTasksColumnsToV8(txn);

        // Xóa dữ liệu cũ
        await txn.delete(DatabaseHelper.tableTasks);
        await txn.delete(DatabaseHelper.tableActivities);
        await txn.delete(DatabaseHelper.tableSubjects);
        await txn.delete(DatabaseHelper.tableProfile);
        await txn.delete(DatabaseHelper.tableClassSchedules);

        // Ghi dữ liệu môn học
        for (final s in subjects) {
          await txn.insert(
            DatabaseHelper.tableSubjects,
            s.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Ghi dữ liệu công việc
        for (final t in tasks) {
          await txn.insert(
            DatabaseHelper.tableTasks,
            t.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Ghi dữ liệu lịch sử hoạt động học tập
        for (final a in activities) {
          await txn.insert(
            DatabaseHelper.tableActivities,
            a.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Ghi dữ liệu lịch học cố định theo tuần
        for (final sc in schedules) {
          await txn.insert(
            DatabaseHelper.tableClassSchedules,
            sc.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Bảo đảm bảng user_profile có đủ cột v7 và ghi hồ sơ cá nhân
        await DatabaseHelper.upgradeProfileColumnsToV7(txn);
        await txn.insert(
          DatabaseHelper.tableProfile,
          profile.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } else {
      // Chế độ Web Preview: Khôi phục qua bộ nhớ và Web Storage
      await taskRepository.clearAllTasks();
      await subjectRepository.resetDefaultSubjects(subjects);
      if (scheduleRepository != null) {
        await scheduleRepository!.resetDefaultSchedules(schedules);
      }
      for (final t in tasks) {
        await taskRepository.insertTask(t);
      }
      for (final a in activities) {
        await taskRepository.recordTaskCompletion(
          a.taskId,
          completedAt: a.completedAt,
          actualMinutes: a.actualMinutes,
          subjectId: a.subjectId,
        );
      }
      await profileRepository.saveProfile(profile);
    }

    lastBackupTime =
        DateTime.tryParse(backupMap['createdAt']?.toString() ?? '') ??
        DateTime.now();
  }
}
