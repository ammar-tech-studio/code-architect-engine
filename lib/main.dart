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
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  @override
  void dispose() {
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
      ]);
      if (!mounted) return;
      setState(() {
        _skills = results[0] as List<SkillSummary>;
        _queue = results[1] as List<QueueItem>;
        _runs = results[2] as List<WorkflowRunSummary>;
        _prs = results[3] as List<PullRequestSummary>;
        _telemetry = results[4] as CloudTelemetry?;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    setState(() {
      _api.owner = _ownerController.text.trim();
      _api.repo = _repoController.text.trim();
      _api.token = _tokenController.text.trim();
    });
    _showSnack('تم حفظ الإعدادات للجلسة الحالية.');
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                Text(
                  'ما يتعلمه الآن',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if (activeRuns.isEmpty && activeQueue.isEmpty) ...[
                  Text(
                    nextPending.isNotEmpty
                        ? 'لا توجد دورة نشطة حالياً — التالي في الطابور: ${nextPending.first.slug}'
                        : 'لا توجد دورة تعلم نشطة حالياً.',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _loading ? null : _triggerLearn,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('تشغيل التعلم الآن'),
                  ),
                ],
                ...activeRuns.map(
                  (r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.autorenew),
                    title: Text(r.name),
                    subtitle: Text('${r.status} • ${r.createdAt}'),
                  ),
                ),
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
        Text('ما تم تعلمه — المهارات المتقنة (${filteredSkills.length}/${_skills.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'ابحث في المهارات المتعلمة أو التصنيفات...',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
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
        Text('الموجود في طابور التعلم (${_queue.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._queue.map(
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
