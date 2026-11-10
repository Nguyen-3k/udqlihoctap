/// Đại diện cho một sự kiện hoạt động học tập được ghi nhận khi hoàn thành nhiệm vụ.
class StudyActivity {
  final String id;
  final String dateKey; // YYYY-MM-DD theo giờ địa phương
  final String taskId;
  final DateTime completedAt;
  final int actualMinutes;
  final String? subjectId;

  const StudyActivity({
    required this.id,
    required this.dateKey,
    required this.taskId,
    required this.completedAt,
    this.actualMinutes = 0,
    this.subjectId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'activity_date': dateKey,
      'task_id': taskId,
      'completed_at': completedAt.toIso8601String(),
      'actual_minutes': actualMinutes,
      'subject_id': subjectId,
    };
  }

  factory StudyActivity.fromMap(Map<String, dynamic> map) {
    return StudyActivity(
      id: map['id']?.toString() ?? '',
      dateKey: map['activity_date']?.toString() ?? '',
      taskId: map['task_id']?.toString() ?? '',
      completedAt:
          DateTime.tryParse(map['completed_at']?.toString() ?? '') ??
          DateTime.now(),
      actualMinutes: (map['actual_minutes'] as num?)?.toInt() ?? 0,
      subjectId: map['subject_id']?.toString(),
    );
  }
}
