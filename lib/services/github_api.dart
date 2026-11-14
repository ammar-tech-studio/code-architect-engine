import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class SkillSummary {
  final String title;
  final String slug;
  final String category;
  final String updatedAt;

  const SkillSummary({
    required this.title,
    required this.slug,
    required this.category,
    required this.updatedAt,
  });
}

class QueueItem {
  final String slug;
  final String topic;
  final String category;
  final String status;
  final int priority;
  final int depth;

  const QueueItem({
    required this.slug,
    required this.topic,
    required this.category,
    required this.status,
    required this.priority,
    required this.depth,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      slug: json['slug']?.toString() ?? '',
      topic: json['topic']?.toString() ?? '',
      category: json['category']?.toString() ?? 'general',
      status: json['status']?.toString() ?? 'pending',
      priority: (json['priority'] as num?)?.toInt() ?? 99,
      depth: (json['depth'] as num?)?.toInt() ?? 0,
    );
  }
}

class WorkflowStepStatus {
  final String name;
  final String status;
  final String conclusion;

  const WorkflowStepStatus({
    required this.name,
    required this.status,
    required this.conclusion,
  });
}

class WorkflowRunSummary {
  final int id;
  final String name;
  final String status;
  final String conclusion;
  final String createdAt;
  final String htmlUrl;
  final String? currentStep;
  final List<WorkflowStepStatus> steps;

  const WorkflowRunSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.conclusion,
    required this.createdAt,
    required this.htmlUrl,
    this.currentStep,
    this.steps = const [],
  });

  WorkflowRunSummary copyWith({
    String? currentStep,
    List<WorkflowStepStatus>? steps,
  }) {
    return WorkflowRunSummary(
      id: id,
      name: name,
      status: status,
      conclusion: conclusion,
      createdAt: createdAt,
      htmlUrl: htmlUrl,
      currentStep: currentStep ?? this.currentStep,
      steps: steps ?? this.steps,
    );
  }
}

class BrainStorageInfo {
  final int brainDbBytes;
  final String? downloadUrl;
  final bool exists;

  const BrainStorageInfo({
    required this.brainDbBytes,
    this.downloadUrl,
    required this.exists,
  });

  String get formattedSize {
    if (!exists || brainDbBytes <= 0) return '0 B (لم تُنشأ بعد)';
    if (brainDbBytes < 1024) return '$brainDbBytes B';
    if (brainDbBytes < 1024 * 1024) {
      return '${(brainDbBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(brainDbBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class RepoEntry {
  final String name;
  final String path;
  final String type; // 'file' or 'dir'
  final int size;
  final String? downloadUrl;

  const RepoEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    this.downloadUrl,
  });

  factory RepoEntry.fromJson(Map<String, dynamic> json) {
    return RepoEntry(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      type: json['type']?.toString() ?? 'file',
      size: (json['size'] as num?)?.toInt() ?? 0,
      downloadUrl: json['download_url']?.toString(),
    );
  }
}

class PullRequestSummary {
  final int number;
  final String title;
  final String state;
  final String createdAt;

  const PullRequestSummary({
    required this.number,
    required this.title,
    required this.state,
    required this.createdAt,
  });
}

class CloudTelemetry {
  final String updatedAt;
  final int totalSkills;
  final int totalErrorFixes;

  const CloudTelemetry({
    required this.updatedAt,
    required this.totalSkills,
    required this.totalErrorFixes,
  });

  factory CloudTelemetry.fromJson(Map<String, dynamic> json) {
    return CloudTelemetry(
      updatedAt: json['updated_at']?.toString() ?? '',
      totalSkills: (json['total_skills'] as num?)?.toInt() ?? 0,
      totalErrorFixes: (json['total_error_fixes'] as num?)?.toInt() ?? 0,
    );
  }
}

