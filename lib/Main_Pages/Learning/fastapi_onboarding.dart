// ============================================================
//  OptionXi — fastapi_onboarding.dart
//
//  Standalone from the achievements system: its own base URL,
//  its own API key, its own backend router. FastAPI does the
//  gating and writes; this client just calls it and renders
//  the result. Add to .env:
//    ONBOARDING_API_BASE=https://your-backend.example.com
//    ONBOARDING_API_KEY=<matches the backend's ONBOARDING_API_KEY>
//  No new pubspec deps — reuses http, firebase_auth, flutter_dotenv
//  already in the project.
// ============================================================

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────
// CONFIG
// ─────────────────────────────────────────────────────────────

abstract class OnboardingConfig {
  static String get apiBase => dotenv.env['ONBOARDING_API_BASE']!;
  static String get apiKey => dotenv.env['ONBOARDING_API_KEY']!;
}

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────

class QuizQuestion {
  final String id;
  final String prompt;
  final List<String> options;

  const QuizQuestion(
      {required this.id, required this.prompt, required this.options});

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        id: j['id'] as String,
        prompt: j['prompt'] as String,
        options: List<String>.from(j['options'] as List),
      );
}

class OnboardingLesson {
  final String id;
  final String moduleKey;
  final String title;
  final int orderIndex;
  final bool isFree;
  final int xpReward;
  final bool locked;
  final bool completed;
  final bool requiresPremium;
  final int? quizScore;
  final String? actionRoute; // NEW — GetX route, e.g. '/screeners'
  final String? actionLabel; // NEW — button text, e.g. 'Try the Screener'

  const OnboardingLesson({
    required this.id,
    required this.moduleKey,
    required this.title,
    required this.orderIndex,
    required this.isFree,
    required this.xpReward,
    required this.locked,
    required this.completed,
    required this.requiresPremium,
    this.quizScore,
    this.actionRoute,
    this.actionLabel,
  });

  factory OnboardingLesson.fromJson(Map<String, dynamic> j) => OnboardingLesson(
        id: j['id'] as String,
        moduleKey: j['module_key'] as String,
        title: j['title'] as String,
        orderIndex: j['order_index'] as int,
        isFree: j['is_free'] as bool,
        xpReward: (j['xp_reward'] as int?) ?? 0,
        locked: j['locked'] as bool,
        completed: j['completed'] as bool,
        requiresPremium: j['requires_premium'] as bool,
        quizScore: j['quiz_score'] as int?,
        actionRoute: j['action_route'] as String?,
        actionLabel: j['action_label'] as String?,
      );
}

class OnboardingModule {
  final String key;
  final String title;
  final String? description;
  final int sortOrder;
  final List<OnboardingLesson> lessons;

  const OnboardingModule({
    required this.key,
    required this.title,
    required this.sortOrder,
    required this.lessons,
    this.description,
  });

  double get progress => lessons.isEmpty
      ? 0
      : lessons.where((l) => l.completed).length / lessons.length;

