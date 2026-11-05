// NeST tender tracker (Tendering & Logistics → NeST Tenders). Tenders come
// from nest.go.tz three times a day via the API (`nest:sync`), already
// scored for relevance to a medical-device / laboratory-reagent supplier.
// Tabs: Overview (counts that tap through to a filtered list), Tenders,
// Buyers (procuring entities) and Settings (rules, alerts, NeST login).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/nest_tender.dart';
import '../../services/nest_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/procurement/nest_widgets.dart';
import '../../widgets/procurement/proc_widgets.dart';
import 'nest_settings_tab.dart';
import 'nest_tender_detail_screen.dart';

class NestTendersScreen extends StatefulWidget {
  const NestTendersScreen({super.key, this.initialTenderId});
  /// Opened from a NeST notification — jumps straight to that tender.
  final int? initialTenderId;
  @override
  State<NestTendersScreen> createState() => _NestTendersScreenState();
}

class _NestTendersScreenState extends State<NestTendersScreen> {
  int _tab = 0; // overview · tenders · buyers · settings
  NestFilter _filter = const NestFilter();
  NestDashboard? _dash = NestService.cachedDashboard;
  String? _dashError;
  bool _syncing = false;
  final _listKey = GlobalKey<NestTenderListState>();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    if (widget.initialTenderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.initialTenderId!));
    }
  }

  Future<void> _loadDashboard({bool peek = false}) async {
    try {
      final d = await NestService.instance.dashboard(peek: peek);
      if (mounted) setState(() { _dash = d; _dashError = null; });
    } catch (e) {
      if (mounted) setState(() => _dashError = friendlyError(e));
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NestTenderDetailScreen(tenderId: id)));
    _listKey.currentState?.reload();
    _loadDashboard(peek: true);
  }

  /// Overview tiles land here with their filter preset.
  void _showList(NestFilter f) => setState(() { _filter = f; _tab = 1; });

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await NestService.instance.syncNow();
      if (mounted) showSuccessToast(context, 'Checking NeST now — new tenders appear in a few minutes.');
      // The run itself takes ~1 min (polite pauses between pages).
      Future.delayed(const Duration(seconds: 75), () { if (mounted) { _loadDashboard(peek: true); _listKey.currentState?.reload(); } });
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _subtitle(NestDashboard? d) {
    if (d == null) return 'Tenders published on nest.go.tz, scored for devices and reagents';
    final s = d.sync;
    final last = s.lastOkAt == null ? 'not checked yet' : 'checked ${timeAgo(s.lastOkAt!)}';
    return '${d.openRelevant} open relevant · ${d.closing3} closing within 3 days · $last';
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final d = _dash;
    final canManage = d?.canManage ?? false;
    return Container(
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ProcPageHeader(
          title: 'NeST tenders',
          subtitle: _subtitle(d),
          accent: AppColors.green,
          actions: [
            ProcButton(label: 'Open NeST', icon: Symbols.open_in_new,
                onPressed: () => launchUrl(Uri.parse('https://nest.go.tz'), mode: LaunchMode.externalApplication)),
            if (canManage) ProcButton(
              label: _syncing ? 'Starting…' : 'Check NeST now', icon: Symbols.sync, tone: ProcTone.green,
              locked: d != null && !d.sync.canRunNow,
              onPressed: _syncing ? null : _syncNow,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: ProcSegmented(
            options: const ['Overview', 'Tenders', 'Buyers', 'Settings'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          )),
        ),
        Expanded(child: IndexedStack(index: _tab, children: [
          _Overview(dash: d, error: _dashError, onRetry: _loadDashboard, onRefresh: () => _loadDashboard(peek: true), onFilter: _showList),
          NestTenderList(key: _listKey, filter: _filter, onFilterChanged: (f) => setState(() => _filter = f), onOpen: _open),
          _Buyers(onOpenEntity: (e) => _showList(NestFilter(open: false, relevance: 'all', sort: 'newest', entityUuid: e.uuid))),
          NestSettingsTab(onChanged: () { _loadDashboard(peek: true); _listKey.currentState?.reload(); }),
        ])),
      ]),
    );
  }
}

// ── Overview ────────────────────────────────────────────────────────────────

