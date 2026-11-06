import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/info_card.dart';

/// Màn hình Cá nhân & Cài đặt.
/// Hiển thị thông tin người học, trạng thái lộ trình dự án và công cụ hỗ trợ kiểm thử.
class ProfileScreen extends StatelessWidget {
  final VoidCallback onResetSampleData;
  final VoidCallback onClearAllTasks;

  const ProfileScreen({
    super.key,
    required this.onResetSampleData,
    required this.onClearAllTasks,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Avatar cá nhân
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.person, size: 44, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Người học ExamPilot',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Lập kế hoạch • Học tập • Tiến bộ mỗi ngày',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),

        // Trạng thái dự án
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.flag_circle_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Lộ trình phát triển ExamPilot',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                '• Giai đoạn 1 & 2: Giao diện 5 tab & CRUD cơ bản [Hoàn thành]',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              Text(
                '• Giai đoạn 3: Lưu trữ cục bộ SQLite Android & Web Preview an toàn [Hoạt động]',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              Text(
                '• Giai đoạn 4: Hoàn thiện Design System UI/UX Pro Max [Hoàn thành]',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              Text(
                '• Giai đoạn 5 & 6: Đánh giá sau học & Thông báo nhắc nhở [Sắp tới]',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Trạng thái lưu trữ theo nền tảng
        Text(
          kIsWeb ? 'Lưu trữ & Môi trường chạy' : 'Lưu trữ cục bộ',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InfoCard(
          icon: kIsWeb ? Icons.cloud_done_outlined : Icons.storage_rounded,
          iconColor: AppColors.primary,
          title: kIsWeb
              ? 'Chế độ xem trước Web (Web Preview)'
              : 'Cơ sở dữ liệu SQLite',
          subtitle: kIsWeb
              ? 'Dữ liệu chỉ phục vụ xem trước giao diện trên trình duyệt và không làm thay đổi dữ liệu SQLite trên thiết bị Android.'
              : 'Dữ liệu công việc được lưu bền vững trong file exampilot.db (bảng study_tasks), không bị mất khi đóng app.',
        ),

        const SizedBox(height: 16),
        // Công cụ hỗ trợ kiểm thử cho sinh viên
        Text(
          kIsWeb
              ? 'Công cụ kiểm thử dữ liệu xem trước'
              : 'Công cụ kiểm thử dữ liệu SQLite',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InfoCard(
          icon: Icons.refresh_rounded,
          iconColor: AppColors.primary,
          title: 'Khôi phục dữ liệu mẫu',
          subtitle: kIsWeb
              ? 'Khôi phục 3 công việc mẫu trên Web để kiểm tra giao diện.'
              : 'Ghi lại 3 công việc mẫu vào SQLite để kiểm tra giao diện.',
          onTap: () {
            onResetSampleData();
          },
        ),
        InfoCard(
          icon: Icons.delete_sweep_outlined,
          iconColor: AppColors.error,
          title: 'Xóa toàn bộ công việc',
          subtitle: kIsWeb
              ? 'Xóa toàn bộ danh sách tạm trên Web để kiểm tra trạng thái rỗng.'
              : 'Xóa sạch dữ liệu trong bảng SQLite để kiểm tra trạng thái rỗng.',
          onTap: () {
            onClearAllTasks();
          },
        ),

        const SizedBox(height: 16),
        const Text(
          'Về ứng dụng',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const InfoCard(
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.primary,
          title: 'ExamPilot phiên bản 1.0 (Design System)',
          subtitle:
              'Ứng dụng học tập cá nhân phát triển bằng Flutter cho sinh viên theo tiêu chuẩn UI/UX Pro Max.',
        ),
      ],
    );
  }
}
