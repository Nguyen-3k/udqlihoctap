import 'package:flutter/material.dart';
import 'repositories/profile_repository.dart';
import 'repositories/subject_repository.dart';
import 'repositories/task_repository.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamPilotApp());
}

class ExamPilotApp extends StatefulWidget {
  final TaskRepository? taskRepository;
  final SubjectRepository? subjectRepository;
  final ProfileRepository? profileRepository;

  const ExamPilotApp({
    super.key,
    this.taskRepository,
    this.subjectRepository,
    this.profileRepository,
  });

  @override
  State<ExamPilotApp> createState() => _ExamPilotAppState();
}

class _ExamPilotAppState extends State<ExamPilotApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _handleThemeModeChanged(ThemeMode mode) {
    if (_themeMode != mode) {
      setState(() {
        _themeMode = mode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ExamPilot',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: AppShell(
        taskRepository: widget.taskRepository,
        subjectRepository: widget.subjectRepository,
        profileRepository: widget.profileRepository,
        onThemeModeChanged: _handleThemeModeChanged,
      ),
    );
  }
}