class _Overview extends StatelessWidget {
  const _Overview({required this.dash, required this.error, required this.onRetry, required this.onRefresh, required this.onFilter});
  final NestDashboard? dash;
  final String? error;
  final Future<void> Function({bool peek}) onRetry;
  final Future<void> Function() onRefresh;
  final ValueChanged<NestFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final d = dash;
    if (d == null) {
      return error != null ? ErrorView(message: error!, onRetry: () => onRetry()) : const Center(child: CircularProgressIndicator());
    }
    const base = NestFilter();
    final s = d.sync;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        if (s.totalStored == 0) ...[
          const NestEmpty('Nothing fetched from NeST yet. The first check runs at the next scheduled time (07:00, 13:00 or 19:00), or use "Check NeST now".'),
          const SizedBox(height: 14),
        ],
        if (s.lastStatus == 'failed') ...[
          ProcPanel(title: 'Last NeST check failed', icon: Symbols.error, iconColor: AppColors.coral, borderColor: AppColors.coral.withValues(alpha: 0.4),
            child: Padding(padding: const EdgeInsets.all(14), child: Text(
                '${s.lastError ?? 'Unknown error'}\nNothing was removed — the list shows what the last good check found.',
                style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)))),
          const SizedBox(height: 14),
        ],
        _TileGrid(tiles: [
          _Tile(Symbols.travel_explore, ProcTone.green, 'Open relevant', '${d.openRelevant}', '${d.openMaybe} more maybe',
              () => onFilter(base)),
          _Tile(Symbols.alarm, ProcTone.coral, 'Closing ≤ 3 days', '${d.closing3}', d.closing3 == 0 ? 'nothing urgent' : 'act now',
              () => onFilter(base.copyWith(closingWithin: () => 3)), alarm: d.closing3 > 0),
          _Tile(Symbols.event, ProcTone.amber, 'Closing ≤ 7 days', '${d.closing7}', 'this week',
              () => onFilter(base.copyWith(closingWithin: () => 7))),
          _Tile(Symbols.fiber_new, ProcTone.teal, 'New since last visit', '${d.newSinceVisit}', 'relevant',
              () => onFilter(base.copyWith(open: false, newSinceVisit: true, sort: 'newest'))),
        ]),
        const SizedBox(height: 14),
        ProcPanel(
          title: 'Open relevant by tag', icon: Symbols.sell,
          child: Padding(padding: const EdgeInsets.all(12), child: _TileGrid(compact: true, tiles: [
            for (final tag in nestTags) _Tile(Symbols.label, nestTagTone(tag), nestTagLabel(tag), '${d.byTag[tag] ?? 0}', '',
                () => onFilter(base.copyWith(tags: {tag}))),
          ])),
        ),
        const SizedBox(height: 14),
        ProcPanel(
          title: 'Pipeline', icon: Symbols.route,
          trailing: Text('relevant tenders, all dates', style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim)),
          child: Padding(padding: const EdgeInsets.all(12), child: _TileGrid(compact: true, tiles: [
            for (final p in nestPipeline.where((p) => p != 'skipped'))
              _Tile(Symbols.circle, nestPipelineTone(p), nestPipelineLabel(p), '${d.byPipeline[p] ?? 0}', '',
                  () => onFilter(base.copyWith(open: false, pipeline: {p}, sort: 'newest'))),
          ])),
        ),
        const SizedBox(height: 14),
        ProcPanel(
          title: 'Top buyers of devices & reagents', icon: Symbols.apartment,
          child: d.topEntities.isEmpty
              ? Padding(padding: const EdgeInsets.all(14), child: Text('No relevant tenders yet.', style: AppTheme.bodySub.copyWith(color: pal.textDim)))
              : Column(children: [
                  for (final e in d.topEntities) InkWell(
                    onTap: () => onFilter(NestFilter(open: false, relevance: 'all', sort: 'newest', entityUuid: e.uuid)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                      child: Row(children: [
                        Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12))),
                        const SizedBox(width: 10),
                        Text('${e.relevantCount}', style: procMono(context, color: pal.text)),
                      ]),
                    ),
                  ),
                ]),
        ),
        const SizedBox(height: 12),
        Text(
          'NeST is checked at 07:00, 13:00 and 19:00 (at most ${s.maxRunsPerDay} times a day, ${s.runsToday} so far today) · ${s.totalStored} tenders stored',
          style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim),
        ),
      ]),
    );
  }
}

class _Tile {
  final IconData icon;
  final ProcTone tone;
  final String label, value, note;
  final VoidCallback onTap;
  final bool alarm;
  const _Tile(this.icon, this.tone, this.label, this.value, this.note, this.onTap, {this.alarm = false});
}

