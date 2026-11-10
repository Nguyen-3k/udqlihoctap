import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/study_activity.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/goals_edit_dialog.dart';
import '../widgets/info_card.dart';
import '../widgets/profile_edit_dialog.dart';

/// Màn hình Hồ sơ cá nhân, Mục tiêu học tập và Cài đặt (Giai đoạn 5).
/// Hoạt động hoàn toàn cục bộ, không có backend, không đăng nhập.
class ProfileScreen extends StatelessWidget {
  final UserProfile profile;
  final List<StudyActivity> activities;
  final ValueChanged<UserProfile> onUpdateProfile;
  final void Function(double hours, int tasks) onUpdateGoals;
  final ValueChanged<String> onUpdateThemeMode;
  final ValueChanged<bool> onUpdateReminderEnabled;
  final Future<void> Function() onResetStudyData;
  final Future<void> Function() onResetProfile;
  final Future<void> Function() onResetSampleData;
  final Future<void> Function() onResetAllData;

  const ProfileScreen({
    super.key,
    required this.profile,
    required this.activities,
    required this.onUpdateProfile,
    required this.onUpdateGoals,
    required this.onUpdateThemeMode,
    required this.onUpdateReminderEnabled,
    required this.onResetStudyData,
    required this.onResetProfile,
    required this.onResetSampleData,
    required this.onResetAllData,
  });

  /// Tính toán tiến độ thực tế đạt mục tiêu trong tuần hiện tại (Thứ Hai -> Chủ Nhật)
  /// Dựa hoàn toàn trên các bản ghi trong `study_activities`.
  static WeeklyGoalProgress calculateWeeklyGoalProgress({
    required UserProfile profile,
    required List<StudyActivity> activities,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final localNow = current.toLocal();
    final mondayOffset = localNow.weekday - DateTime.monday;
    final startOfWeek = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      0,
      0,
      0,
    ).subtract(Duration(days: mondayOffset));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    final weekActivities = activities.where((act) {
      final actDate = act.completedAt.toLocal();
      return !actDate.isBefore(startOfWeek) && actDate.isBefore(endOfWeek);
    }).toList();

    int totalMinutes = 0;
    final completedTaskIds = <String>{};
    for (final act in weekActivities) {
      totalMinutes += act.actualMinutes;
      if (act.taskId.isNotEmpty) {
        completedTaskIds.add(act.taskId);
      }
    }

    return WeeklyGoalProgress(
      targetHours: profile.weeklyTargetHours,
      targetTasks: profile.weeklyTargetTasks,
      actualHours: totalMinutes / 60.0,
      actualTasks: completedTaskIds.length,
    );
  }

