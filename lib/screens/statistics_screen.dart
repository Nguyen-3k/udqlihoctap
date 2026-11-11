import 'package:flutter/material.dart';
import '../models/study_activity.dart';
import '../models/study_statistics.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../theme/app_colors.dart';

/// Màn hình Thống kê học tập (G4).
/// Tổng hợp chỉ số thực tế, biểu đồ hoạt động 7 ngày và tiến độ môn học theo subjectId.
class StatisticsScreen extends StatefulWidget {
  final List<StudyTask> tasks;
  final List<Subject> subjects;
  final List<StudyActivity> activities;

  const StatisticsScreen({
    super.key,
    required this.tasks,
    this.subjects = const [],
    this.activities = const [],
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  StatisticsPeriod _selectedPeriod = StatisticsPeriod.last7Days;
  int _selectedDayIndex = 0; // 0 = T2 ... 6 = CN

  @override
  void initState() {
    super.initState();
    // Mặc định chọn ngày hôm nay trong tuần (thứ 2 là 0, CN là 6)
    final localNow = DateTime.now().toLocal();
    _selectedDayIndex = (localNow.weekday - 1).clamp(0, 6);
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '0 phút';
    if (minutes < 60) return '$minutes phút';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (remaining == 0) return '$hours giờ';
    return '$hours giờ $remaining phút';
  }

  @override
  Widget build(BuildContext context) {
    // Tách riêng logic tính toán thống kê
    final stats = StudyStatisticsCalculator.calculate(
      tasks: widget.tasks,
      subjects: widget.subjects,
      activities: widget.activities,
      period: _selectedPeriod,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // --- 1. TIÊU ĐỀ & MÔ TẢ ---
        Text(
          'Thống kê học tập',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Theo dõi hoạt động tự học trong kỳ và tiến độ danh mục công việc',
          style: TextStyle(color: context.textSecondaryColor, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // --- 2. NHÓM B: TRẠNG THÁI DANH MỤC CÔNG VIỆC HIỆN TẠI ---
        _buildCurrentInventoryHeader(),
        const SizedBox(height: 12),
        _buildOverallCompletionCard(stats),
        const SizedBox(height: 12),
        _buildCurrentInventoryMetrics(stats),
        const SizedBox(height: 24),

        // --- 3. NHÓM A: HOẠT ĐỘNG HỌC TẬP TRONG KỲ ---
        _buildPeriodSelector(),
        const SizedBox(height: 16),
        _buildPeriodActivityHeader(),
        const SizedBox(height: 12),
        _buildPeriodActivityMetrics(stats),
        const SizedBox(height: 20),

        // BIỂU ĐỒ HOẠT ĐỘNG HỌC TẬP THEO TUẦN (7 NGÀY T2 -> CN)
        _buildWeeklyChartSection(stats),
        const SizedBox(height: 24),

        // --- 5. THỐNG KÊ TIẾN ĐỘ THEO MÔN HỌC ---
        _buildSubjectStatisticsSection(stats),
        const SizedBox(height: 20),

        // Ghi chú dữ liệu thực tế
        _buildFooterNote(),
        const SizedBox(height: 24),
      ],
    );
  }

  // --- BỘ LỌC KHOẢNG THỜI GIAN ---
  Widget _buildPeriodSelector() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.surfaceMutedColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: StatisticsPeriod.values.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedPeriod = period;
                });
              },
              borderRadius: BorderRadius.circular(9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? context.surfaceColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: context.isDark ? 0.2 : 0.05,
                            ),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  period.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? (context.isDark
                              ? AppColors.primaryLight
                              : AppColors.primary)
                        : context.textSecondaryColor,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- TIÊU ĐỀ NHÓM A: HOẠT ĐỘNG HỌC TẬP TRONG KỲ ---
  Widget _buildPeriodActivityHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.insights_rounded,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hoạt động học tập trong kỳ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: context.primaryContainerColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Kỳ: ${_selectedPeriod.label}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.isDark
                      ? AppColors.primaryLight
                      : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Số liệu nỗ lực tự học ghi nhận từ các buổi học hoàn thành thực tế trong ${_selectedPeriod.label.toLowerCase()}',
          style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
        ),
      ],
    );
  }

  // --- CÁC CHỈ SỐ NHÓM A: HOẠT ĐỘNG HỌC TẬP TRONG KỲ ---
  Widget _buildPeriodActivityMetrics(StudyStatistics stats) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.task_alt_rounded,
            iconColor: AppColors.primary,
            title: 'Lượt hoàn thành',
            value: '${stats.periodCompletedTasks}',
            subtitle: 'Trong ${_selectedPeriod.label.toLowerCase()}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFF7C3AED), // Tím năng động
            title: 'Thời lượng thực tế',
            value: _formatDuration(stats.totalActualMinutes),
            subtitle: 'Thời gian tự học',
          ),
        ),
      ],
    );
  }

  // --- TIÊU ĐỀ NHÓM B: TRẠNG THÁI DANH MỤC CÔNG VIỆC HIỆN TẠI ---
  Widget _buildCurrentInventoryHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.format_list_bulleted_rounded,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Trạng thái danh mục công việc',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Tình trạng toàn bộ các bài tập đang quản lý trong ứng dụng (không phụ thuộc bộ lọc thời gian)',
          style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
        ),
      ],
    );
  }

  // --- THẺ TỶ LỆ HOÀN THÀNH DANH MỤC HIỆN TẠI ---
  Widget _buildOverallCompletionCard(StudyStatistics stats) {
    final percentInt = (stats.currentCompletionRate * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tỷ lệ hoàn thành nhiệm vụ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.primaryContainerColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$percentInt%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.isDark
                        ? AppColors.primaryLight
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: stats.currentCompletionRate,
              minHeight: 10,
              backgroundColor: context.surfaceMutedColor,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            stats.totalTasks == 0
                ? 'Chưa có công việc nào trong danh mục.'
                : 'Đang hoàn thành ${stats.currentCompletedTasks} / ${stats.totalTasks} công việc hiện có (${stats.pendingTasks} việc chưa xong)',
            style: TextStyle(
              color: context.textSecondaryColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // --- LƯỚI CÁC CHỈ SỐ DANH MỤC HIỆN TẠI (NHÓM B) ---
  Widget _buildCurrentInventoryMetrics(StudyStatistics stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.checklist_rounded,
                iconColor: AppColors.primary,
                title: 'Tổng công việc',
                value: '${stats.totalTasks}',
                subtitle: 'Toàn bộ danh mục',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.check_circle_rounded,
                iconColor: AppColors.statusCompleted,
                title: 'Đã hoàn thành',
                value: '${stats.currentCompletedTasks}',
                subtitle: 'Đạt ${(stats.currentCompletionRate * 100).round()}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.timelapse_rounded,
                iconColor: AppColors.statusInProgress,
                title: 'Đang làm',
                value: '${stats.inProgressTasks}',
                subtitle: 'Đang tiến hành',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.pending_actions_rounded,
                iconColor: AppColors.priorityMedium,
                title: 'Chưa làm',
                value: '${stats.todoTasks}',
                subtitle: 'Chưa bắt đầu',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.hourglass_empty_rounded,
                iconColor: AppColors.error,
                title: 'Chưa hoàn thành',
                value: '${stats.pendingTasks}',
                subtitle: 'Cần hoàn thành tiếp',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.menu_book_rounded,
                iconColor: const Color(0xFF0284C7),
                title: 'Môn học quản lý',
                value: '${stats.totalSubjects}',
                subtitle: 'Danh mục hiện có',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  // --- BIỂU ĐỒ HOẠT ĐỘNG HỌC TẬP THEO TUẦN (7 NGÀY) ---
  Widget _buildWeeklyChartSection(StudyStatistics stats) {
    final weeklyMetrics = stats.weeklyMetrics;
    final maxTasks = weeklyMetrics.fold<int>(
      1,
      (max, m) => m.completedTasks > max ? m.completedTasks : max,
    );
    final maxMinutes = weeklyMetrics.fold<int>(
      30,
      (max, m) => m.actualMinutes > max ? m.actualMinutes : max,
    );

    final selectedDay =
        (_selectedDayIndex >= 0 && _selectedDayIndex < weeklyMetrics.length)
        ? weeklyMetrics[_selectedDayIndex]
        : weeklyMetrics.first;

    final localNow = DateTime.now().toLocal();
    final todayKey =
        '${localNow.year}-${localNow.month.toString().padLeft(2, '0')}-${localNow.day.toString().padLeft(2, '0')}';

    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hoạt động học tập tuần này',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Thứ Hai – Chủ Nhật (theo ngày thực tế)',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Biểu đồ thể hiện số việc hoàn thành và thời lượng học thực tế ghi nhận mỗi ngày trong tuần.',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: context.textSecondaryColor,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Chú thích (Legend)
          Row(
            children: [
              _buildLegendItem(
                color: AppColors.primary,
                label: 'Số việc hoàn thành',
              ),
              const SizedBox(width: 14),
              _buildLegendItem(
                color: const Color(0xFF10B981), // Emerald/Xanh lá thời lượng
                label: 'Thời lượng (phút)',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Khung chứa biểu đồ cột 7 ngày
          SizedBox(
            height: 175,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(weeklyMetrics.length, (index) {
                final dayMetric = weeklyMetrics[index];
                final isSelected = index == _selectedDayIndex;
                final isToday = dayMetric.dateKey == todayKey;

                // Tỷ lệ chiều cao cột (tối đa 100px)
                const double chartBarHeight = 90.0;
                final taskHeight = dayMetric.completedTasks > 0
                    ? ((dayMetric.completedTasks / maxTasks) * chartBarHeight)
                          .clamp(8.0, chartBarHeight)
                    : 4.0;
                final minuteHeight = dayMetric.actualMinutes > 0
                    ? ((dayMetric.actualMinutes / maxMinutes) * chartBarHeight)
                          .clamp(8.0, chartBarHeight)
                    : 4.0;

                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedDayIndex = index;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.primaryContainerColor.withValues(
                                alpha: 0.4,
                              )
                            : (isToday
                                  ? context.surfaceMutedColor.withValues(
                                      alpha: 0.5,
                                    )
                                  : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isToday
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : Colors.transparent),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Cặp cột kép: Cột công việc (Primary) & Cột phút (Emerald)
                          SizedBox(
                            height: chartBarHeight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Cột số lượng công việc
                                Container(
                                  width: 8,
                                  height: taskHeight,
                                  decoration: BoxDecoration(
                                    color: dayMetric.completedTasks > 0
                                        ? AppColors.primary
                                        : context.borderColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                // Cột thời lượng (phút)
                                Container(
                                  width: 8,
                                  height: minuteHeight,
                                  decoration: BoxDecoration(
                                    color: dayMetric.actualMinutes > 0
                                        ? const Color(0xFF10B981)
                                        : context.borderColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Thứ (T2, T3... CN)
                          Text(
                            dayMetric.weekdayLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : (isToday
                                        ? AppColors.primary
                                        : context.textPrimaryColor),
                            ),
                          ),
                          const SizedBox(height: 2),

                          // Ngày tháng (dd/MM)
                          Text(
                            dayMetric.dateLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.primary
                                  : context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Trạng thái rỗng khi cả tuần chưa có dữ liệu
          if (!stats.hasWeeklyData)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.primaryContainerColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tuần này chưa có hoạt động học tập nào. Hãy đánh dấu hoàn thành công việc để bắt đầu tích lũy!',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Bảng chi tiết tương tác ngày được chọn
          _buildDayDetailCard(selectedDay, todayKey),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: context.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildDayDetailCard(DailyStudyMetric day, String todayKey) {
    final isToday = day.dateKey == todayKey;
    final hasActivity = day.completedTasks > 0 || day.actualMinutes > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMutedColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasActivity
                  ? context.primaryContainerColor
                  : context.surfaceMutedColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasActivity
                  ? Icons.check_circle_outline_rounded
                  : Icons.bedtime_outlined,
              size: 20,
              color: hasActivity
                  ? AppColors.primary
                  : context.textSecondaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${day.weekdayLabel} (${day.dateLabel})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Hôm nay',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  hasActivity
                      ? '${day.completedTasks} công việc hoàn thành • ${_formatDuration(day.actualMinutes)} học thực tế'
                      : 'Không có hoạt động học tập nào được ghi nhận',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasActivity
                        ? context.textPrimaryColor
                        : context.textSecondaryColor,
                    fontWeight: hasActivity
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- THỐNG KÊ TIẾN ĐỘ THEO MÔN HỌC ---
  Widget _buildSubjectStatisticsSection(StudyStatistics stats) {
    final subjectMetrics = stats.subjectMetrics;

    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tiến độ theo môn học',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Phân bổ công việc và thời lượng tích lũy',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
              Text(
                '${subjectMetrics.length} môn',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (subjectMetrics.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Text(
                'Chưa có môn học nào được quản lý.',
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 13,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: subjectMetrics.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 20, color: context.borderColor),
              itemBuilder: (context, index) {
                final metric = subjectMetrics[index];
                return _buildSubjectProgressItem(metric);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectProgressItem(SubjectStudyMetric metric) {
    final sub = metric.subject;
    final color = sub.color;
    final percentInt = (metric.completionRate * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sub.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$percentInt%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: metric.completionRate,
            minHeight: 7,
            backgroundColor: color.withValues(alpha: 0.15),
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              metric.totalTasks == 0
                  ? 'Chưa có công việc'
                  : 'Danh mục: ${metric.currentCompletedTasks} / ${metric.totalTasks} việc',
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 13,
                  color: context.textSecondaryColor,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(metric.actualMinutes),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.primaryContainerColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dữ liệu hoạt động học tập được tính toán độc lập từ study_activities dựa trên thời điểm hoàn thành bài học thực tế, không dùng deadline. Trạng thái danh mục phản ánh toàn bộ công việc hiện tại.',
              style: TextStyle(
                fontSize: 12,
                color: context.textPrimaryColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
