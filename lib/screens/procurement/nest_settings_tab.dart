// NeST tenders → Settings: own alert toggles (everyone), and for procurement
// staff the relevance rules, threshold and the company NeST login used to
// fetch tender documents. Rule and threshold edits re-score every stored
// tender on the server (queued).

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
import 'tender_forms.dart' show ProcDialog, formRow;

class NestSettingsTab extends StatefulWidget {
  const NestSettingsTab({super.key, this.onChanged});
  /// Rules/threshold changed — the caller refreshes its counts.
  final VoidCallback? onChanged;
  @override
  State<NestSettingsTab> createState() => _NestSettingsTabState();
}

class _NestSettingsTabState extends State<NestSettingsTab> {
  NestSettings? _s;
  List<NestRule>? _rules;
  String? _error;
  String? _busy;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _threshold = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await NestService.instance.settings();
      final (rules, _, _, _) = await NestService.instance.rules();
      if (!mounted) return;
      setState(() {
        _s = s;
        _rules = rules;
        _error = null;
        _user.text = s.nestUsername ?? '';
        _threshold.text = '${s.threshold}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _run(String key, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = key);
    try {
      await action();
      if (done != null && mounted) showSuccessToast(context, done);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _toggleAlert(String key, bool on) => _run('alert', () async {
    final s = await NestService.instance.saveSettings({'notifications': {key: on}});
    if (mounted) setState(() => _s = s);
  });

  Future<void> _saveLogin() => _run('login', () async {
    if (_user.text.trim().isEmpty) throw Exception('Enter the NeST username (email).');
    var s = await NestService.instance.saveSettings({
      'nest_username': _user.text.trim(),
      if (_pass.text.isNotEmpty) 'nest_password': _pass.text,
    });
    _pass.clear();
    // Try it straight away so a typo shows now, not when someone needs a document.
    try {
      s = await NestService.instance.testLogin();
      if (mounted) showSuccessToast(context, 'Saved — NeST accepted the login.');
    } catch (e) {
      if (mounted) showErrorToast(context, e);
      s = await NestService.instance.settings();
    }
    if (mounted) setState(() => _s = s);
  });

  Future<void> _forgetLogin() => _run('login', () async {
    final s = await NestService.instance.saveSettings({'forget_login': true});
    _user.clear();
    _pass.clear();
    if (mounted) setState(() => _s = s);
  }, done: 'NeST login removed.');

  Future<void> _saveThreshold() => _run('threshold', () async {
    final v = int.tryParse(_threshold.text.trim());
    if (v == null || v < 1 || v > 100) throw Exception('The threshold is a whole number from 1 to 100.');
    final s = await NestService.instance.saveSettings({'threshold': v});
    if (mounted) setState(() => _s = s);
    widget.onChanged?.call();
  }, done: 'Threshold saved — re-scoring all tenders.');

  Future<void> _recompute() => _run('recompute', () async {
    await NestService.instance.recompute();
    widget.onChanged?.call();
  }, done: 'Re-scoring all tenders — counts update in a moment.');

  Future<void> _editRule([NestRule? rule]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _RuleForm(rule: rule));
    if (saved == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _toggleRule(NestRule r) => _run('rule-${r.id}', () async {
    await NestService.instance.saveRule({'active': !r.active}, id: r.id);
    await _load();
    widget.onChanged?.call();
  });

  Future<void> _deleteRule(NestRule r) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete rule?'),
      content: Text('"${r.term}" will stop counting. You can switch a rule off instead to keep it for later.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    await _run('rule-${r.id}', () async {
      await NestService.instance.deleteRule(r.id);
      await _load();
      widget.onChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
        _alerts(context, s),
        if (s.canManage) ...[
          const SizedBox(height: 14),
          _login(context, s),
          const SizedBox(height: 14),
          _scoring(context, s),
        ],
        const SizedBox(height: 14),
        _rulesPanel(context, s),
      ]),
    );
  }

  Widget _alerts(BuildContext context, NestSettings s) {
    final pal = context.pal;
    Widget row(String key, String title, String sub) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
          Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11, color: pal.textDim)),
        ])),
        Switch(value: s.notifications[key] ?? true, onChanged: _busy == null ? (v) => _toggleAlert(key, v) : null),
      ]),
    );
    return ProcPanel(
      title: 'My alerts', icon: Symbols.notifications,
      footer: const ProcNote('In-app notifications, with an email copy to your @hypermed.co.tz address.'),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: [
        row('new_relevant', 'New relevant tenders', 'After each NeST check (one summary when many arrive at once)'),
        row('changes', 'Changes on tenders we are working on', 'Closing date moved, addendum added, lots changed'),
        row('digest', 'Morning digest (07:30)', 'Relevant tenders closing within 3 days that nobody has picked up'),
      ])),
    );
  }

  Widget _login(BuildContext context, NestSettings s) {
    final pal = context.pal;
    final status = !s.serverReady
        ? ('The server is not set up for NeST sign-in yet (NEST_CLIENT_SECRET).', ProcTone.amber)
        : s.lastLoginError != null
            ? ('Last sign-in failed: ${s.lastLoginError}', ProcTone.coral)
            : s.lastLoginOkAt != null
                ? ('Signed in to NeST ${timeAgo(s.lastLoginOkAt!.toLocal())}.', ProcTone.green)
                : s.hasPassword ? ('Saved, not tried yet.', ProcTone.neutral) : ('Not set up.', ProcTone.neutral);
    return ProcPanel(
      title: 'Company NeST login', icon: Symbols.key,
      footer: ProcNote('Used only by the server to fetch tender documents. The password is stored encrypted and never shown again. '
          'The tender list itself needs no login.', tone: ProcTone.teal),
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Symbols.circle, size: 9, fill: 1, color: status.$2.fg(context)),
          const SizedBox(width: 8),
          Expanded(child: Text(status.$1, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute))),
        ]),
        const SizedBox(height: 12),
        formRow([
          LabeledTextField(label: 'NeST username (email)', controller: _user, keyboardType: TextInputType.emailAddress,
              hint: 'tenders@hypermed.co.tz'),
          LabeledTextField(label: s.hasPassword ? 'Password (leave blank to keep)' : 'Password', controller: _pass, obscure: true),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ProcButton(label: _busy == 'login' ? 'Checking…' : 'Save & test', icon: Symbols.login, tone: ProcTone.green,
              onPressed: _busy == null ? _saveLogin : null),
          if (s.hasPassword) ProcButton(label: 'Remove login', icon: Symbols.delete, tone: ProcTone.coral,
              onPressed: _busy == null ? _forgetLogin : null),
        ]),
      ])),
    );
  }

  Widget _scoring(BuildContext context, NestSettings s) {
    final pal = context.pal;
    return ProcPanel(
      title: 'Relevance threshold', icon: Symbols.tune,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('A tender is relevant when its matched rules add up to at least the threshold. '
            'From ${s.maybeMin} up to it, it shows under "Maybe".',
            style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: pal.textMute)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 140, child: LabeledTextField(label: 'Threshold', controller: _threshold, keyboardType: TextInputType.number)),
          ProcButton(label: _busy == 'threshold' ? 'Saving…' : 'Save', icon: Symbols.save, onPressed: _busy == null ? _saveThreshold : null),
          ProcButton(label: _busy == 'recompute' ? 'Queued…' : 'Re-score all tenders', icon: Symbols.refresh, onPressed: _busy == null ? _recompute : null),
        ]),
      ])),
    );
  }

  Widget _rulesPanel(BuildContext context, NestSettings s) {
    final pal = context.pal;
    final rules = _rules ?? const [];
    final groups = <(String, String, String)>[
      ('DEVICES', 'Devices', 'keyword'), ('REAGENTS', 'Reagents', 'keyword'), ('CONSUMABLES', 'Consumables', 'keyword'),
      ('SERVICE', 'Service (counts only with a device term or a health tender)', 'keyword'),
      ('exclude', 'Excludes (never hide a tender that also has devices or reagents)', 'exclude'),
      ('health_subcategory', 'Health-sector sub-category', 'health_subcategory'),
      ('entity_hint', 'Buyer name hints', 'entity_hint'),
    ];
    return ProcPanel(
      title: 'Relevance rules', icon: Symbols.rule,
      trailing: s.canManage ? TextButton.icon(onPressed: () => _editRule(), icon: const Icon(Symbols.add, size: 14),
          label: const Text('Add rule', style: TextStyle(fontSize: 11.5))) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Row(children: [
            Icon(Symbols.local_hospital, size: 12, color: pal.textDim),
            const SizedBox(width: 6),
            Expanded(child: Text('Only counts for health tenders, so words like "equipment" or "reagents" '
                "don't pull in ICT, mining or water-lab tenders.",
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: pal.textDim))),
          ]),
        ),
        for (final (key, title, type) in groups) Builder(builder: (context) {
          final list = rules.where((r) => r.type == type && (type != 'keyword' || r.tag == key)).toList();
          if (list.isEmpty) return const SizedBox.shrink();
          final weight = list.first.weight;
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.5)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (type == 'keyword') ...[ProcTag(nestTagLabel(key), tone: nestTagTone(key), small: true), const SizedBox(width: 8)],
                Expanded(child: Text(type == 'keyword' && key != 'SERVICE' ? 'Keywords' : title,
                    style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
                Text('${list.length} · weight ${weight > 0 ? '+' : ''}$weight', style: procMono(context, size: 10.5)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in list) _RuleChip(rule: r, canManage: s.canManage, busy: _busy == 'rule-${r.id}',
                    onEdit: () => _editRule(r), onToggle: () => _toggleRule(r), onDelete: () => _deleteRule(r)),
              ]),
            ]),
          );
        }),
      ]),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.rule, required this.canManage, required this.busy, required this.onEdit, required this.onToggle, required this.onDelete});
  final NestRule rule;
  final bool canManage, busy;
  final VoidCallback onEdit, onToggle, onDelete;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final r = rule;
    final color = r.weight < 0 ? AppColors.coral : r.tag != null ? nestTagTone(r.tag!).fg(context) : pal.textMute;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: r.active ? color.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: r.active ? color.withValues(alpha: 0.35) : pal.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(r.term, style: AppTheme.bodySub.copyWith(fontSize: 11.5, color: r.active ? pal.text : pal.textDim,
            decoration: r.active ? null : TextDecoration.lineThrough)),
        if (r.context != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: nestContextLabel(r.context),
            child: Icon(Symbols.local_hospital, size: 11, color: r.active ? color : pal.textDim),
          ),
        ],
        if (busy) ...[const SizedBox(width: 6), const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))],
      ]),
    );
    if (!canManage) return chip;
    return PopupMenuButton<String>(
      tooltip: 'Edit, switch off or delete',
      onSelected: (v) => switch (v) { 'edit' => onEdit(), 'toggle' => onToggle(), _ => onDelete() },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'toggle', child: Text(r.active ? 'Switch off' : 'Switch on')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
      child: chip,
    );
  }
}