  factory OnboardingModule.fromJson(Map<String, dynamic> j) => OnboardingModule(
        key: j['key'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        sortOrder: (j['sort_order'] as int?) ?? 0,
        lessons: (j['lessons'] as List<dynamic>)
            .map((e) => OnboardingLesson.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Body text, quiz prompts, and an optional reference video for one lesson.
/// Kept as a named class (instead of a bare record) so every call site is
/// type-safe about field names rather than juggling positional tuple slots.
class LessonContent {
  final String body;
  final List<QuizQuestion> quiz;
  final String? videoUrl;

  const LessonContent({
    required this.body,
    required this.quiz,
    this.videoUrl,
  });

  factory LessonContent.fromJson(Map<String, dynamic> j) => LessonContent(
        body: j['body'] as String,
        quiz: (j['quiz'] as List<dynamic>)
            .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
        videoUrl: j['video_url'] as String?,
      );
}

/// Per-question grading detail, returned only after submission — the
/// correct answer is never shipped in [LessonContent], so there's nothing
/// client-side to cheat with before the quiz is actually submitted.
class QuestionResult {
  final String questionId;
  final bool correct;
  final int? correctIndex;
  final int selectedIndex;

  const QuestionResult({
    required this.questionId,
    required this.correct,
    required this.selectedIndex,
    this.correctIndex,
  });

  factory QuestionResult.fromJson(Map<String, dynamic> j) => QuestionResult(
        questionId: j['question_id'] as String,
        correct: j['correct'] as bool,
        selectedIndex: (j['selected_index'] as int?) ?? -1,
        correctIndex: j['correct_index'] as int?,
      );
}

class LessonResult {
  final bool passed;
  final int score;
  final int xpAwarded;
  final int attempts;
  final List<QuestionResult> breakdown;

  const LessonResult({
    required this.passed,
    required this.score,
    required this.xpAwarded,
    required this.attempts,
    this.breakdown = const [],
  });

  factory LessonResult.fromJson(Map<String, dynamic> j) => LessonResult(
        passed: j['passed'] as bool,
        score: j['score'] as int,
        xpAwarded: (j['xp_awarded'] as int?) ?? 0,
        attempts: (j['attempts'] as int?) ?? 1,
        // Older backend versions may not send this yet — default to empty
        // so the result screen just hides the breakdown instead of crashing.
        breakdown: (j['results'] as List<dynamic>?)
                ?.map((e) => QuestionResult.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class DailyQuest {
  final String id;
  final String title;
  final String description;
  final int xpReward;
  final bool completed;

  const DailyQuest({
    required this.id,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.completed,
  });

  factory DailyQuest.fromJson(Map<String, dynamic> j) => DailyQuest(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        xpReward: (j['xp_reward'] as int?) ?? 0,
        completed: j['status'] == 'completed',
      );
}

// ─────────────────────────────────────────────────────────────
// CLIENT
// ─────────────────────────────────────────────────────────────

class OnboardingClient {
  OnboardingClient._();

  static final _auth = FirebaseAuth.instance;

  static Future<String> _idToken() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    return await user.getIdToken() ??
        (throw Exception('Could not get ID token'));
  }

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'X-Api-Key': OnboardingConfig.apiKey,
        'Authorization': 'Bearer $token',
      };

  /// All modules + lessons, with lock/completion state computed server-side.
  static Future<(List<OnboardingModule>, bool isPremium)> fetchLessons() async {
    final token = await _idToken();
    final res = await http
        .get(Uri.parse('${OnboardingConfig.apiBase}/onboarding/lessons'),
            headers: _headers(token))
        .timeout(const Duration(seconds: 8));

    if (res.statusCode != 200) {
      throw Exception('Failed to load lessons (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final modules = (body['modules'] as List<dynamic>)
        .map((e) => OnboardingModule.fromJson(e as Map<String, dynamic>))
        .toList();
    return (modules, body['is_premium'] as bool);
  }

  /// Body text, quiz prompts, and optional reference video for one lesson
  /// (no correct answers included — grading always happens server-side in
  /// submitLesson).
  static Future<LessonContent> fetchLessonContent(String lessonId) async {
    final token = await _idToken();
    final res = await http
        .get(
          Uri.parse(
              '${OnboardingConfig.apiBase}/onboarding/lessons/$lessonId/content'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode == 402) {
      throw Exception('Premium required for this lesson');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load lesson (${res.statusCode})');
    }
    return LessonContent.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// answers: {question_id: selected_index}
  static Future<LessonResult> submitLesson(
    String lessonId,
    Map<String, int> answers,
  ) async {
    final token = await _idToken();
    final res = await http
        .post(
          Uri.parse(
              '${OnboardingConfig.apiBase}/onboarding/lessons/$lessonId/submit'),
          headers: _headers(token),
          body: jsonEncode({
            'answers': answers.entries
                .map((e) => {
                      'question_id': e.key,
                      'selected_index': e.value,
                    })
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode == 402) {
      throw Exception('Premium required for this lesson');
    }
    if (res.statusCode == 409) {
      throw Exception('Complete the previous lesson first');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to submit lesson (${res.statusCode})');
    }
    return LessonResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Today's quest set. `locked: true` means the user isn't premium —
  /// show an upgrade card instead of the quest list.
  static Future<(bool locked, List<DailyQuest> quests)>
      fetchTodayQuests() async {
    final token = await _idToken();
    final res = await http
        .get(Uri.parse('${OnboardingConfig.apiBase}/quests/today'),
            headers: _headers(token))
        .timeout(const Duration(seconds: 8));

    if (res.statusCode != 200) {
      throw Exception('Failed to load quests (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final quests = (body['quests'] as List<dynamic>)
        .map((e) => DailyQuest.fromJson(e as Map<String, dynamic>))
        .toList();
    return (body['locked'] as bool, quests);
  }

  static Future<int> completeQuest(String questId) async {
    final token = await _idToken();
    final res = await http
        .post(
          Uri.parse('${OnboardingConfig.apiBase}/quests/$questId/complete'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 8));

    if (res.statusCode == 402) throw Exception('Premium required');
    if (res.statusCode != 200) {
      throw Exception('Failed to complete quest (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['xp_awarded'] as int?) ?? 0;
  }
}
