import 'task_priority.dart';
import 'task_status.dart';

/// Đại diện cho một công việc học tập trong ExamPilot.
class StudyTask {
  final String id;
  String title;

  /// Khóa ID môn học duy nhất liên kết với bảng `subjects`.
  String subjectId;

  /// Tên môn học hiển thị (được cập nhật đồng bộ khi đổi tên môn học).
  String subject;

  DateTime deadline;
  int estimatedMinutes;
  TaskPriority priority;
  TaskStatus status;
  String notes;

  StudyTask({
    required this.id,
    required this.title,
    String? subjectId,
    required this.subject,
    required this.deadline,
    required this.estimatedMinutes,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.todo,
    this.notes = '',
  }) : subjectId = (subjectId != null && subjectId.isNotEmpty)
           ? subjectId
           : _resolveSubjectIdFromName(subject);

  /// Kiểm tra xem công việc đã hoàn thành chưa.
  bool get isCompleted => status == TaskStatus.completed;

  /// Kiểm tra xem công việc đã quá hạn hay chưa.
  bool get isOverdue => !isCompleted && deadline.isBefore(DateTime.now());

  /// Chuyển đổi đối tượng sang Map để lưu trữ trong SQLite.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subject_id': subjectId,
      'subject': subject,
      'deadline': deadline.toIso8601String(),
      'estimated_minutes': estimatedMinutes,
      'priority': priority.name,
      'status': status.name,
      'notes': notes,
    };
  }

  /// Khởi tạo đối tượng từ Map đọc ra từ SQLite hoặc Web preview.
  factory StudyTask.fromMap(Map<String, dynamic> map) {
    final subName = map['subject']?.toString() ?? 'Chung';
    final subId = map['subject_id']?.toString();

    return StudyTask(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      subjectId: (subId != null && subId.isNotEmpty)
          ? subId
          : _resolveSubjectIdFromName(subName),
      subject: subName,
      deadline:
          DateTime.tryParse(map['deadline']?.toString() ?? '') ??
          DateTime.now(),
      estimatedMinutes: (map['estimated_minutes'] as num?)?.toInt() ?? 0,
      priority: _parsePriority(map['priority']?.toString()),
      status: _parseStatus(map['status']?.toString()),
      notes: map['notes']?.toString() ?? '',
    );
  }

  /// Hàm phụ trợ ánh xạ tên môn sang subjectId mặc định đối với dữ liệu cũ.
  static String _resolveSubjectIdFromName(String name) {
    switch (name.trim()) {
      case 'Toán cao cấp':
        return 'subj_1';
      case 'Lập trình Web':
        return 'subj_2';
      case 'Cơ sở dữ liệu':
        return 'subj_3';
      case 'Tiếng Anh':
        return 'subj_4';
      default:
        return 'subj_${name.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
    }
  }

  static TaskPriority _parsePriority(String? val) {
    if (val == null) return TaskPriority.medium;
    final clean = val.contains('.') ? val.split('.').last.trim() : val.trim();
    return TaskPriority.values.firstWhere(
      (p) => p.name.toLowerCase() == clean.toLowerCase(),
      orElse: () => TaskPriority.medium,
    );
  }

  static TaskStatus _parseStatus(String? val) {
    if (val == null) return TaskStatus.todo;
    final clean = val.contains('.') ? val.split('.').last.trim() : val.trim();
    return TaskStatus.values.firstWhere(
      (s) => s.name.toLowerCase() == clean.toLowerCase(),
      orElse: () => TaskStatus.todo,
    );
  }

  /// Tạo bản sao có cập nhật trường dữ liệu.
  StudyTask copyWith({
    String? id,
    String? title,
    String? subjectId,
    String? subject,
    DateTime? deadline,
    int? estimatedMinutes,
    TaskPriority? priority,
    TaskStatus? status,
    String? notes,
  }) {
    return StudyTask(
      id: id ?? this.id,
      title: title ?? this.title,
      subjectId: subjectId ?? this.subjectId,
      subject: subject ?? this.subject,
      deadline: deadline ?? this.deadline,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }
}