/// Tappable count tiles: 4 (or however many) across, 2 per row on phones.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, this.compact = false});
  final List<_Tile> tiles;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth < 560 ? 2 : (compact && tiles.length > 4 ? (box.maxWidth < 900 ? 3 : tiles.length) : tiles.length);
      const gap = 10.0;
      final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final t in tiles) SizedBox(width: w, child: Material(
          color: t.alarm ? AppColors.coral.withValues(alpha: 0.06) : pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rMd),
          child: InkWell(
            onTap: t.onTap,
            borderRadius: BorderRadius.circular(AppColors.rMd),
            child: Container(
              padding: EdgeInsets.fromLTRB(14, compact ? 10 : 13, 14, compact ? 10 : 13),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppColors.rMd),
                  border: Border.all(color: t.alarm ? AppColors.coral.withValues(alpha: 0.4) : pal.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(t.icon, size: 13, color: t.tone.fg(context), fill: t.alarm || compact ? 1 : 0),
                  const SizedBox(width: 7),
                  Expanded(child: Text(t.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: procCaps(context, color: t.alarm ? AppColors.coral : null))),
                ]),
                SizedBox(height: compact ? 5 : 8),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(t.value, style: AppTheme.kpiValue.copyWith(fontSize: compact ? 20 : 26, height: 1,
                      color: t.alarm ? AppColors.coral : pal.text)),
                  if (t.note.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.note, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim))),
                  ],
                ]),
              ]),
            ),
          ),
        )),
      ]);
    });
  }
}

// ── Tenders list ─────────────────────────────────────────────────────────────

/// Filter bar + paged list (20 per page, more on scroll). Public so the
/// widget tests can drive the filters.
class NestTenderList extends StatefulWidget {
  const NestTenderList({super.key, required this.filter, required this.onFilterChanged, required this.onOpen, this.service});
  final NestFilter filter;
  final ValueChanged<NestFilter> onFilterChanged;
  final ValueChanged<int> onOpen;
  /// Injected in tests.
  final Future<NestPage> Function(NestFilter f, int page)? service;
  @override
  State<NestTenderList> createState() => NestTenderListState();
}

class NestTenderListState extends State<NestTenderList> {
  final _scroll = ScrollController();
  final List<NestTender> _rows = [];
  int _page = 0, _lastPage = 1, _total = 0;
  bool _loading = false;
  String? _error;
  int _gen = 0; // drops responses for an outdated filter
  Timer? _debounce;

