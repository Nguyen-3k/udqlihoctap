import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';
import '../repositories/subject_repository.dart';
import '../repositories/task_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/task_form_dialog.dart';
import 'overview_screen.dart';
import 'plan_screen.dart';
import 'profile_screen.dart';
import 'statistics_screen.dart';
import 'subjects_screen.dart';

// Bí danh tương thích ngược
const primaryColor = AppColors.primary;
const backgroundColor = AppColors.background;

/// Màn hình khung chính quản lý điều hướng 5 tab và lưu trữ dữ liệu bền vững qua SQLite (Android)
/// hoặc chế độ xem trước an toàn trên Web (không gọi sqflite).
class AppShell extends StatefulWidget {
  final TaskRepository? taskRepository;
  final SubjectRepository? subjectRepository;

  const AppShell({super.key, this.taskRepository, this.subjectRepository});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;

  late final TaskRepository _taskRepository;
  late final SubjectRepository _subjectRepository;

  // Danh mục môn học đồng bộ từ SQLite hoặc Web preview
  List<Subject> _subjects = [];

  // Danh sách công việc được đồng bộ từ SQLite hoặc Web preview
  List<StudyTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _taskRepository = widget.taskRepository ?? TaskRepository();
    _subjectRepository = widget.subjectRepository ?? SubjectRepository();
    _loadData();
  }

  /// Tải đồng bộ cả môn học và nhiệm vụ từ các Repository.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final subjectsFuture = _subjectRepository.getAllSubjects();
      final tasksFuture = _taskRepository.getAllTasks();

      final results = await Future.wait([subjectsFuture, tasksFuture]);
      final loadedSubjects = results[0] as List<Subject>;
      final loadedTasks = results[1] as List<StudyTask>;

      if (!mounted) return;
      setState(() {
        _subjects = loadedSubjects;
        _tasks = loadedTasks;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      if (!mounted) return;
      debugPrint('LỖI TRUY XUẤT CƠ SỞ DỮ LIỆU: $e\n$stackTrace');

      // Chỉ trên Web (không có sqflite) mới dùng dữ liệu xem trước
      if (kIsWeb) {
        setState(() {
          _subjects = SubjectRepository.getDefaultSubjects();
          _tasks = _getSampleTasks();
          _isLoading = false;
          _errorMessage = null;
        });
        return;
      }

      // Trên Android / Thiết bị di động: Tuyệt đối không tự động nạp dữ liệu mẫu ghi đè dữ liệu người dùng.
      // Giữ nguyên exception và hiển thị lỗi trung thực lên giao diện.
      setState(() {
        _errorMessage = 'Lỗi truy xuất cơ sở dữ liệu: $e';
        _isLoading = false;
      });
    }
  }

  List<StudyTask> _getSampleTasks() {
    final now = DateTime.now();
    return [
      StudyTask(
        id: 'task_1',
        title: 'Ôn tập chương 3 Đạo hàm',
        subjectId: 'subj_1',
        subject: 'Toán cao cấp',
        deadline: now.add(const Duration(hours: 4)),
        estimatedMinutes: 60,
        priority: TaskPriority.high,
        status: TaskStatus.inProgress,
        notes: 'Cần chú ý công thức đạo hàm hàm hợp và định lý Fermat.',
      ),
      StudyTask(
        id: 'task_2',
        title: 'Thực hành viết câu lệnh SQL JOIN',
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
        deadline: now.add(const Duration(days: 1)),
        estimatedMinutes: 45,
        priority: TaskPriority.medium,
        status: TaskStatus.todo,
        notes: 'Phân biệt rõ ràng giữa INNER JOIN và LEFT JOIN.',
      ),
      StudyTask(
        id: 'task_3',
        title: 'Đọc tài liệu CSS Flexbox & Grid',
        subjectId: 'subj_2',
        subject: 'Lập trình Web',
        deadline: now.subtract(const Duration(hours: 2)),
        estimatedMinutes: 30,
        priority: TaskPriority.low,
        status: TaskStatus.completed,
        notes: 'Đã nắm vững align-items và justify-content.',
      ),
    ];
  }

  // --- TIỆN ÍCH THÔNG BÁO NHẸ NHÀNG, KHÔNG CHE NỘI DUNG VÀ KHÔNG XẾP CHỒNG ---

  void _showNotification(
    String message, {
    bool isError = false,
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    if (!mounted) return;
    // Xóa ngay thông báo cũ để không xếp chồng khi người dùng tương tác liên tục
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  // --- CÁC HÀM XỬ LÝ NGHIỆP VỤ CRUD NHIỆM VỤ (TASK) ---

  Future<void> _addTask(StudyTask newTask) async {
    try {
      await _taskRepository.insertTask(newTask);
      if (!mounted) return;
      setState(() {
        _tasks.insert(0, newTask);
      });
      _showNotification(
        kIsWeb
            ? 'Đã thêm: "${newTask.title}" (Chế độ xem trước Web)'
            : 'Đã lưu công việc: "${newTask.title}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi thêm công việc: $e', isError: true);
    }
  }

  Future<void> _updateTask(StudyTask updatedTask) async {
    try {
      await _taskRepository.updateTask(updatedTask);
      if (!mounted) return;
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
        if (index != -1) {
          _tasks[index] = updatedTask;
        }
      });
      _showNotification(
        kIsWeb
            ? 'Đã cập nhật: "${updatedTask.title}" (Chế độ xem trước Web)'
            : 'Đã cập nhật: "${updatedTask.title}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật: $e', isError: true);
    }
  }

  Future<void> _deleteTask(StudyTask taskToDelete) async {
    try {
      await _taskRepository.deleteTask(taskToDelete.id);
      if (!mounted) return;
      setState(() {
        _tasks.removeWhere((t) => t.id == taskToDelete.id);
      });
      _showNotification(
        kIsWeb
            ? 'Đã xóa: "${taskToDelete.title}" (Chế độ xem trước Web)'
            : 'Đã xóa công việc: "${taskToDelete.title}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi xóa: $e', isError: true);
    }
  }

  Future<void> _toggleTaskComplete(StudyTask task) async {
    final newStatus = task.isCompleted ? TaskStatus.todo : TaskStatus.completed;

    try {
      // 1. Ghi nhận thay đổi xuống repository/database trước
      await _taskRepository.updateTaskStatus(task.id, newStatus);

      // 2. Chỉ khi ghi SQLite thành công mới cập nhật giao diện
      if (!mounted) return;
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = _tasks[index].copyWith(status: newStatus);
        }
        task.status = newStatus;
      });

      // 3. Thông báo nhanh gọn (1.5s), không xếp chồng và không che nội dung
      _showNotification(
        newStatus == TaskStatus.completed
            ? (kIsWeb
                  ? 'Đã hoàn thành công việc 🎉 (Xem trước Web)'
                  : 'Đã hoàn thành công việc 🎉')
            : 'Đã chuyển về Chưa làm',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật trạng thái: $e', isError: true);
    }
  }

  void _openTaskForm({StudyTask? initialTask, String? preselectedSubjectId}) {
    showDialog(
      context: context,
      builder: (context) => TaskFormDialog(
        initialTask: initialTask,
        subjects: _subjects,
        preselectedSubjectId: preselectedSubjectId,
        onSave: (savedTask) {
          if (initialTask == null) {
            _addTask(savedTask);
          } else {
            _updateTask(savedTask);
          }
        },
      ),
    );
  }

  void _openTaskDetail(StudyTask task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        task: task,
        onToggleComplete: () => _toggleTaskComplete(task),
        onEdit: () => _openTaskForm(initialTask: task),
        onDelete: () => _deleteTask(task),
      ),
    );
  }

  // --- CÁC HÀM XỬ LÝ NGHIỆP VỤ CRUD MÔN HỌC (SUBJECT) ---

  Future<void> _addSubject(Subject newSubject) async {
    try {
      await _subjectRepository.insertSubject(newSubject);
      if (!mounted) return;
      setState(() {
        _subjects.add(newSubject);
      });
      _showNotification(
        kIsWeb
            ? 'Đã thêm môn: "${newSubject.name}" (Xem trước Web)'
            : 'Đã thêm và lưu môn: "${newSubject.name}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi thêm môn học: $e', isError: true);
    }
  }

  Future<void> _updateSubject(Subject updatedSubject) async {
    try {
      await _subjectRepository.updateSubject(updatedSubject);
      await _taskRepository.updateTasksSubjectName(
        updatedSubject.id,
        updatedSubject.name,
      );

      if (!mounted) return;
      setState(() {
        final subIndex = _subjects.indexWhere((s) => s.id == updatedSubject.id);
        if (subIndex != -1) {
          _subjects[subIndex] = updatedSubject;
        }
        for (final t in _tasks) {
          if (t.subjectId == updatedSubject.id) {
            t.subject = updatedSubject.name;
          }
        }
      });

      _showNotification(
        kIsWeb
            ? 'Đã cập nhật môn: "${updatedSubject.name}" (Xem trước Web)'
            : 'Đã cập nhật môn: "${updatedSubject.name}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật môn học: $e', isError: true);
    }
  }

  Future<void> _deleteSubject(
    String subjectId, {
    String? migrateToSubjectId,
  }) async {
    try {
      // 1. Nếu có môn đích để chuyển giao nhiệm vụ
      if (migrateToSubjectId != null && migrateToSubjectId.isNotEmpty) {
        final targetSub = _subjects.firstWhere(
          (s) => s.id == migrateToSubjectId,
        );
        await _taskRepository.migrateTasksSubject(
          subjectId,
          migrateToSubjectId,
          targetSub.name,
        );
      }

      // 2. Xóa môn học trong repository
      await _subjectRepository.deleteSubject(subjectId);

      // 3. Tải lại toàn bộ dữ liệu để cập nhật đồng bộ UI
      await _loadData();

      if (!mounted) return;
      _showNotification(
        migrateToSubjectId != null
            ? 'Đã chuyển toàn bộ nhiệm vụ và xóa môn học thành công.'
            : 'Đã xóa môn học thành công.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi xóa môn học: $e', isError: true);
    }
  }

  // --- CÔNG CỤ DỌN DẸP / KHÔI PHỤC DỮ LIỆU ---

  Future<void> _resetSampleData() async {
    try {
      final sampleSubjects = SubjectRepository.getDefaultSubjects();
      final sampleTasks = _getSampleTasks();
      await _subjectRepository.resetDefaultSubjects(sampleSubjects);
      await _taskRepository.resetSampleTasks(sampleTasks);
      await _loadData();
      if (!mounted) return;
      _showNotification('Đã khôi phục dữ liệu mẫu thành công');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi khôi phục dữ liệu mẫu: $e', isError: true);
    }
  }

  Future<void> _clearAllTasks() async {
    try {
      await _taskRepository.clearAllTasks();
      await _loadData();
      if (!mounted) return;
      _showNotification('Đã xóa tất cả công việc');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi xóa toàn bộ: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.school_rounded, color: AppColors.primary, size: 26),
            SizedBox(width: 8),
            Text(
              'ExamPilot',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              _showNotification(
                kIsWeb
                    ? 'Chế độ Web Preview: Dữ liệu mẫu chỉ phục vụ xem trước giao diện và không làm thay đổi dữ liệu SQLite trên Android.'
                    : 'Dữ liệu hiện đang được đồng bộ và lưu trữ cục bộ bằng SQLite.',
                duration: const Duration(seconds: 2),
              );
            },
            icon: Icon(
              kIsWeb ? Icons.cloud_done_outlined : Icons.storage_rounded,
              color: AppColors.primary,
            ),
            tooltip: kIsWeb ? 'Chế độ Web Preview' : 'Trạng thái CSDL',
          ),
          IconButton(
            onPressed: () {
              _showNotification(
                'Tính năng thông báo tự động sẽ được triển khai ở giai đoạn thông báo.',
                duration: const Duration(seconds: 2),
              );
            },
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Thông báo',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Banner thông báo rõ ràng khi chạy trên nền tảng Web
          if (kIsWeb)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.primaryContainer,
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bản xem trước Web: Dữ liệu chỉ phục vụ preview giao diện, không ghi đè dữ liệu SQLite trên Android.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton:
          (!_isLoading && (_selectedIndex == 0 || _selectedIndex == 1))
          ? FloatingActionButton.extended(
              onPressed: () => _openTaskForm(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Thêm việc',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Tổng quan',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Kế hoạch',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Môn học',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Thống kê',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Cá nhân',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              kIsWeb
                  ? 'Đang nạp dữ liệu xem trước Web...'
                  : 'Đang tải dữ liệu từ SQLite...',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 52,
              ),
              const SizedBox(height: 14),
              const Text(
                'Lỗi truy xuất cơ sở dữ liệu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                      _loadData();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Thử lại'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _subjects = SubjectRepository.getDefaultSubjects();
                        _tasks = _getSampleTasks();
                        _errorMessage = null;
                        _isLoading = false;
                      });
                    },
                    icon: const Icon(Icons.preview_rounded),
                    label: const Text('Tiếp tục với dữ liệu mẫu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final pages = [
      OverviewScreen(
        tasks: _tasks,
        onToggleComplete: _toggleTaskComplete,
        onTapTask: _openTaskDetail,
        onEditTask: (task) => _openTaskForm(initialTask: task),
        onDeleteTask: _deleteTask,
        onAddTask: () => _openTaskForm(),
        onGoToPlan: () => setState(() => _selectedIndex = 1),
      ),
      PlanScreen(
        tasks: _tasks,
        onToggleComplete: _toggleTaskComplete,
        onTapTask: _openTaskDetail,
        onEditTask: (task) => _openTaskForm(initialTask: task),
        onDeleteTask: _deleteTask,
        onAddTask: () => _openTaskForm(),
      ),
      SubjectsScreen(
        subjects: _subjects,
        tasks: _tasks,
        onAddSubject: _addSubject,
        onUpdateSubject: _updateSubject,
        onDeleteSubject: _deleteSubject,
        onToggleCompleteTask: _toggleTaskComplete,
        onTapTask: _openTaskDetail,
        onEditTask: (task) => _openTaskForm(initialTask: task),
        onDeleteTask: _deleteTask,
        onAddTaskForSubject: (subject) =>
            _openTaskForm(preselectedSubjectId: subject.id),
      ),
      StatisticsScreen(tasks: _tasks),
      ProfileScreen(
        onResetSampleData: _resetSampleData,
        onClearAllTasks: _clearAllTasks,
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
    );
  }
}
