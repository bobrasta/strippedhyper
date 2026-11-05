import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/hr_report_service.dart';
import '../../services/position_service.dart';
import '../../services/recruitment_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../theme/hr_category_colors.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/hr_empty_state.dart';
import '../../widgets/common/labeled_field.dart';

/// Recruitment — ported from HR Redesign spec 1d: vacancy summary strip,
/// the pipeline as a Kanban board, then interviews/talent-pool/sources on
/// one row below. Everything on one page, no tabs.
class HrRecruitmentTab extends StatefulWidget {
  const HrRecruitmentTab({super.key});

  @override
  State<HrRecruitmentTab> createState() => _HrRecruitmentTabState();
}

class _HrRecruitmentTabState extends State<HrRecruitmentTab> {
  final _talentPoolKey = GlobalKey();
  bool _loading = true;
  String? _error;
  List<Vacancy> _vacancies = [];
  Vacancy? _active;
  List<Application> _pipeline = [];
  List<Applicant> _pool = [];
  Map<String, int> _hiresBySource = {};

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show whatever's already cached from a
    // previous visit immediately instead of blanking to a spinner on every
    // navigation — see MachineService's own doc comment for the full
    // reasoning.
    final cachedVacancies = RecruitmentService.cachedDefaultVacancies;
    final cachedPool = RecruitmentService.cachedTalentPool;
    if (cachedVacancies != null) {
      _vacancies = cachedVacancies;
      _active = _vacancies.where((v) => v.status == 'open').isNotEmpty
          ? _vacancies.where((v) => v.status == 'open').first
          : (_vacancies.isNotEmpty ? _vacancies.first : null);
      if (_active != null) {
        _pipeline = RecruitmentService.cachedPipelineByVacancyId[_active!.id] ?? [];
      }
    }
    if (cachedPool != null) _pool = cachedPool;
    if (cachedVacancies != null || cachedPool != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_vacancies.isEmpty && _pool.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        RecruitmentService.instance.vacancies(),
        RecruitmentService.instance.applicants(talentPool: true),
        HrReportService.instance.recruitmentSummary(),
      ]);
      final vacancies = results[0] as List<Vacancy>;
      final active = vacancies.where((v) => v.status == 'open').isNotEmpty
          ? vacancies.where((v) => v.status == 'open').first
          : (vacancies.isNotEmpty ? vacancies.first : null);
      final pipeline = active != null ? await RecruitmentService.instance.pipeline(active.id) : <Application>[];
      if (!mounted) return;
      setState(() {
        _vacancies = vacancies;
        _active = active;
        _pipeline = pipeline;
        _pool = results[1] as List<Applicant>;
        _hiresBySource = (results[2] as RecruitmentSummary).hiresBySource;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _selectVacancy(Vacancy v) async {
    setState(() => _active = v);
    try {
      final pipeline = await RecruitmentService.instance.pipeline(v.id);
      if (mounted && _active?.id == v.id) setState(() => _pipeline = pipeline);
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null && _vacancies.isEmpty && _pool.isEmpty) return ErrorView(message: _error!, onRetry: _load);

    final openCount = _vacancies.where((v) => v.status == 'open').length;

    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 900 ? 16.0 : 26.0;
      return SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(openCount),
          const SizedBox(height: 4),
          Container(width: double.infinity, height: 1, color: context.pal.divider),
          const SizedBox(height: 18),
          _vacancyRow(),
          const SizedBox(height: 18),
          if (_active != null) ...[
            _kanbanBoard(),
            const SizedBox(height: 20),
          ],
          _bottomRow(cst.maxWidth >= 1100),
        ]),
      );
    });
  }

  Widget _header(int openCount) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Container(width: 2, height: 32, decoration: BoxDecoration(color: HrCategory.recruitment.color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Recruitment', style: AppTheme.pageTitle.copyWith(fontSize: 21)),
      const SizedBox(height: 3),
      Text('$openCount open vacanc${openCount == 1 ? 'y' : 'ies'} · ${_pipeline.length} in pipeline · ${_pool.length} in talent pool', style: AppTheme.bodySub.copyWith(fontSize: 12)),
    ])),
    OutlinedButton.icon(onPressed: _scrollToTalentPool, icon: const Icon(Symbols.groups, size: 15), label: const Text('Talent pool')),
    const SizedBox(width: 8),
    FilledButton.icon(onPressed: _newVacancy, icon: const Icon(Symbols.add, size: 16), label: const Text('New vacancy')),
  ]);

  Widget _vacancyRow() {
    if (_vacancies.isEmpty) {
      return HrEmptyState(icon: HrCategory.recruitment.icon, title: 'No vacancies yet', message: 'Post a role to start building your applicant pipeline.', actionLabel: 'Post a vacancy', onAction: _newVacancy);
    }
    final others = _vacancies.where((v) => v.id != _active?.id).take(2).toList();
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_active != null) Expanded(child: _activeVacancyCard(_active!)),
        for (final v in others) ...[
          const SizedBox(width: 12),
          SizedBox(width: 300, child: _otherVacancyCard(v)),
        ],
      ]),
    );
  }

  Widget _activeVacancyCard(Vacancy v) {
    final color = HrCategory.recruitment.color;
    final daysOpen = DateTime.tryParse(v.openedAt) != null ? DateTime.now().difference(DateTime.parse(v.openedAt)).inDays : 0;
    final interviews = _pipeline.fold<int>(0, (a, p) => a + p.interviews.length);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.35))),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(left: -16, top: -14, bottom: -14, width: 2, child: Container(color: color)),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(v.positionTitle ?? 'Vacancy #${v.id}', style: AppTheme.cardTitle.copyWith(fontSize: 16)),
              const SizedBox(width: 9),
              _statusChip(v.status, color),
            ]),
            const SizedBox(height: 5),
            Text('${v.department ?? '—'} · opened ${v.openedAt} · $daysOpen days open', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
          ])),
          _statCol('Applicants', '${v.applicationsCount}'),
          const SizedBox(width: 20),
          _statCol('Interviews', '$interviews'),
          const SizedBox(width: 20),
          _statCol('Time to fill', '${daysOpen}d', color: daysOpen > 20 ? AppColors.amber : null),
          const SizedBox(width: 16),
          OutlinedButton(onPressed: () => _setStatus(v, 'on_hold'), child: const Text('Hold')),
          const SizedBox(width: 7),
          OutlinedButton(
            onPressed: () => _setStatus(v, 'closed'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.coral, side: BorderSide(color: AppColors.coral.withValues(alpha: 0.5))),
            child: const Text('Close'),
          ),
        ]),
      ]),
    );
  }

  Widget _otherVacancyCard(Vacancy v) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => _selectVacancy(v),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(v.positionTitle ?? 'Vacancy #${v.id}', style: AppTheme.bodySub.copyWith(fontSize: 13.5)),
            const SizedBox(width: 8),
            _statusChip(v.status, context.pal.textDim),
          ]),
          const SizedBox(height: 4),
          Text('${v.applicationsCount} applicant(s) · ${v.closedAt ?? v.openedAt}', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
        ])),
        Icon(Symbols.arrow_forward, size: 15, color: context.pal.textDim),
      ]),
    ),
  );

  Widget _statCol(String label, String value, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
    const SizedBox(height: 2),
    Text(value, style: AppTheme.monoXs.copyWith(fontSize: 17, color: color ?? context.pal.text)),
  ]);

  Widget _statusChip(String status, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(5)),
    child: Text(status.replaceAll('_', ' '), style: AppTheme.monoXs.copyWith(fontSize: 10, color: color)),
  );

  Future<void> _setStatus(Vacancy v, String status) async {
    try {
      await RecruitmentService.instance.updateVacancy(v.id, {'status': status});
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  static const _stages = ['applied', 'shortlisted', 'interviewed', 'offered', 'hired'];
  static const _stageLabels = {'applied': 'Applied', 'shortlisted': 'Shortlisted', 'interviewed': 'Interviewed', 'offered': 'Offered', 'hired': 'Hired'};
  static List<Color> get _stageColors => [AppColors.violet, const Color(0xFF8B76E0), const Color(0xFF7A63D6), const Color(0xFF6A54C4), AppColors.green];

  Widget _kanbanBoard() {
    return SizedBox(
      height: 280,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < _stages.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _kanbanColumn(_stages[i], _stageColors[i])),
        ],
      ]),
    );
  }

  Widget _kanbanColumn(String stage, Color color) {
    final apps = _pipeline.where((a) => a.status == stage).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(_stageLabels[stage]!.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10)),
        const SizedBox(width: 6),
        Text('${apps.length}', style: AppTheme.monoXs.copyWith(fontSize: 11)),
      ]),
      const SizedBox(height: 9),
      Expanded(child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: apps.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.inbox, size: 17, color: context.pal.textDim),
                const SizedBox(height: 6),
                Text('Nothing here', style: AppTheme.monoXs.copyWith(fontSize: 11)),
              ]))
            : ListView.separated(
                itemCount: apps.length,
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (_, i) => _pipelineCard(apps[i]),
              ),
      )),
    ]);
  }

  Widget _pipelineCard(Application a) {
    final nextInterview = a.interviews.isNotEmpty ? a.interviews.last : null;
    return GestureDetector(
      onTap: () => _advanceStage(a),
      onLongPress: () => _scheduleInterview(a),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(11), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _avatar(a.applicantName ?? '?', a.id),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(a.applicantName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(a.appliedAt, style: AppTheme.monoXs.copyWith(fontSize: 10)),
            ])),
          ]),
          if (a.applicantSource != null || a.applicantCv != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (a.applicantSource != null) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(5)),
                child: Text(a.applicantSource!, style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: context.pal.textMute)),
              ),
              if (a.applicantCv != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _openCv(a.applicantCv!.url),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Symbols.picture_as_pdf, size: 10.5, color: AppColors.coral),
                      const SizedBox(width: 3),
                      Text('CV', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: AppColors.coral)),
                    ]),
                  ),
                ),
              ],
            ]),
          ],
          if (nextInterview != null) ...[
            const SizedBox(height: 8),
            Container(width: double.infinity, height: 1, color: context.pal.divider),
            const SizedBox(height: 7),
            Row(children: [
              Icon(Symbols.calendar_month, size: 12, color: AppColors.amber),
              const SizedBox(width: 6),
              Expanded(child: Text(nextInterview.scheduledAt, style: AppTheme.monoXs.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _avatar(String name, int seed) {
    final palette = [AppColors.violet, AppColors.cyan, AppColors.amber, AppColors.info];
    final color = palette[seed % palette.length];
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((p) => p.isNotEmpty ? p[0] : '').join().toUpperCase();
    return Container(
      width: 26, height: 26, alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(initials, style: AppTheme.monoXs.copyWith(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF08090B))),
    );
  }

  Widget _bottomRow(bool wide) {
    final children = [
      Expanded(flex: 11, child: _interviewsCard()),
      const SizedBox(width: 16),
      Expanded(flex: 10, child: _talentPoolCard()),
      const SizedBox(width: 16),
      Expanded(flex: 8, child: _sourcesCard()),
    ];
    return wide
        ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))
        : Column(children: [_interviewsCard(), const SizedBox(height: 14), _talentPoolCard(), const SizedBox(height: 14), _sourcesCard()]);
  }

  Widget _railHeader(IconData icon, Color color, String title, {String? count}) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 8),
    Text(title.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
    if (count != null) ...[const SizedBox(width: 6), Text(count, style: AppTheme.monoXs.copyWith(fontSize: 11))],
    const SizedBox(width: 8),
    Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
  ]);

  Widget _interviewsCard() {
    final upcoming = _pipeline.expand((a) => a.interviews.map((iv) => (a, iv))).toList()
      ..sort((x, y) => x.$2.scheduledAt.compareTo(y.$2.scheduledAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _railHeader(Symbols.calendar_month, AppColors.amber, 'Scheduled interviews'),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: upcoming.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No interviews scheduled.', style: AppTheme.bodySub.copyWith(fontSize: 12))))
            : Column(children: upcoming.map((pair) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  Expanded(child: Text(pair.$1.applicantName ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
                  Text(pair.$2.stage ?? '—', style: AppTheme.monoXs.copyWith(fontSize: 10.5)),
                  const SizedBox(width: 10),
                  Text(pair.$2.scheduledAt, style: AppTheme.monoXs.copyWith(fontSize: 11)),
                ]),
              )).toList()),
      ),
    ]);
  }

  void _scrollToTalentPool() {
    final ctx = _talentPoolKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, alignment: 0.1);
  }

  Widget _talentPoolCard() => Column(key: _talentPoolKey, crossAxisAlignment: CrossAxisAlignment.start, children: [
    _railHeader(Symbols.groups, HrCategory.recruitment.color, 'Talent pool', count: '${_pool.length}'),
    const SizedBox(height: 9),
    Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      child: _pool.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Nobody in the pool yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))))
          : Column(children: _pool.map((p) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                _avatar(p.name, p.id),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(p.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(p.skillsTags ?? p.sourceChannel ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                if (p.latestCv != null) ...[
                  GestureDetector(
                    onTap: () => _openCv(p.latestCv!.url),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.coral.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Symbols.picture_as_pdf, size: 11, color: AppColors.coral),
                        const SizedBox(width: 3),
                        Text('CV v${p.latestCv!.version}', style: AppTheme.monoXs.copyWith(fontSize: 9.5, color: AppColors.coral)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => _uploadCv(p),
                    icon: Icon(Symbols.upload_file, size: 15, color: context.pal.textDim),
                    tooltip: 'Replace CV', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ] else
                  TextButton(onPressed: () => _uploadCv(p), child: const Text('Upload CV')),
              ]),
            )).toList()),
    ),
  ]);

  Widget _sourcesCard() {
    final maxN = _hiresBySource.values.fold(0, (a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _railHeader(Symbols.podcasts, HrCategory.recruitment.color, 'Hires by source'),
      const SizedBox(height: 9),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: _hiresBySource.isEmpty
            ? Text('No hires recorded yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
            : Column(children: _hiresBySource.entries.map((e) {
                final pct = maxN > 0 ? (e.value / maxN).clamp(0.05, 1.0) : 0.05;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(e.key, style: AppTheme.monoXs.copyWith(fontSize: 11))),
                      Text('${e.value}', style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: context.pal.text)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(borderRadius: BorderRadius.circular(3), child: FractionallySizedBox(
                      widthFactor: pct, alignment: Alignment.centerLeft,
                      child: Container(width: double.infinity, height: 6, color: HrCategory.recruitment.color),
                    )),
                  ]),
                );
              }).toList()),
      ),
    ]);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _newVacancy() async {
    List<Position> positions = [];
    try { positions = await PositionService.instance.list(); } catch (_) {}
    if (!mounted) return;
    int? positionId = positions.isNotEmpty ? positions.first.id : null;
    final reqCtrl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('New Vacancy', style: AppTheme.cardTitle),
        content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LabeledDropdown<int?>(
            label: 'Position', value: positionId,
            items: positions.map((p) => p.id).toList(),
            displayBuilder: (id) => positions.firstWhere((p) => p.id == id).title,
            onChanged: (v) => setDialogState(() => positionId = v),
          ),
          const SizedBox(height: 12),
          LabeledTextField(label: 'Requirements', controller: reqCtrl, maxLines: 3),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Create')),
        ],
      ),
    ));
    if (go != true || positionId == null) return;
    try {
      await RecruitmentService.instance.createVacancy({'position_id': positionId, 'requirements': reqCtrl.text.trim().isNotEmpty ? reqCtrl.text.trim() : null});
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _advanceStage(Application a) async {
    final next = await showDialog<String>(context: context, builder: (dialogCtx) => SimpleDialog(
      backgroundColor: context.pal.surface1,
      title: const Text('Move to Stage'),
      children: Application.stageLabels.entries.map((e) => SimpleDialogOption(onPressed: () => Navigator.of(dialogCtx).pop(e.key), child: Text(e.value))).toList(),
    ));
    if (next == null) return;
    try {
      await RecruitmentService.instance.updateStage(a.id, next);
      if (_active != null) _selectVacancy(_active!);
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _scheduleInterview(Application a) async {
    DateTime date = DateTime.now().add(const Duration(days: 3));
    final stageCtrl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('Schedule Interview — ${a.applicantName ?? ''}', style: AppTheme.cardTitle),
        content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LabeledDateField(label: 'Date', date: date, onTap: () async {
            final picked = await showDatePicker(context: dialogCtx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null) setDialogState(() => date = picked);
          }),
          const SizedBox(height: 12),
          LabeledTextField(label: 'Stage', controller: stageCtrl, hint: 'e.g. Technical'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Schedule')),
        ],
      ),
    ));
    if (go != true) return;
    try {
      await RecruitmentService.instance.scheduleInterview(a.id, {'scheduled_at': date.toIso8601String(), 'stage': stageCtrl.text.trim().isNotEmpty ? stageCtrl.text.trim() : null});
      if (_active != null) _selectVacancy(_active!);
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }

  Future<void> _openCv(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _uploadCv(Applicant a) async {
    final result = await FilePicker.pickFiles(allowMultiple: false, withData: false);
    if (result == null || result.files.single.path == null) return;
    try {
      await RecruitmentService.instance.uploadCv(a.id, result.files.single.path!, result.files.single.name);
      if (mounted) showSuccessToast(context, 'CV uploaded.');
      _load();
    } catch (e) { if (mounted) showErrorToast(context, e); }
  }
}