class _RuleForm extends StatefulWidget {
  const _RuleForm({this.rule});
  final NestRule? rule;
  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  static const _types = ['keyword', 'exclude', 'health_subcategory', 'entity_hint'];
  static const _defaultWeight = {'keyword': 10, 'exclude': -20, 'health_subcategory': 5, 'entity_hint': 2};

  late String _type = widget.rule?.type ?? 'keyword';
  late String? _tag = widget.rule?.tag ?? (widget.rule == null ? 'DEVICES' : null);
  late final _term = TextEditingController(text: widget.rule?.term);
  late final _weight = TextEditingController(text: '${widget.rule?.weight ?? 10}');
  late String _context = widget.rule?.context ?? 'always';
  bool _saving = false;

  @override
  void dispose() {
    _term.dispose();
    _weight.dispose();
    super.dispose();
  }

  String _typeLabel(String t) => switch (t) {
    'keyword' => 'Keyword (in description / sub-category)',
    'exclude' => 'Exclude (lowers the score)',
    'health_subcategory' => 'Sub-category code contains',
    'entity_hint' => 'Buyer name contains',
    _ => t,
  };

  Future<void> _save() async {
    final weight = int.tryParse(_weight.text.trim());
    if (_term.text.trim().length < 2 || weight == null) {
      showErrorToast(context, Exception('Enter the word or phrase and a whole-number weight.'));
      return;
    }
    setState(() => _saving = true);
    try {
      await NestService.instance.saveRule({
        'type': _type,
        'tag': _type == 'keyword' ? _tag : null,
        'term': _term.text.trim(),
        'weight': weight,
        'context': _type == 'keyword' && _context != 'always' ? _context : null,
      }, id: widget.rule?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProcDialog(
    title: widget.rule == null ? 'Add relevance rule' : 'Edit relevance rule',
    icon: Symbols.rule,
    width: 480,
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
    ],
    body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabeledDropdown<String>(
        label: 'Kind of rule',
        value: _type,
        items: _types,
        displayBuilder: _typeLabel,
        onChanged: (v) => setState(() {
          _type = v;
          if (widget.rule == null) _weight.text = '${_defaultWeight[v]}';
          if (v == 'keyword') _tag ??= 'DEVICES';
        }),
      ),
      if (_type == 'keyword') ...[
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Tag',
          value: _tag ?? 'DEVICES',
          items: nestTags,
          displayBuilder: nestTagLabel,
          onChanged: (v) => setState(() {
            _tag = v;
            if (widget.rule == null) _weight.text = v == 'CONSUMABLES' || v == 'SERVICE' ? '6' : '10';
          }),
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Counts',
          value: _context,
          items: const ['always', 'text', 'health'],
          displayBuilder: (v) => nestContextLabel(v == 'always' ? null : v),
          onChanged: (v) => setState(() => _context = v),
        ),
      ],
      const SizedBox(height: 12),
      LabeledTextField(label: 'Word or phrase', controller: _term,
          hint: _type == 'entity_hint' ? 'REFERRAL HOSPITAL' : _type == 'health_subcategory' ? 'HEALTH_SECTOR' : 'haematology analyser'),
      const SizedBox(height: 4),
      Text('Whole words, any case; a trailing s/es is allowed (monitor also finds monitors).',
          style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: context.pal.textDim)),
      const SizedBox(height: 12),
      SizedBox(width: 160, child: LabeledTextField(label: 'Weight', controller: _weight, keyboardType: const TextInputType.numberWithOptions(signed: true))),
    ]),
  );
}

/// How a keyword's context reads in the rules editor.
String nestContextLabel(String? context) => switch (context) {
  'text' => 'Only with medical/health wording in the tender',
  'health' => 'Only for a health tender or health buyer',
  _ => 'Always',
};
