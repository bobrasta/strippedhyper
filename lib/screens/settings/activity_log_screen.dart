import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/activity_log_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';

// Read-only history of who changed what — spatie/laravel-activitylog rows
// plus ApprovalLog-recorded actions, surfaced via ActivityLogController on
// the backend (admin-tier only server-side; this screen only appears in the
// sidebar for that tier too, see allowedScreenKeys/_system in sidebar.dart).
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  List<ActivityLogEntry> _entries = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known first page immediately
    // (surviving widget disposal, unlike State fields) while a real refresh
    // happens silently in the background — see MachineService's own doc
    // comment for the full reasoning. Scoped to page 1 only; navigating to
    // another page still shows the normal loading state.
    final cached = ActivityLogService.cachedFirstPage;
    if (cached != null) {
      _entries = cached.items;
      _page = cached.currentPage;
      _lastPage = cached.lastPage;
      _loading = false;
    }
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      if (_entries.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final result = await ActivityLogService.instance.list(page: page);
      if (!mounted) return;
      setState(() {
        _entries = result.items;
        _page = result.currentPage;
        _lastPage = result.lastPage;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Activity Log', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('Who changed what, company-wide — record creation, field edits, approvals', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
            IconButton(onPressed: () => _load(page: _page), icon: const Icon(Symbols.refresh, size: 20)),
          ]),
        ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null && _entries.isEmpty
                ? ErrorView(message: _error!, onRetry: () => _load(page: _page))
                : _entries.isEmpty
                    ? Center(child: Text('No activity recorded yet.', style: AppTheme.bodySub))
                    : ListView.separated(
                        padding: EdgeInsets.all(pad),
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _EntryCard(entry: _entries[i], dateLabel: _fmtDate(_entries[i].createdAt)),
                      )),
        if (_lastPage > 1)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(onPressed: _page > 1 ? () => _load(page: _page - 1) : null, child: const Text('Previous')),
              Text('Page $_page of $_lastPage', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              TextButton(onPressed: _page < _lastPage ? () => _load(page: _page + 1) : null, child: const Text('Next')),
            ]),
          ),
      ]);
    });
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.dateLabel});
  final ActivityLogEntry entry;
  final String dateLabel;

  static final _typeWords = RegExp(r'(?<=[a-z])(?=[A-Z])');

  (IconData, Color) _verbStyle() => switch (entry.description) {
    'created' => (Symbols.add_circle, AppColors.green),
    'deleted' => (Symbols.delete, AppColors.coral),
    'updated' => (Symbols.edit, AppColors.cyan),
    _ => (Symbols.bolt, AppColors.violet),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _verbStyle();
    final type = entry.subjectType.split(_typeWords).join(' ');
    final record = entry.subjectLabel ?? (entry.subjectId != null ? '#${entry.subjectId}' : '');
    final isCreate = entry.description == 'created';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.pal.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.summary ?? entry.description, style: AppTheme.bodySm.copyWith(fontSize: 13.5, color: context.pal.text))),
          const SizedBox(width: 10),
          Text(dateLabel, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(record.isEmpty ? type : '$type · $record', style: AppTheme.monoXs.copyWith(color: AppColors.violet, fontSize: 10)),
          ),
          Text(
            'by ${entry.causerName ?? 'System'}${entry.causerRole != null ? ' · ${entry.causerRole}' : ''}',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textDim),
          ),
        ]),
        if (entry.fieldChanges.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: context.pal.surface2.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in entry.fieldChanges)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 150, child: Text(c.field, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: context.pal.textMute))),
                    Expanded(child: Text.rich(TextSpan(children: [
                      if (!isCreate && c.oldValue != null) ...[
                        TextSpan(text: c.oldValue, style: TextStyle(color: context.pal.textDim, decoration: TextDecoration.lineThrough)),
                        TextSpan(text: '  →  ', style: TextStyle(color: context.pal.textDim)),
                      ],
                      TextSpan(text: c.newValue ?? '—', style: TextStyle(color: context.pal.text)),
                    ]), style: AppTheme.monoXs.copyWith(fontSize: 11.5))),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}
