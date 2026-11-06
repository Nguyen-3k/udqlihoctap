import 'package:flutter/material.dart';
import 'repositories/subject_repository.dart';
import 'repositories/task_repository.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamPilotApp());
}

class ExamPilotApp extends StatelessWidget {
  final TaskRepository? taskRepository;
  final SubjectRepository? subjectRepository;

  const ExamPilotApp({super.key, this.taskRepository, this.subjectRepository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ExamPilot',
      theme: AppTheme.lightTheme,
      home: AppShell(
        taskRepository: taskRepository,
        subjectRepository: subjectRepository,
      ),
    );
  }
}
