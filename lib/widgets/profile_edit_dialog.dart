import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';

/// Hộp thoại thiết lập và chỉnh sửa Hồ sơ cá nhân.
class ProfileEditDialog extends StatefulWidget {
  final UserProfile initialProfile;
  final ValueChanged<UserProfile> onSave;

  const ProfileEditDialog({
    super.key,
    required this.initialProfile,
    required this.onSave,
  });

  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _universityController;
  late final TextEditingController _majorController;
  late final TextEditingController _academicYearController;
  late String _selectedAvatarId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProfile.name);
    _universityController = TextEditingController(
      text: widget.initialProfile.university,
    );
    _majorController = TextEditingController(text: widget.initialProfile.major);
    _academicYearController = TextEditingController(
      text: widget.initialProfile.academicYear,
    );
    _selectedAvatarId = widget.initialProfile.avatarId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _universityController.dispose();
    _majorController.dispose();
    _academicYearController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_formKey.currentState?.validate() ?? false) {
      final updated = widget.initialProfile.copyWith(
        name: _nameController.text.trim(),
        university: _universityController.text.trim(),
        major: _majorController.text.trim(),
        academicYear: _academicYearController.text.trim(),
        avatarId: _selectedAvatarId,
      );
      widget.onSave(updated);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tiêu đề
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.initialProfile.isConfigured
                            ? 'Chỉnh sửa hồ sơ cá nhân'
                            : 'Thiết lập hồ sơ cá nhân',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Chọn ảnh đại diện (Avatar Selector)
                Text(
                  'Chọn biểu tượng đại diện',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: AvatarPreset.presets.map((preset) {
                    final isSelected = preset.id == _selectedAvatarId;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedAvatarId = preset.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: preset.backgroundColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          preset.icon,
                          color: preset.foregroundColor,
                          size: 24,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Tên hiển thị
                TextFormField(
                  key: const ValueKey('profile_name_field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị *',
                    hintText: 'VD: Nguyễn Văn A',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập tên hiển thị';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Trường đại học
                TextFormField(
                  key: const ValueKey('profile_university_field'),
                  controller: _universityController,
                  decoration: const InputDecoration(
                    labelText: 'Trường đại học *',
                    hintText: 'VD: Đại học Bách Khoa',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập trường đại học';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Ngành học
                TextFormField(
                  key: const ValueKey('profile_major_field'),
                  controller: _majorController,
                  decoration: const InputDecoration(
                    labelText: 'Ngành học *',
                    hintText: 'VD: Công nghệ Thông tin',
                    prefixIcon: Icon(Icons.auto_stories_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập ngành học';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Khóa học / Năm học (không bắt buộc)
                TextFormField(
                  key: const ValueKey('profile_year_field'),
                  controller: _academicYearController,
                  decoration: const InputDecoration(
                    labelText: 'Khóa / Năm học (tùy chọn)',
                    hintText: 'VD: K65 hoặc Năm 3',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                ),
                const SizedBox(height: 24),

                // Nút thao tác
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('profile_save_button'),
                      onPressed: _handleSave,
                      child: const Text('Lưu hồ sơ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
