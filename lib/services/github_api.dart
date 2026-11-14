import 'dart:convert';
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

class WorkflowRunSummary {
  final String name;
  final String status;
  final String conclusion;
  final String createdAt;
  final String htmlUrl;

  const WorkflowRunSummary({
    required this.name,
    required this.status,
    required this.conclusion,
    required this.createdAt,
    required this.htmlUrl,
  });
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
    final resp = await _client.get(_repoUri('contents/$path'), headers: _headers);
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

  Future<List<WorkflowRunSummary>> fetchWorkflowRuns() async {
    final resp = await _client.get(_repoUri('actions/runs', {'per_page': '10'}), headers: _headers);
    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode} while reading workflow runs');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final runs = data['workflow_runs'] as List<dynamic>? ?? [];
    return runs.map((r) {
      final map = r as Map<String, dynamic>;
      return WorkflowRunSummary(
        name: map['name']?.toString() ?? 'Workflow',
        status: map['status']?.toString() ?? '',
        conclusion: map['conclusion']?.toString() ?? 'running',
        createdAt: (map['created_at']?.toString() ?? '').split('T').first,
        htmlUrl: map['html_url']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<PullRequestSummary>> fetchPullRequests() async {
    final resp = await _client.get(_repoUri('pulls', {'state': 'all', 'per_page': '10'}), headers: _headers);
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