  Future<NestPage> _fetch(NestFilter f, int page) =>
      widget.service?.call(f, page) ?? NestService.instance.list(f, page: page);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _more();
    });
    reload();
  }

  @override
  void didUpdateWidget(NestTenderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    final gen = ++_gen;
    setState(() { _loading = true; _error = null; });
    try {
      final p = await _fetch(widget.filter, 1);
      if (!mounted || gen != _gen) return;
      setState(() { _rows..clear()..addAll(p.rows); _page = p.page; _lastPage = p.lastPage; _total = p.total; _loading = false; });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _more() async {
    if (_loading || _page >= _lastPage || _error != null) return;
    final gen = _gen;
    setState(() => _loading = true);
    try {
      final p = await _fetch(widget.filter, _page + 1);
      if (!mounted || gen != _gen) return;
      setState(() { _rows.addAll(p.rows); _page = p.page; _lastPage = p.lastPage; _loading = false; });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _set(NestFilter f) => widget.onFilterChanged(f);

  void _toggleTag(String tag) {
    final tags = {...widget.filter.tags};
    tags.contains(tag) ? tags.remove(tag) : tags.add(tag);
    _set(widget.filter.copyWith(tags: tags));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final f = widget.filter;
    const relevanceOptions = ['relevant', 'maybe', 'all'];

    final filters = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SearchField(
        key: ValueKey('nest-search-${f.entityUuid}'),
        hint: 'Description, buyer or reference…',
        width: 280,
        onChanged: (v) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), () => _set(widget.filter.copyWith(q: v)));
        },
      ),
      ProcSegmented(
        options: const ['Relevant', 'Maybe', 'All'],
        selected: relevanceOptions.indexOf(f.relevance).clamp(0, 2),
        onChanged: (i) => _set(f.copyWith(relevance: relevanceOptions[i])),
      ),
      NestToggleChip(label: 'Open', icon: Symbols.lock_open, selected: f.open, onTap: () => _set(f.copyWith(open: !f.open))),
      for (final tag in nestTags) NestToggleChip(label: nestTagLabel(tag), tone: nestTagTone(tag),
          selected: f.tags.contains(tag), onTap: () => _toggleTag(tag)),
      NestToggleChip(label: 'Closing soon', icon: Symbols.alarm, tone: ProcTone.coral, selected: f.closingWithin != null,
          onTap: () => _set(f.copyWith(closingWithin: () => f.closingWithin == null ? 3 : null))),
      NestToggleChip(label: 'My tenders', icon: Symbols.person, selected: f.mine, onTap: () => _set(f.copyWith(mine: !f.mine))),
      SizedBox(width: 190, child: DropdownFieldBox<String>(
        value: f.sort,
        items: const [
          DropdownMenuItem(value: 'closing', child: Text('Closing soonest')),
          DropdownMenuItem(value: 'newest', child: Text('Newest')),
          DropdownMenuItem(value: 'score', child: Text('Best match')),
        ],
        onChanged: (v) { if (v != null) _set(f.copyWith(sort: v)); },
      )),
    ]);

    final extras = [
      if (f.entityUuid != null) NestToggleChip(label: 'One buyer only ×', icon: Symbols.apartment, selected: true,
          onTap: () => _set(f.copyWith(entityUuid: () => null, relevance: 'relevant', open: true, sort: 'closing'))),
      if (f.newSinceVisit) NestToggleChip(label: 'New since last visit ×', icon: Symbols.fiber_new, selected: true,
          onTap: () => _set(f.copyWith(newSinceVisit: false))),
      if (f.pipeline.isNotEmpty) NestToggleChip(label: '${f.pipeline.map(nestPipelineLabel).join(', ')} ×', icon: Symbols.route, selected: true,
          onTap: () => _set(f.copyWith(pipeline: {}))),
      if (f.closingWithin != null && f.closingWithin != 3) NestToggleChip(label: 'Closing ≤ ${f.closingWithin} days ×', selected: true,
          onTap: () => _set(f.copyWith(closingWithin: () => null))),
    ];

    return RefreshIndicator(
      onRefresh: reload,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        return CustomScrollView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverPadding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), sliver: SliverToBoxAdapter(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              filters,
              if (extras.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: extras)],
              const SizedBox(height: 10),
              Text(_loading && _rows.isEmpty ? 'Loading…' : '$_total tender${_total == 1 ? '' : 's'}',
                  key: const ValueKey('nest-count'), style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
              const SizedBox(height: 8),
            ]))),
          if (_error != null && _rows.isEmpty)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: ErrorView(message: _error!, onRetry: reload)))
          else if (!_loading && _rows.isEmpty)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16),
                child: NestEmpty('No tenders match these filters.')))
          else
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), sliver: SliverToBoxAdapter(child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (wide) const NestTableHeader(),
                for (final t in _rows) NestTenderRow(tender: t, wide: wide, onTap: () => widget.onOpen(t.id)),
                if (_loading) const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
                if (_error != null && _rows.isNotEmpty) Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                  Icon(Symbols.wifi_off, size: 14, color: AppColors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textMute))),
                  TextButton(onPressed: () { setState(() => _error = null); _more(); }, child: const Text('Retry')),
                ])),
              ]),
            ))),
        ]);
      }),
    );
  }
}

// ── Buyers ─────────────────────────────────────────────────────────────────

class _Buyers extends StatefulWidget {
  const _Buyers({required this.onOpenEntity});
  final ValueChanged<NestEntity> onOpenEntity;
  @override
  State<_Buyers> createState() => _BuyersState();
}

class _BuyersState extends State<_Buyers> {
  List<NestEntity>? _rows;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await NestService.instance.entities();
      if (mounted) setState(() { _rows = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final rows = _rows;
    if (rows == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    final q = _q.toLowerCase();
    final shown = rows.where((e) => q.isEmpty || e.name.toLowerCase().contains(q)).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        SearchField(hint: 'Find a procuring entity…', width: 320, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 6),
        Text('Who buys devices and reagents, and how often — most relevant tenders first. Tap one for its tender history.',
            style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        const SizedBox(height: 10),
        if (shown.isEmpty) const NestEmpty('No procuring entities yet.', icon: Symbols.apartment)
        else Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: pal.surface1, borderRadius: BorderRadius.circular(AppColors.rMd), border: Border.all(color: pal.border)),
          child: Column(children: [
            for (final e in shown) InkWell(
              onTap: () => widget.onOpenEntity(e),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                    const SizedBox(height: 2),
                    Text([
                      '${e.totalCount} tender${e.totalCount == 1 ? '' : 's'} on NeST',
                      if (e.lastTenderAt != null) 'latest ${formatDate(toEat(e.lastTenderAt!))}',
                    ].join(' · '), style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
                  ])),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${e.relevantCount}', style: AppTheme.kpiValue.copyWith(fontSize: 18, height: 1,
                        color: e.relevantCount > 0 ? AppColors.green : pal.textDim)),
                    Text('relevant', style: AppTheme.bodySub.copyWith(fontSize: 10, color: pal.textDim)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