class GitHubApiClient {
  GitHubApiClient({
    this.owner = 'ammar-tech-studio',
    this.repo = 'code-architect-engine',
    this.token = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  String owner;
  String repo;
  String token;
  final http.Client _client;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    return headers;
  }

  Uri _repoUri(String path, [Map<String, String>? query]) {
    return Uri.https('api.github.com', '/repos/$owner/$repo/$path', query);
  }

  Future<String> _fetchFileText(String path) async {
    if (token.trim().isEmpty) {
      final rawUri = Uri.https('raw.githubusercontent.com', '/$owner/$repo/main/$path');
      final rawResp = await _client.get(rawUri);
      if (rawResp.statusCode == 200) {
        return rawResp.body;
      }
    }
    final resp = await _client.get(_repoUri('contents/$path'), headers: _headers);
    if (resp.statusCode == 403) {
      throw Exception(
        'تم تجاوز حد طلبات GitHub API (403). أدخل GitHub PAT في تبويب الإعدادات لرفع الحد إلى 5000 طلب/ساعة.',
      );
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode} while reading $path');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawBase64 = (data['content'] as String? ?? '').replaceAll('\n', '');
    return utf8.decode(base64Decode(rawBase64));
  }

  Future<List<QueueItem>> fetchLearningQueue() async {
    final text = await _fetchFileText('learning_queue.json');
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final items = decoded['items'] as List<dynamic>? ?? [];
    return items.map((e) => QueueItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<SkillSummary>> fetchSkillsIndex() async {
    final md = await _fetchFileText('memory/skills/_index.md');
    final rowRegex = RegExp(r'\|\s*\[([^\]]+)\]\(\./([^/]+)/SKILL\.md\)\s*\|\s*`([^`]+)`\s*\|\s*([^|]+)\|');
    return rowRegex
        .allMatches(md)
        .map(
          (m) => SkillSummary(
            title: m.group(1)!.trim(),
            slug: m.group(2)!.trim(),
            category: m.group(3)!.trim(),
            updatedAt: m.group(4)!.trim(),
          ),
        )
        .toList();
  }

  Future<String> fetchSkillMarkdown(String slug) {
    return _fetchFileText('memory/skills/$slug/SKILL.md');
  }

  Future<String> fetchFileTextByPath(String path) {
    return _fetchFileText(path);
  }

  Future<BrainStorageInfo> fetchBrainStorageInfo() async {
    try {
      final resp = await _client.get(_repoUri('contents/memory'), headers: _headers);
      if (resp.statusCode != 200) {
        return const BrainStorageInfo(brainDbBytes: 0, exists: false);
      }
      final list = jsonDecode(resp.body) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        if (map['name'] == 'brain.db') {
          return BrainStorageInfo(
            brainDbBytes: (map['size'] as num?)?.toInt() ?? 0,
            downloadUrl: map['download_url']?.toString(),
            exists: true,
          );
        }
      }
      return const BrainStorageInfo(brainDbBytes: 0, exists: false);
    } catch (_) {
      return const BrainStorageInfo(brainDbBytes: 0, exists: false);
    }
  }

  Future<Uint8List> downloadFileBytes(String path, {String? directUrl}) async {
    if (directUrl != null && directUrl.isNotEmpty && token.trim().isEmpty) {
      final resp = await _client.get(Uri.parse(directUrl));
      if (resp.statusCode == 200) return resp.bodyBytes;
    }
    final resp = await _client.get(
      _repoUri('contents/$path'),
      headers: {
        ..._headers,
        'Accept': 'application/vnd.github.raw+json',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل تنزيل الملف (${resp.statusCode})');
    }
    return resp.bodyBytes;
  }

  Future<List<RepoEntry>> fetchDirectoryEntries(String path) async {
    try {
      final cleanPath = path.replaceAll(RegExp(r'^/+|/+$'), '');
      final resp = await _client.get(_repoUri('contents/$cleanPath'), headers: _headers);
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List<dynamic>) return [];
      final entries = decoded.map((e) => RepoEntry.fromJson(e as Map<String, dynamic>)).toList();
      entries.sort((a, b) {
        if (a.type != b.type) return a.type == 'dir' ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<({String? currentStep, List<WorkflowStepStatus> steps})> fetchActiveRunSteps(int runId) async {
    try {
      final resp = await _client.get(_repoUri('actions/runs/$runId/jobs'), headers: _headers);
      if (resp.statusCode != 200) return (currentStep: null, steps: const <WorkflowStepStatus>[]);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final jobs = data['jobs'] as List<dynamic>? ?? [];
      final allSteps = <WorkflowStepStatus>[];
      String? activeName;
      for (final j in jobs) {
        final job = j as Map<String, dynamic>;
        final steps = job['steps'] as List<dynamic>? ?? [];
        for (final s in steps) {
          final step = s as Map<String, dynamic>;
          final name = step['name']?.toString() ?? '';
          final status = step['status']?.toString() ?? '';
          final conclusion = step['conclusion']?.toString() ?? '';
          allSteps.add(WorkflowStepStatus(name: name, status: status, conclusion: conclusion));
          if (status == 'in_progress') {
            activeName = name;
          }
        }
        if (activeName == null && job['status'] == 'in_progress') {
          activeName = job['name']?.toString();
        }
      }
      return (currentStep: activeName, steps: allSteps);
    } catch (_) {
      return (currentStep: null, steps: const <WorkflowStepStatus>[]);
    }
  }

  Future<String> fetchRunFailureLogs(int runId) async {
    final jobsResp = await _client.get(_repoUri('actions/runs/$runId/jobs'), headers: _headers);
    if (jobsResp.statusCode != 200) {
      throw Exception('تعذر جلب تفاصيل الوظائف (${jobsResp.statusCode}). تأكد من إدخال GitHub PAT في الإعدادات.');
    }
    final data = jsonDecode(jobsResp.body) as Map<String, dynamic>;
    final jobs = data['jobs'] as List<dynamic>? ?? [];
    if (jobs.isEmpty) {
      return 'لا توجد تفاصيل وظائف مسجلة لهذا التشغيل.';
    }

    final buffer = StringBuffer();
    for (final j in jobs) {
      final job = j as Map<String, dynamic>;
      final jobId = (job['id'] as num?)?.toInt();
      final jobName = job['name']?.toString() ?? 'Job';
      final jobConclusion = job['conclusion']?.toString() ?? job['status']?.toString() ?? '';

      buffer.writeln('=== Job: $jobName [$jobConclusion] ===');
      final steps = job['steps'] as List<dynamic>? ?? [];
      for (final s in steps) {
        final step = s as Map<String, dynamic>;
        final conclusion = step['conclusion']?.toString() ?? step['status']?.toString() ?? '';
        if (conclusion == 'failure' || conclusion == 'cancelled' || conclusion == 'timed_out') {
          buffer.writeln('✖ Step failed: ${step['name']} ($conclusion)');
        }
      }

      if (jobId != null) {
        try {
          final logResp = await _client.get(_repoUri('actions/jobs/$jobId/logs'), headers: _headers);
          if (logResp.statusCode == 200 && logResp.body.isNotEmpty) {
            final lines = logResp.body.split('\n');
            final tail = lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
            buffer.writeln('\n--- آخر 100 سطر من الكنسول ---');
            buffer.writeln(tail.join('\n'));
          } else if (logResp.statusCode == 401 || logResp.statusCode == 403) {
            buffer.writeln('\n[ملاحظة]: لقراءة نص سجل الكنسول الكامل من GitHub، يرجى إدخال GitHub PAT (بصلاحية repo + workflow) في تبويب الإعدادات.');
          } else {
            buffer.writeln('\n[ملاحظة]: تعذر تحميل سجل الكنسول (HTTP ${logResp.statusCode}).');
          }
        } catch (e) {
          buffer.writeln('\n[خطأ أثناء جلب السجل]: $e');
        }
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  Future<List<WorkflowRunSummary>> fetchWorkflowRuns() async {
    final resp = await _client.get(_repoUri('actions/runs', {'per_page': '10'}), headers: _headers);
    if (resp.statusCode == 403) {
      throw Exception(
        'تم تجاوز حد طلبات GitHub API (60 طلب/ساعة بدون توكن). أدخل GitHub PAT في تبويب الإعدادات.',
      );
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode} while reading workflow runs');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final runs = data['workflow_runs'] as List<dynamic>? ?? [];
    final summaries = runs.map((r) {
      final map = r as Map<String, dynamic>;
      return WorkflowRunSummary(
        id: (map['id'] as num?)?.toInt() ?? 0,
        name: map['name']?.toString() ?? 'Workflow',
        status: map['status']?.toString() ?? '',
        conclusion: map['conclusion']?.toString() ?? 'running',
        createdAt: (map['created_at']?.toString() ?? '').split('T').first,
        htmlUrl: map['html_url']?.toString() ?? '',
      );
    }).toList();

    for (var i = 0; i < summaries.length; i++) {
      if (summaries[i].status != 'completed' && summaries[i].id > 0) {
        final info = await fetchActiveRunSteps(summaries[i].id);
        summaries[i] = summaries[i].copyWith(
          currentStep: info.currentStep,
          steps: info.steps,
        );
      }
    }
    return summaries;
  }

  Future<List<PullRequestSummary>> fetchPullRequests() async {
    final resp = await _client.get(_repoUri('pulls', {'state': 'all', 'per_page': '10'}), headers: _headers);
    if (resp.statusCode == 403) {
      throw Exception(
        'تم تجاوز حد طلبات GitHub API (60 طلب/ساعة بدون توكن). أدخل GitHub PAT في تبويب الإعدادات.',
      );
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode} while reading pull requests');
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((p) {
      final map = p as Map<String, dynamic>;
      return PullRequestSummary(
        number: (map['number'] as num?)?.toInt() ?? 0,
        title: map['title']?.toString() ?? '',
        state: map['state']?.toString() ?? 'open',
        createdAt: (map['created_at']?.toString() ?? '').split('T').first,
      );
    }).toList();
  }

  Future<int> createBuildIssue({required String title, required String body}) async {
    if (token.trim().isEmpty) {
      throw Exception('يرجى إدخال GitHub Token في تبويب الإعدادات أولاً.');
    }
    final resp = await _client.post(
      _repoUri('issues'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'body': body,
        'labels': ['agent-build'],
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception('فشل إنشاء المهمة (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['number'] as num).toInt();
  }

  Future<void> triggerSelfLearn() async {
    if (token.trim().isEmpty) {
      throw Exception('يرجى إدخال GitHub Token في تبويب الإعدادات أولاً.');
    }
    final resp = await _client.post(
      _repoUri('actions/workflows/self_learn.yml/dispatches'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'ref': 'main'}),
    );
    if (resp.statusCode != 204) {
      throw Exception('فشل تشغيل دورة التعلم (${resp.statusCode}): ${resp.body}');
    }
  }

  Future<CloudTelemetry?> fetchTelemetry() async {
    try {
      final text = await _fetchFileText('memory/telemetry.json');
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      return CloudTelemetry.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> addTopicToQueue({
    required String slug,
    required String topic,
    required String category,
    int priority = 2,
  }) async {
    if (token.trim().isEmpty) {
      throw Exception('يرجى إدخال GitHub Token في تبويب الإعدادات أولاً.');
    }
    final getResp = await _client.get(_repoUri('contents/learning_queue.json'), headers: _headers);
    if (getResp.statusCode != 200) {
      throw Exception('تعذر قراءة learning_queue.json (${getResp.statusCode})');
    }
    final fileMeta = jsonDecode(getResp.body) as Map<String, dynamic>;
    final sha = fileMeta['sha'] as String;
    final rawBase64 = (fileMeta['content'] as String? ?? '').replaceAll('\n', '');
    final queueJson = jsonDecode(utf8.decode(base64Decode(rawBase64))) as Map<String, dynamic>;
    final items = (queueJson['items'] as List<dynamic>? ?? []);

    final cleanSlug = slug
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (items.any((e) => (e as Map<String, dynamic>)['slug'] == cleanSlug)) {
      throw Exception('هذا الموضوع موجود بالفعل في طابور التعلم.');
    }

    items.add({
      'slug': cleanSlug.isEmpty ? 'custom-topic-${ items.length + 1}' : cleanSlug,
      'topic': topic.trim(),
      'category': category.trim().isEmpty ? 'architecture' : category.trim(),
      'priority': priority,
      'depth': 0,
      'attempts': 0,
      'status': 'pending',
      'parent_slug': null,
    });
    queueJson['items'] = items;

    final updatedText = '${const JsonEncoder.withIndent('  ').convert(queueJson)}\n';
    final putResp = await _client.put(
      _repoUri('contents/learning_queue.json'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': 'chore(queue): add learning topic $cleanSlug from dashboard',
        'content': base64Encode(utf8.encode(updatedText)),
        'sha': sha,
      }),
    );
    if (putResp.statusCode != 200 && putResp.statusCode != 201) {
      throw Exception('فشل تحديث طابور التعلم (${putResp.statusCode}): ${putResp.body}');
    }
  }
}
