import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/github_api.dart';

void main() {
  runApp(const CodeArchitectApp());
}

class CodeArchitectApp extends StatelessWidget {
  const CodeArchitectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Code Architect Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DashboardShell(),
      ),
    );
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  final GitHubApiClient _api = GitHubApiClient();
  int _tabIndex = 0;

  bool _loading = false;
  String? _error;
  List<SkillSummary> _skills = [];
  List<QueueItem> _queue = [];
  List<WorkflowRunSummary> _runs = [];
  List<PullRequestSummary> _prs = [];
  CloudTelemetry? _telemetry;
  BrainStorageInfo _brainStorage = const BrainStorageInfo(brainDbBytes: 0, exists: false);
  List<RepoEntry> _repoEntries = [];
  String _browsePath = 'workspace_outputs';
  bool _autoRefresh = false;
  Timer? _autoRefreshTimer;
  bool _downloadingBrain = false;
  String _searchQuery = '';

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _slugController = TextEditingController();
  final _topicController = TextEditingController();
  final _categoryController = TextEditingController(text: 'python-architecture');
  late final TextEditingController _ownerController;
  late final TextEditingController _repoController;
  final _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ownerController = TextEditingController(text: _api.owner);
    _repoController = TextEditingController(text: _api.repo);
    _loadSavedSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  File? _settingsFile() {
    if (kIsWeb) return null;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return File('$home${Platform.pathSeparator}.cae_dashboard_settings.json');
  }

  void _loadSavedSettings() {
    try {
      final file = _settingsFile();
      if (file == null || !file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final savedOwner = data['owner']?.toString().trim() ?? '';
      final savedRepo = data['repo']?.toString().trim() ?? '';
      final savedToken = data['token']?.toString().trim() ?? '';
      if (savedOwner.isNotEmpty) {
        _api.owner = savedOwner;
        _ownerController.text = savedOwner;
      }
      if (savedRepo.isNotEmpty) {
        _api.repo = savedRepo;
        _repoController.text = savedRepo;
      }
      if (savedToken.isNotEmpty) {
        _api.token = savedToken;
        _tokenController.text = savedToken;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    _slugController.dispose();
    _topicController.dispose();
    _categoryController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchSkillsIndex(),
        _api.fetchLearningQueue(),
        _api.fetchWorkflowRuns(),
        _api.fetchPullRequests(),
        _api.fetchTelemetry(),
        _api.fetchBrainStorageInfo(),
        _api.fetchDirectoryEntries(_browsePath),
      ]);
      if (!mounted) return;
      setState(() {
        _skills = results[0] as List<SkillSummary>;
        _queue = results[1] as List<QueueItem>;
        _runs = results[2] as List<WorkflowRunSummary>;
        _prs = results[3] as List<PullRequestSummary>;
        _telemetry = results[4] as CloudTelemetry?;
        _brainStorage = results[5] as BrainStorageInfo;
        _repoEntries = results[6] as List<RepoEntry>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleAutoRefresh(bool enabled) {
    _autoRefreshTimer?.cancel();
    setState(() => _autoRefresh = enabled);
    if (enabled) {
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_loading && mounted) {
          _refreshAll();
        }
      });
    }
  }

  Future<void> _downloadBrainDb() async {
    if (!_brainStorage.exists) {
      _showSnack('ملف brain.db غير موجود بعد في السحابة. شغّل دورة التعلم أولاً.');
      return;
    }
    if (kIsWeb) {
      _showSnack('التنزيل المباشر للملفات مدعوم على نسخة سطح المكتب (Windows).');
      return;
    }
    setState(() => _downloadingBrain = true);
    try {
      final bytes = await _api.downloadFileBytes(
        'memory/brain.db',
        directUrl: _brainStorage.downloadUrl,
      );
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
      final downloadsDir = Directory('$home${Platform.pathSeparator}Downloads');
      final targetDir = downloadsDir.existsSync() ? downloadsDir : Directory.current;
      final outFile = File('${targetDir.path}${Platform.pathSeparator}brain.db');
      await outFile.writeAsBytes(bytes, flush: true);
      _showSnack('تم تنزيل الذاكرة (${_brainStorage.formattedSize}) إلى: ${outFile.path}');
    } catch (e) {
      _showSnack('تعذر تنزيل brain.db: $e');
    } finally {
      if (mounted) setState(() => _downloadingBrain = false);
    }
  }

  Future<void> _browseDirectory(String path) async {
    setState(() {
      _browsePath = path;
      _loading = true;
    });
    try {
      final entries = await _api.fetchDirectoryEntries(path);
      if (!mounted) return;
      setState(() => _repoEntries = entries);
    } catch (e) {
      _showSnack('تعذر فتح المجلد: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRunLogsDialog(WorkflowRunSummary run) async {
    if (run.id <= 0) {
      _showSnack('معرّف التشغيل غير متوفر.');
      return;
    }
    setState(() => _loading = true);
    try {
      final logs = await _api.fetchRunFailureLogs(run.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('سجل الكنسول: ${run.name} (${run.conclusion})'),
          content: Container(
            width: 720,
            height: 440,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111318),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logs,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: logs));
                _showSnack('تم نسخ سجل الكنسول.');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('نسخ السجل'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack('تعذر جلب سجل الكنسول: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRepoFileDialog(RepoEntry entry) async {
    try {
      final content = await _api.fetchFileTextByPath(entry.path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(entry.name),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                _showSnack('تم نسخ محتوى الملف.');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('نسخ'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack('تعذر قراءة الملف: $e');
    }
  }

  Future<void> _openSkillDialog(SkillSummary skill) async {
    try {
      final md = await _api.fetchSkillMarkdown(skill.slug);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(skill.title),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(
                md,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: md));
                _showSnack('تم نسخ محتوى المهارة إلى الحافظة.');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('نسخ الكود والشرح'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack('تعذر قراءة المهارة: $e');
    }
  }

  Future<void> _addQueueTopic() async {
    final slug = _slugController.text.trim();
    final topic = _topicController.text.trim();
    final category = _categoryController.text.trim();
    if (slug.isEmpty || topic.isEmpty) {
      _showSnack('أدخل المعرّف (Slug) ووصف الموضوع أولاً.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _api.addTopicToQueue(slug: slug, topic: topic, category: category);
      _slugController.clear();
      _topicController.clear();
      _showSnack('تمت إضافة الموضوع لطابور التعلم السحابي بنجاح.');
      await _refreshAll();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitTask() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      _showSnack('اكتب عنوان المهمة أولاً.');
      return;
    }
    setState(() => _loading = true);
    try {
      final issueNum = await _api.createBuildIssue(title: title, body: body);
      _titleController.clear();
      _bodyController.clear();
      _showSnack('تم إرسال المهمة بنجاح (Issue #$issueNum).');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerLearn() async {
    setState(() => _loading = true);
    try {
      await _api.triggerSelfLearn();
      _showSnack('تم تشغيل نبضة التعلم الذاتي على السحابة.');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _saveSettings() {
    final owner = _ownerController.text.trim();
    final repo = _repoController.text.trim();
    final token = _tokenController.text.trim();
    setState(() {
      _api.owner = owner;
      _api.repo = repo;
      _api.token = token;
    });
    try {
      final file = _settingsFile();
      if (file != null) {
        file.writeAsStringSync(
          jsonEncode({'owner': owner, 'repo': repo, 'token': token}),
          flush: true,
        );
      }
    } catch (_) {}
    _showSnack('تم حفظ الإعدادات وتحديث البيانات.');
    _refreshAll();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Code Architect Engine'),
        actions: [
          IconButton(
            tooltip: 'تحديث من GitHub',
            onPressed: _loading ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('إخفاء'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                _buildMemoryTab(),
                _buildDispatchTab(),
                _buildCloudTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.psychology_outlined), label: 'الذاكرة'),
          NavigationDestination(icon: Icon(Icons.add_task), label: 'تكليف'),
          NavigationDestination(icon: Icon(Icons.cloud_done_outlined), label: 'السحابة'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
        ],
      ),
    );
  }

  Widget _buildMemoryTab() {
    if (_skills.isEmpty && _queue.isEmpty && _runs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.memory, size: 48),
            const SizedBox(height: 12),
            const Text('اضغط زر التحديث لجلب المهارات والطابور من GitHub.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _refreshAll,
              icon: const Icon(Icons.download),
              label: const Text('جلب البيانات الآن'),
            ),
          ],
        ),
      );
    }

    final activeRuns = _runs.where((r) => r.status != 'completed').toList();
    final activeQueue = _queue
        .where((q) => q.status == 'in_progress' || q.status == 'learning' || q.status == 'running')
        .toList();
    final nextPending = _queue.where((q) => q.status == 'pending').toList();

    final filteredSkills = _skills.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.title.toLowerCase().contains(q) ||
          s.slug.toLowerCase().contains(q) ||
          s.category.toLowerCase().contains(q);
    }).toList();

    final filteredQueue = _queue.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return item.slug.toLowerCase().contains(q) ||
          item.topic.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q);
    }).toList();

    final filteredEntries = _repoEntries.where((e) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return e.name.toLowerCase().contains(q) || e.path.toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const CircleAvatar(
                  child: Icon(Icons.storage_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حجم ذاكرة النموذج السحابية (brain.db)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الحجم الحالي: ${_brainStorage.formattedSize} • المهارات: ${_telemetry?.totalSkills ?? _skills.length}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_telemetry != null && _telemetry!.updatedAt.isNotEmpty)
                        Text(
                          'آخر تحديث سحابي: ${_telemetry!.updatedAt.split("T").first}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _downloadingBrain ? null : _downloadBrainDb,
                  icon: _downloadingBrain
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: const Text('تنزيل'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_telemetry != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.psychology, size: 18),
                  label: Text('المهارات المتقنة: ${_telemetry!.totalSkills}'),
                ),
                Chip(
                  avatar: const Icon(Icons.healing, size: 18),
                  label: Text('أنماط الأخطاء المعالجة: ${_telemetry!.totalErrorFixes}'),
                ),
                Chip(
                  avatar: const Icon(Icons.pending_actions, size: 18),
                  label: Text('في الطابور: ${nextPending.length}'),
                ),
              ],
            ),
          ),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ما يقوم به حالياً (البث السحابي)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('تحديث تلقائي', style: TextStyle(fontSize: 12)),
                        Switch(
                          value: _autoRefresh,
                          onChanged: _toggleAutoRefresh,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (activeRuns.isEmpty && activeQueue.isEmpty) ...[
                  Text(
                    nextPending.isNotEmpty
                        ? 'الوكيل السحابي في وضع الاستعداد — المهمة التالية: ${nextPending.first.slug}'
                        : 'الوكيل السحابي في وضع الاستعداد ولا توجد مهام معلقة.',
                  ),
                  if (_runs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'آخر تنفيذ: ${_runs.first.name} (${_runs.first.conclusion}) • ${_runs.first.createdAt}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _loading ? null : _triggerLearn,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('تشغيل التعلم الآن'),
                      ),
                      if (_runs.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _loading ? null : () => _openRunLogsDialog(_runs.first),
                          icon: const Icon(Icons.terminal),
                          label: Text(
                            _runs.first.conclusion == 'failure'
                                ? 'عرض سبب الفشل (الكنسول)'
                                : 'عرض سجل الكنسول',
                          ),
                        ),
                    ],
                  ),
                ],
                ...activeRuns.map(
                  (r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.autorenew),
                        title: Text('${r.name} (${r.status})'),
                        subtitle: Text(
                          r.currentStep != null
                              ? 'الخطوة الحالية: ${r.currentStep}'
                              : 'قيد التنفيذ على GitHub Actions • ${r.createdAt}',
                        ),
                        trailing: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _openRunLogsDialog(r),
                          icon: const Icon(Icons.terminal, size: 16),
                          label: const Text('الكنسول'),
                        ),
                      ),
                      if (r.steps.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: r.steps.map((step) {
                              final isRunning = step.status == 'in_progress';
                              final isDone = step.status == 'completed';
                              final isFailed = step.conclusion == 'failure';
                              final icon = isRunning
                                  ? Icons.sync
                                  : isFailed
                                      ? Icons.cancel
                                      : isDone
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked;
                              final color = isRunning
                                  ? Colors.blue
                                  : isFailed
                                      ? Colors.red
                                      : isDone
                                          ? Colors.green
                                          : Colors.grey;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Icon(icon, size: 15, color: color),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        step.name,
                                        textDirection: TextDirection.ltr,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isRunning ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                if (activeRuns.isNotEmpty && nextPending.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'الموضوع الجاري معالجته غالباً: ${nextPending.first.slug} — ${nextPending.first.topic}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (activeRuns.isNotEmpty &&
                    _runs.any((r) => r.status == 'completed')) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final lastCompleted =
                          _runs.firstWhere((r) => r.status == 'completed');
                      return OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _openRunLogsDialog(lastCompleted),
                        icon: const Icon(Icons.terminal, size: 18),
                        label: Text(
                          'عرض سجل آخر تنفيذ (${lastCompleted.conclusion})',
                        ),
                      );
                    },
                  ),
                ],
                ...activeQueue.map(
                  (q) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.school),
                    title: Text(q.slug),
                    subtitle: Text(q.topic, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث في المهارات، الطابور، والملفات المحفوظة...',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('ما تم تعلمه — المهارات المتقنة (${filteredSkills.length}/${_skills.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (filteredSkills.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('لا توجد مهارات محفوظة مطابقة بعد'),
              subtitle: Text('اضغط "تشغيل التعلم الآن" ليتعلم الوكيل أول مهارة ويحفظها هنا.'),
            ),
          ),
        ...filteredSkills.map(
          (s) => Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(s.title),
              subtitle: Text('${s.category} • ${s.updatedAt}'),
              onTap: () => _openSkillDialog(s),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'تصفح الملفات المحفوظة ($_browsePath)',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => _browseDirectory('workspace_outputs'),
              child: const Text('المخرجات'),
            ),
            TextButton(
              onPressed: () => _browseDirectory('memory'),
              child: const Text('الذاكرة'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (filteredEntries.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('هذا المجلد فارغ حالياً'),
            ),
          ),
        ...filteredEntries.map(
          (entry) => Card(
            child: ListTile(
              leading: Icon(entry.type == 'dir' ? Icons.folder : Icons.description_outlined),
              title: Text(entry.name),
              subtitle: Text(
                entry.type == 'dir'
                    ? 'مجلد • اضغط للتصفح'
                    : '${(entry.size / 1024).toStringAsFixed(1)} KB',
              ),
              onTap: () {
                if (entry.type == 'dir') {
                  _browseDirectory(entry.path);
                } else {
                  _openRepoFileDialog(entry);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('الموجود في طابور التعلم (${filteredQueue.length}/${_queue.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...filteredQueue.map(
          (q) => Card(
            child: ListTile(
              leading: Icon(
                q.status == 'completed'
                    ? Icons.check_circle_outline
                    : q.status == 'blocked'
                        ? Icons.error_outline
                        : Icons.schedule,
              ),
              title: Text(q.slug),
              subtitle: Text(q.topic, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Chip(label: Text(q.status)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDispatchTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('إرسال مهمة برمجية (Issue -> PR)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'عنوان المهمة أو الميزة',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyController,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'التفاصيل والمواصفات المطلوبة',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _submitTask,
          icon: const Icon(Icons.send),
          label: const Text('إرسال للوكيل السحابي'),
        ),
        const Divider(height: 36),
        Text('إضافة موضوع جديد لطابور التعلم السحابي', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _slugController,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'المعرّف المختصر (مثال: python-pydantic-v2-validators)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _topicController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'وصف الموضوع الهندسي المراد تعلمه واختباره',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _categoryController,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'التصنيف (Category)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _loading ? null : _addQueueTopic,
          icon: const Icon(Icons.playlist_add),
          label: const Text('إضافة إلى learning_queue.json في السحابة'),
        ),
        const Divider(height: 36),
        Text('التحكم السحابي المباشر', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loading ? null : _triggerLearn,
          icon: const Icon(Icons.play_arrow),
          label: const Text('تشغيل نبضة التعلم الذاتي الآن'),
        ),
      ],
    );
  }

  Widget _buildCloudTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('آخر تشغيلات GitHub Actions (${_runs.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._runs.map(
          (r) => Card(
            child: ListTile(
              leading: Icon(
                r.conclusion == 'success'
                    ? Icons.check_circle
                    : r.conclusion == 'failure'
                        ? Icons.cancel
                        : Icons.hourglass_top,
              ),
              title: Text(r.name),
              subtitle: Text('${r.status} • ${r.conclusion} • ${r.createdAt}'),
              trailing: IconButton(
                tooltip: 'عرض سجل الكنسول',
                icon: const Icon(Icons.terminal),
                onPressed: _loading ? null : () => _openRunLogsDialog(r),
              ),
              onTap: _loading ? null : () => _openRunLogsDialog(r),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('طلبات الدمج (Pull Requests) (${_prs.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._prs.map(
          (p) => Card(
            child: ListTile(
              leading: const Icon(Icons.merge_type),
              title: Text('#${p.number} ${p.title}'),
              subtitle: Text('${p.state} • ${p.createdAt}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('إعدادات الاتصال بالمستودع', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _ownerController,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'GitHub Owner',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _repoController,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'Repository Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenController,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'GitHub PAT (للمستودع الخاص وإرسال المهام)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saveSettings,
          child: const Text('حفظ وجلب البيانات'),
        ),
      ],
    );
  }
}