  void _openEditProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          ProfileEditDialog(initialProfile: profile, onSave: onUpdateProfile),
    );
  }

  void _openEditGoalsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          GoalsEditDialog(profile: profile, onSave: onUpdateGoals),
    );
  }

  Future<void> _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: ctx.textPrimaryColor,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: ctx.textSecondaryColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onConfirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalProgress = calculateWeeklyGoalProgress(
      profile: profile,
      activities: activities,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // 1. Khối Hồ sơ cá nhân
        _buildProfileHeader(context),
        const SizedBox(height: 16),

        // 2. Khối Mục tiêu học tập tuần này
        _buildWeeklyGoalsCard(context, goalProgress),
        const SizedBox(height: 16),

        // 3. Khối Cài đặt ứng dụng
        _buildSettingsSection(context),
        const SizedBox(height: 16),

        // 4. Khối Quản lý dữ liệu & Đặt lại
        _buildDataManagementSection(context),
        const SizedBox(height: 16),

        // 5. Khối Thông tin phiên bản & Ứng dụng
        _buildAboutSection(context),
        const SizedBox(height: 24),
      ],
    );
  }

  // --- WIDGET XÂY DỰNG HỒ SƠ CÁ NHÂN ---

  Widget _buildProfileHeader(BuildContext context) {
    final isSet = profile.isConfigured;
    final avatar = profile.avatar;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar tròn
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: isSet
                  ? avatar.backgroundColor
                  : context.primaryContainerColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSet
                    ? avatar.foregroundColor.withValues(alpha: 0.3)
                    : AppColors.primary.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                isSet ? avatar.icon : Icons.person_outline_rounded,
                size: 44,
                color: isSet ? avatar.foregroundColor : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Tên hiển thị hoặc trạng thái chưa thiết lập
          Text(
            isSet ? profile.name : 'Chưa thiết lập hồ sơ cá nhân',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          // Trường đại học & ngành học
          if (isSet) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    profile.university,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 16,
                  color: context.textSecondaryColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    profile.major,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (profile.academicYear.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceMutedColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Text(
                      profile.academicYear,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ] else ...[
            Text(
              'Cập nhật tên, trường đại học và ngành học để đồng bộ tiến trình học tập của bạn.',
              style: TextStyle(
                color: context.textSecondaryColor,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),

          // Nút thiết lập / chỉnh sửa
          SizedBox(
            width: double.infinity,
            child: isSet
                ? OutlinedButton.icon(
                    key: const ValueKey('profile_edit_open_button'),
                    onPressed: () => _openEditProfileDialog(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Chỉnh sửa hồ sơ'),
                  )
                : FilledButton.icon(
                    key: const ValueKey('profile_setup_open_button'),
                    onPressed: () => _openEditProfileDialog(context),
                    icon: const Icon(Icons.badge_rounded, size: 18),
                    label: const Text('Thiết lập hồ sơ ngay'),
                  ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET MỤC TIÊU HỌC TẬP TUẦN NÀY ---

  Widget _buildWeeklyGoalsCard(
    BuildContext context,
    WeeklyGoalProgress progress,
  ) {
    final hoursFormatted = progress.actualHours.toStringAsFixed(
      progress.actualHours.truncateToDouble() == progress.actualHours ? 0 : 1,
    );
    final targetHoursFormatted = progress.targetHours.toStringAsFixed(
      progress.targetHours.truncateToDouble() == progress.targetHours ? 0 : 1,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề + Nút chỉnh sửa mục tiêu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.track_changes_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mục tiêu học tập tuần này',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                key: const ValueKey('goals_edit_open_button'),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Chỉnh sửa mục tiêu tuần',
                color: AppColors.primary,
                onPressed: () => _openEditGoalsDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mục tiêu 1: Thời lượng học (giờ)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Thời lượng học tập',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
              Text(
                '$hoursFormatted / $targetHoursFormatted giờ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.hoursRate,
              minHeight: 10,
              backgroundColor: context.surfaceMutedColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress.isHoursAchieved
                    ? AppColors.success
                    : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progress.isHoursAchieved
                    ? '🎉 Đã đạt mục tiêu thời lượng!'
                    : 'Còn thiếu ${progress.remainingHours.toStringAsFixed(1)} giờ',
                style: TextStyle(
                  fontSize: 12,
                  color: progress.isHoursAchieved
                      ? AppColors.success
                      : context.textSecondaryColor,
                  fontWeight: progress.isHoursAchieved
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              Text(
                '${(progress.hoursRate * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mục tiêu 2: Số công việc hoàn thành
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Số công việc hoàn thành',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
              Text(
                '${progress.actualTasks} / ${progress.targetTasks} việc',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.tasksRate,
              minHeight: 10,
              backgroundColor: context.surfaceMutedColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress.isTasksAchieved
                    ? AppColors.success
                    : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progress.isTasksAchieved
                    ? '🎉 Đã đạt mục tiêu công việc!'
                    : 'Còn thiếu ${progress.remainingTasks} công việc',
                style: TextStyle(
                  fontSize: 12,
                  color: progress.isTasksAchieved
                      ? AppColors.success
                      : context.textSecondaryColor,
                  fontWeight: progress.isTasksAchieved
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              Text(
                '${(progress.tasksRate * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Thông điệp tạo động lực
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: progress.isAllAchieved
                  ? (context.isDark
                        ? const Color(0xFF064E3B)
                        : AppColors.statusCompletedBg)
                  : context.primaryContainerColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  progress.isAllAchieved
                      ? Icons.emoji_events_rounded
                      : Icons.auto_awesome_rounded,
                  size: 18,
                  color: progress.isAllAchieved
                      ? AppColors.success
                      : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progress.isAllAchieved
                        ? 'Xuất sắc! Bạn đã vượt qua toàn bộ mục tiêu tuần này! 🏆'
                        : 'Tiến độ được tính từ các hoạt động học tập thực tế trong tuần.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: progress.isAllAchieved
                          ? (context.isDark
                                ? const Color(0xFF6EE7B7)
                                : AppColors.success)
                          : (context.isDark
                                ? AppColors.primaryLight
                                : AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET CÀI ĐẶT ỨNG DỤNG ---

  Widget _buildSettingsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cài đặt ứng dụng',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 10),

        // Cài đặt 1: Chế độ giao diện (Sáng / Tối / Hệ thống)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.palette_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Chế độ giao diện',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'system',
                      label: Text('Hệ thống'),
                      icon: Icon(Icons.settings_brightness_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 'light',
                      label: Text('Sáng'),
                      icon: Icon(Icons.light_mode_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      label: Text('Tối'),
                      icon: Icon(Icons.dark_mode_outlined, size: 16),
                    ),
                  ],
                  selected: {profile.themeMode},
                  onSelectionChanged: (newSelection) {
                    onUpdateThemeMode(newSelection.first);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Cài đặt 2: Thông báo nhắc học
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: SwitchListTile(
              key: const ValueKey('reminder_switch'),
              title: Text(
                'Nhắc nhở học tập hàng ngày',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
              subtitle: Text(
                'Lưu tùy chọn nhắc nhở học tập (Thông báo đẩy tự động sẽ được triển khai ở bản cập nhật sau)',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
              secondary: const Icon(
                Icons.notifications_active_outlined,
                color: AppColors.primary,
              ),
              value: profile.reminderEnabled,
              onChanged: onUpdateReminderEnabled,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Trạng thái lưu trữ theo môi trường chạy
        InfoCard(
          icon: kIsWeb ? Icons.cloud_done_outlined : Icons.storage_rounded,
          iconColor: AppColors.primary,
          title: kIsWeb
              ? 'Môi trường Web Preview (localStorage)'
              : 'Cơ sở dữ liệu SQLite cục bộ (v6)',
          subtitle: kIsWeb
              ? 'Hồ sơ, mục tiêu học tập và cài đặt được lưu bền vững trên localStorage của trình duyệt, không mất khi reload.'
              : 'Dữ liệu công việc, môn học, lịch sử và hồ sơ cá nhân được lưu an toàn trong file exampilot.db.',
        ),
      ],
    );
  }

  // --- WIDGET QUẢN LÝ DỮ LIỆU & ĐẶT LẠI ---

  Widget _buildDataManagementSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quản lý dữ liệu & Đặt lại',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 10),

        // 1. Đặt lại tiến độ học tập (giữ nguyên hồ sơ cá nhân & môn học)
        InfoCard(
          icon: Icons.refresh_rounded,
          iconColor: AppColors.primary,
          title: 'Khôi phục dữ liệu mẫu',
          subtitle:
              'Nạp lại 4 môn học mặc định và 3 nhiệm vụ mẫu ban đầu phục vụ kiểm thử giao diện.',
          onTap: () {
            _showConfirmationDialog(
              context,
              title: 'Khôi phục dữ liệu mẫu?',
              message:
                  'Hành động này sẽ ghi lại các môn học mặc định và công việc mẫu. Thông tin hồ sơ cá nhân của bạn sẽ được giữ nguyên.',
              confirmLabel: 'Khôi phục mẫu',
              onConfirm: onResetSampleData,
            );
          },
        ),
        const SizedBox(height: 8),

        // 2. Đặt lại dữ liệu học tập (xóa công việc, hoạt động, streak)
        InfoCard(
          icon: Icons.cleaning_services_outlined,
          iconColor: AppColors.priorityMedium,
          title: 'Đặt lại dữ liệu học tập',
          subtitle:
              'Xóa toàn bộ nhiệm vụ, lịch sử hoạt động và chuỗi học tập (Streak). Thông tin hồ sơ cá nhân được giữ nguyên.',
          onTap: () {
            _showConfirmationDialog(
              context,
              title: 'Xóa toàn bộ công việc học tập?',
              message:
                  'Hành động này sẽ xóa sạch tất cả công việc, lịch sử làm bài và Study Streak để kiểm tra trạng thái rỗng. Thông tin hồ sơ cá nhân của bạn sẽ KHÔNG bị mất.',
              confirmLabel: 'Xác nhận xóa',
              onConfirm: onResetStudyData,
            );
          },
        ),
        const SizedBox(height: 8),

        // 3. Đặt lại thông tin cá nhân (giữ nguyên dữ liệu học tập)
        InfoCard(
          icon: Icons.person_remove_outlined,
          iconColor: AppColors.priorityMedium,
          title: 'Đặt lại hồ sơ cá nhân',
          subtitle:
              'Xóa tên, trường đại học, ngành học và đưa mục tiêu học tập về mặc định. Dữ liệu công việc được giữ nguyên.',
          onTap: () {
            _showConfirmationDialog(
              context,
              title: 'Đặt lại hồ sơ cá nhân?',
              message:
                  'Hành động này sẽ xóa tên hiển thị, trường học, ngành học và đưa các mục tiêu học tập về giá trị mặc định ban đầu. Tất cả công việc và điểm đánh giá học tập sẽ được bảo toàn.',
              confirmLabel: 'Đặt lại hồ sơ',
              onConfirm: onResetProfile,
            );
          },
        ),
        const SizedBox(height: 8),

        // 4. Khôi phục toàn bộ (Xóa trắng toàn bộ ứng dụng)
        InfoCard(
          icon: Icons.delete_forever_outlined,
          iconColor: AppColors.error,
          title: 'Khôi phục toàn bộ ứng dụng',
          subtitle:
              'Xóa hoàn toàn mọi dữ liệu người dùng tạo (hồ sơ, môn học, công việc, hoạt động) và đưa về trạng thái xuất xưởng.',
          onTap: () {
            _showConfirmationDialog(
              context,
              title: 'Xác nhận khôi phục toàn bộ?',
              message:
                  'CẢNH BÁO: Toàn bộ dữ liệu của bạn bao gồm hồ sơ cá nhân, tất cả môn học, công việc và lịch sử hoạt động sẽ bị xóa sạch hoàn toàn. Hành động này không thể hoàn tác.',
              confirmLabel: 'Xóa tất cả',
              onConfirm: onResetAllData,
            );
          },
        ),
      ],
    );
  }

  // --- WIDGET VỀ ỨNG DỤNG ---

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thông tin ứng dụng',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 10),
        const InfoCard(
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.primary,
          title: 'ExamPilot phiên bản 1.0 (Giai đoạn 6 - Hoàn thiện UI/UX)',
          subtitle:
              'Ứng dụng hỗ trợ sinh viên tự học và quản lý môn học hiệu quả theo tiêu chuẩn UI/UX Pro Max. Dữ liệu chạy hoàn toàn offline và cục bộ trên thiết bị của bạn.',
        ),
      ],
    );
  }
}
