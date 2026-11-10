import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_activity.dart';
import 'package:exampilot/models/study_streak.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/screens/profile_screen.dart';
import 'package:exampilot/services/web_storage.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('G5: Kiểm thử Model UserProfile & AvatarPreset', () {
    test('Khởi tạo UserProfile mặc định trả về trạng thái chưa cấu hình', () {
      const profile = UserProfile();
      expect(profile.isConfigured, isFalse);
      expect(profile.name, isEmpty);
      expect(profile.university, isEmpty);
      expect(profile.major, isEmpty);
      expect(profile.weeklyTargetHours, 10.0);
      expect(profile.weeklyTargetTasks, 5);
      expect(profile.themeMode, 'system');
      expect(profile.reminderEnabled, isFalse);
      expect(profile.flutterThemeMode, ThemeMode.system);
    });

    test('Chuyển đổi toMap và fromMap bảo toàn đầy đủ các trường dữ liệu', () {
      const original = UserProfile(
        id: 'test_user_1',
        name: 'Trần Minh Anh',
        university: 'Đại học Bách Khoa Hà Nội',
        major: 'Kỹ thuật Máy tính',
        academicYear: 'K66',
        avatarId: 'laptop',
        weeklyTargetHours: 14.5,
        weeklyTargetTasks: 8,
        themeMode: 'dark',
        reminderEnabled: true,
      );

      final map = original.toMap();
      final restored = UserProfile.fromMap(map);

      expect(restored.id, 'test_user_1');
      expect(restored.name, 'Trần Minh Anh');
      expect(restored.university, 'Đại học Bách Khoa Hà Nội');
      expect(restored.major, 'Kỹ thuật Máy tính');
      expect(restored.academicYear, 'K66');
      expect(restored.avatarId, 'laptop');
      expect(restored.weeklyTargetHours, 14.5);
      expect(restored.weeklyTargetTasks, 8);
      expect(restored.themeMode, 'dark');
      expect(restored.reminderEnabled, isTrue);
      expect(restored.flutterThemeMode, ThemeMode.dark);
      expect(restored.isConfigured, isTrue);
    });

    test('AvatarPreset hỗ trợ tra cứu đúng preset theo id', () {
      final preset = AvatarPreset.getById('laptop');
      expect(preset.label, 'Công nghệ');
      expect(preset.icon, Icons.laptop_chromebook_rounded);

      // Tra cứu id không tồn tại trả về preset đầu tiên (fallback an toàn)
      final fallback = AvatarPreset.getById('unknown_id');
      expect(fallback.id, 'school');
    });
  });

  group('G5: Kiểm thử ProfileRepository (SQLite & Web)', () {
    late Database db;
    late ProfileRepository repository;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableProfile} (
          ${DatabaseHelper.columnProfileId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnProfileName} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileUniversity} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileMajor} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileAcademicYear} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileAvatarId} TEXT NOT NULL DEFAULT 'school',
          ${DatabaseHelper.columnProfileTargetHours} REAL NOT NULL DEFAULT 10.0,
          ${DatabaseHelper.columnProfileTargetTasks} INTEGER NOT NULL DEFAULT 5,
          ${DatabaseHelper.columnProfileThemeMode} TEXT NOT NULL DEFAULT 'system',
          ${DatabaseHelper.columnProfileReminderEnabled} INTEGER NOT NULL DEFAULT 0
        )
      ''');

      DatabaseHelper.instance.setDatabaseForTesting(db);
      repository = ProfileRepository(dbHelper: DatabaseHelper.instance);
    });

    tearDown(() async {
      await db.close();
    });

    test('1. Thêm và chỉnh sửa hồ sơ cá nhân bền vững trong SQLite', () async {
      // Ban đầu chưa có dữ liệu
      var profile = await repository.getProfile();
      expect(profile.isConfigured, isFalse);

      // Thiết lập thông tin hồ sơ
      final newProfile = const UserProfile(
        name: 'Lê Hoàng Nam',
        university: 'Đại học Quốc gia',
        major: 'Khoa học Dữ liệu',
        academicYear: 'Năm 2',
        avatarId: 'science',
      );
      await repository.saveProfile(newProfile);

      profile = await repository.getProfile();
      expect(profile.isConfigured, isTrue);
      expect(profile.name, 'Lê Hoàng Nam');
      expect(profile.university, 'Đại học Quốc gia');
      expect(profile.major, 'Khoa học Dữ liệu');
      expect(profile.academicYear, 'Năm 2');
      expect(profile.avatarId, 'science');

      // Chỉnh sửa hồ sơ
      final editedProfile = profile.copyWith(
        name: 'Lê Hoàng Nam (Đã cập nhật)',
        academicYear: 'Năm 3',
      );
      await repository.saveProfile(editedProfile);

      final updated = await repository.getProfile();
      expect(updated.name, 'Lê Hoàng Nam (Đã cập nhật)');
      expect(updated.academicYear, 'Năm 3');
      expect(
        updated.university,
        'Đại học Quốc gia',
      ); // Các trường khác giữ nguyên
    });

    test(
      '2. Chế độ Web Preview bảo toàn hồ sơ qua reload (WebStreakStorage)',
      () async {
        WebStreakStorage.clearProfile();
        final webRepo = ProfileRepository(useWebPreview: true);

        // Ban đầu chưa có hồ sơ
        var p = await webRepo.getProfile();
        expect(p.isConfigured, isFalse);

        // Lưu hồ sơ
        const profile = UserProfile(
          name: 'Nguyễn Thị Mai',
          university: 'Đại học Kinh tế',
          major: 'Hệ thống Thông tin Quản lý',
          avatarId: 'book',
          weeklyTargetHours: 12.0,
          weeklyTargetTasks: 6,
        );
        await webRepo.saveProfile(profile);

        // Mô phỏng reload bằng cách khởi tạo instance repository mới
        final reloadedRepo = ProfileRepository(useWebPreview: true);
        final loaded = await reloadedRepo.getProfile();

        expect(loaded.isConfigured, isTrue);
        expect(loaded.name, 'Nguyễn Thị Mai');
        expect(loaded.university, 'Đại học Kinh tế');
        expect(loaded.major, 'Hệ thống Thông tin Quản lý');
        expect(loaded.weeklyTargetHours, 12.0);
        expect(loaded.weeklyTargetTasks, 6);

        WebStreakStorage.clearProfile();
      },
    );

    test('3. Cập nhật mục tiêu học tập, chế độ theme và nhắc nhở', () async {
      // Cập nhật mục tiêu
      await repository.updateWeeklyGoals(hours: 15.0, tasks: 7);
      var p = await repository.getProfile();
      expect(p.weeklyTargetHours, 15.0);
      expect(p.weeklyTargetTasks, 7);

      // Cập nhật theme mode
      await repository.updateThemeMode('dark');
      p = await repository.getProfile();
      expect(p.themeMode, 'dark');
      expect(p.flutterThemeMode, ThemeMode.dark);

      // Cập nhật thông báo nhắc học
      await repository.updateReminderEnabled(true);
      p = await repository.getProfile();
      expect(p.reminderEnabled, isTrue);
    });

    test('4. Đặt lại hồ sơ cá nhân đưa về trạng thái chưa thiết lập', () async {
      await repository.saveProfile(
        const UserProfile(
          name: 'Đặng Tuấn Kiệt',
          university: 'ĐH Sư Phạm Kỹ Thuật',
          major: 'Điện tử Viễn thông',
        ),
      );

      var p = await repository.getProfile();
      expect(p.isConfigured, isTrue);

      await repository.resetProfile();

      p = await repository.getProfile();
      expect(p.isConfigured, isFalse);
      expect(p.name, isEmpty);
    });
  });

  group('G5: Kiểm thử Thuật toán Tính Tiến độ Mục tiêu Tuần', () {
    final monday = DateTime(2026, 11, 9, 10, 0); // Thứ Hai
    final wednesday = DateTime(2026, 11, 11, 14, 0); // Thứ Tư

    test(
      '5. Tiến độ được tính chuẩn xác từ hoạt động thực tế trong tuần hiện tại',
      () {
        const profile = UserProfile(
          weeklyTargetHours: 10.0,
          weeklyTargetTasks: 4,
        );

        final activities = [
          StudyActivity(
            id: 'act_1',
            dateKey: StudyStreak.formatDateKey(monday),
            taskId: 'task_1',
            completedAt: monday,
            actualMinutes: 60, // 1 giờ
          ),
          StudyActivity(
            id: 'act_2',
            dateKey: StudyStreak.formatDateKey(wednesday),
            taskId: 'task_2',
            completedAt: wednesday,
            actualMinutes: 120, // 2 giờ
          ),
          // Hoạt động của 15 ngày trước (ngoài tuần này)
          StudyActivity(
            id: 'act_old',
            dateKey: '2026-10-25',
            taskId: 'task_old',
            completedAt: monday.subtract(const Duration(days: 15)),
            actualMinutes: 180,
          ),
        ];

        final progress = ProfileScreen.calculateWeeklyGoalProgress(
          profile: profile,
          activities: activities,
          now: wednesday,
        );

        // Tổng thời lượng tuần: 60 + 120 = 180 phút = 3.0 giờ
        expect(progress.actualHours, 3.0);
        expect(progress.targetHours, 10.0);
        expect(progress.remainingHours, 7.0);
        expect(progress.hoursRate, 0.3);
        expect(progress.isHoursAchieved, isFalse);

        // Tổng công việc hoàn thành trong tuần: task_1 và task_2 = 2 việc
        expect(progress.actualTasks, 2);
        expect(progress.targetTasks, 4);
        expect(progress.remainingTasks, 2);
        expect(progress.tasksRate, 0.5);
        expect(progress.isTasksAchieved, isFalse);
        expect(progress.isAllAchieved, isFalse);
      },
    );

    test('6. Khi chưa có hoạt động nào trong tuần: hiển thị 0 hợp lý', () {
      const profile = UserProfile(weeklyTargetHours: 8.0, weeklyTargetTasks: 5);

      final progress = ProfileScreen.calculateWeeklyGoalProgress(
        profile: profile,
        activities: [],
        now: monday,
      );

      expect(progress.actualHours, 0.0);
      expect(progress.actualTasks, 0);
      expect(progress.remainingHours, 8.0);
      expect(progress.remainingTasks, 5);
      expect(progress.hoursRate, 0.0);
      expect(progress.tasksRate, 0.0);
      expect(progress.isAllAchieved, isFalse);
    });

    test(
      '7. Thay đổi mục tiêu không làm thay đổi hoặc mất dữ liệu học tập thực tế',
      () {
        var profile = const UserProfile(
          weeklyTargetHours: 5.0,
          weeklyTargetTasks: 2,
        );

        final activities = [
          StudyActivity(
            id: 'act_1',
            dateKey: StudyStreak.formatDateKey(monday),
            taskId: 'task_1',
            completedAt: monday,
            actualMinutes: 300, // 5 giờ
          ),
          StudyActivity(
            id: 'act_2',
            dateKey: StudyStreak.formatDateKey(monday),
            taskId: 'task_2',
            completedAt: monday,
            actualMinutes: 60, // 1 giờ
          ),
        ];

        // Với mục tiêu cũ: 6 giờ / 5 giờ (đạt), 2 việc / 2 việc (đạt)
        var progress = ProfileScreen.calculateWeeklyGoalProgress(
          profile: profile,
          activities: activities,
          now: monday,
        );
        expect(progress.actualHours, 6.0);
        expect(progress.isHoursAchieved, isTrue);
        expect(progress.isTasksAchieved, isTrue);
        expect(progress.isAllAchieved, isTrue);

        // Nâng mục tiêu lên 10 giờ và 4 việc: lịch sử 6 giờ và 2 việc vẫn giữ nguyên
        profile = profile.copyWith(
          weeklyTargetHours: 10.0,
          weeklyTargetTasks: 4,
        );
        progress = ProfileScreen.calculateWeeklyGoalProgress(
          profile: profile,
          activities: activities,
          now: monday,
        );
        expect(progress.actualHours, 6.0);
        expect(progress.actualTasks, 2);
        expect(progress.targetHours, 10.0);
        expect(progress.targetTasks, 4);
        expect(progress.remainingHours, 4.0);
        expect(progress.remainingTasks, 2);
        expect(progress.isAllAchieved, isFalse);
      },
    );
  });

  group('G5: Kiểm thử Giao diện Màn hình Cá nhân (ProfileScreen & Dialogs)', () {
    testWidgets(
      'Hiển thị trạng thái chưa cấu hình và kích hoạt dialog thiết lập hồ sơ',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        UserProfile? savedProfile;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfileScreen(
                profile: const UserProfile(),
                activities: const [],
                onUpdateProfile: (p) => savedProfile = p,
                onUpdateGoals: (hours, tasks) {},
                onUpdateThemeMode: (_) {},
                onUpdateReminderEnabled: (_) {},
                onResetStudyData: () async {},
                onResetProfile: () async {},
                onResetSampleData: () async {},
                onResetAllData: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Kiểm tra thông điệp chưa cấu hình
        expect(find.text('Chưa thiết lập hồ sơ cá nhân'), findsOneWidget);
        expect(find.text('Thiết lập hồ sơ ngay'), findsOneWidget);
        expect(find.text('Mục tiêu học tập tuần này'), findsOneWidget);
        expect(find.text('Cài đặt ứng dụng'), findsOneWidget);
        expect(find.text('Nhắc nhở học tập hàng ngày'), findsOneWidget);

        // Bấm nút thiết lập hồ sơ ngay
        await tester.tap(
          find.byKey(const ValueKey('profile_setup_open_button')),
        );
        await tester.pumpAndSettle();

        // Hộp thoại ProfileEditDialog xuất hiện
        expect(find.text('Thiết lập hồ sơ cá nhân'), findsOneWidget);
        expect(find.text('Chọn biểu tượng đại diện'), findsOneWidget);

        // Nhập thông tin
        await tester.enterText(
          find.byKey(const ValueKey('profile_name_field')),
          'Phạm Quốc Huy',
        );
        await tester.enterText(
          find.byKey(const ValueKey('profile_university_field')),
          'Đại học Công nghệ',
        );
        await tester.enterText(
          find.byKey(const ValueKey('profile_major_field')),
          'Kỹ thuật Phần mềm',
        );

        // Bấm Lưu hồ sơ
        await tester.tap(find.byKey(const ValueKey('profile_save_button')));
        await tester.pumpAndSettle();

        expect(savedProfile, isNotNull);
        expect(savedProfile!.name, 'Phạm Quốc Huy');
        expect(savedProfile!.university, 'Đại học Công nghệ');
        expect(savedProfile!.major, 'Kỹ thuật Phần mềm');
      },
    );

    testWidgets(
      'Hiển thị thông tin hồ sơ đã cấu hình và mở dialog chỉnh sửa mục tiêu',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        double? updatedHours;
        int? updatedTasks;

        const configuredProfile = UserProfile(
          name: 'Vũ Đức Minh',
          university: 'Học viện Bưu chính Viễn thông',
          major: 'An toàn Thông tin',
          academicYear: 'K2021',
          weeklyTargetHours: 12.0,
          weeklyTargetTasks: 6,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfileScreen(
                profile: configuredProfile,
                activities: const [],
                onUpdateProfile: (_) {},
                onUpdateGoals: (h, t) {
                  updatedHours = h;
                  updatedTasks = t;
                },
                onUpdateThemeMode: (_) {},
                onUpdateReminderEnabled: (_) {},
                onResetStudyData: () async {},
                onResetProfile: () async {},
                onResetSampleData: () async {},
                onResetAllData: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Kiểm tra thông tin hồ sơ hiển thị
        expect(find.text('Vũ Đức Minh'), findsOneWidget);
        expect(find.text('Học viện Bưu chính Viễn thông'), findsOneWidget);
        expect(find.text('An toàn Thông tin'), findsOneWidget);
        expect(find.text('K2021'), findsOneWidget);
        expect(find.text('Chỉnh sửa hồ sơ'), findsOneWidget);

        // Bấm nút chỉnh sửa mục tiêu tuần
        await tester.tap(find.byKey(const ValueKey('goals_edit_open_button')));
        await tester.pumpAndSettle();

        expect(find.text('Thiết lập mục tiêu tuần'), findsOneWidget);
        expect(find.text('12 giờ'), findsOneWidget);
        expect(find.text('6 việc'), findsOneWidget);

        // Bấm Lưu mục tiêu
        await tester.tap(find.byKey(const ValueKey('goals_save_button')));
        await tester.pumpAndSettle();

        expect(updatedHours, 12.0);
        expect(updatedTasks, 6);
      },
    );

    testWidgets(
      'Hộp thoại xác nhận đặt lại dữ liệu: bấm Hủy không xóa, bấm Xác nhận kích hoạt xóa',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool resetCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfileScreen(
                profile: const UserProfile(name: 'Test'),
                activities: const [],
                onUpdateProfile: (_) {},
                onUpdateGoals: (hours, tasks) {},
                onUpdateThemeMode: (_) {},
                onUpdateReminderEnabled: (_) {},
                onResetStudyData: () async {
                  resetCalled = true;
                },
                onResetProfile: () async {},
                onResetSampleData: () async {},
                onResetAllData: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Bấm vào mục "Đặt lại dữ liệu học tập"
        await tester.tap(find.text('Đặt lại dữ liệu học tập'));
        await tester.pumpAndSettle();

        // Xuất hiện hộp thoại xác nhận rõ ràng
        expect(find.text('Xóa toàn bộ công việc học tập?'), findsOneWidget);
        expect(find.text('Hủy'), findsOneWidget);
        expect(find.text('Xác nhận xóa'), findsOneWidget);

        // 1. Thử bấm Hủy -> Không kích hoạt xóa
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        expect(resetCalled, isFalse);

        // 2. Bấm lại và chọn Xác nhận xóa -> Kích hoạt xóa
        await tester.tap(find.text('Đặt lại dữ liệu học tập'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xác nhận xóa'));
        await tester.pumpAndSettle();
        expect(resetCalled, isTrue);
      },
    );
  });
}
