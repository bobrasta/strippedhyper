import 'package:flutter/material.dart';
import '../../models/notification_template.dart';
import '../../services/notification_template_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';

// Lets an admin change what a notification actually says — title/body
// wording only, per (event, audience) template — without a deploy. See
// NotificationTemplateService on the backend: every AppNotification the app
// sends is rendered from one of these rows, with {placeholder} tokens
// substituted at send time.
class NotificationTemplatesScreen extends StatefulWidget {
  const NotificationTemplatesScreen({super.key});

  @override
  State<NotificationTemplatesScreen> createState() => _NotificationTemplatesScreenState();
}

class _NotificationTemplatesScreenState extends State<NotificationTemplatesScreen> {
  List<NotificationTemplate> _templates = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known list immediately, then
    // quietly refresh — see MachineService's own doc comment for the full
    // reasoning.
    final cached = NotificationTemplateService.cachedList;
    if (cached != null) { _templates = cached; _loading = false; }
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() {
      if (_templates.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final templates = await NotificationTemplateService.instance.list();
      if (!mounted) return;
      setState(() { _templates = templates; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<NotificationTemplate> get _filtered => _search.isEmpty
      ? _templates
      : _templates.where((t) =>
          t.templateKey.toLowerCase().contains(_search) ||
          t.titleTemplate.toLowerCase().contains(_search) ||
          t.bodyTemplate.toLowerCase().contains(_search) ||
          (t.description ?? '').toLowerCase().contains(_search)).toList();

  Map<String, List<NotificationTemplate>> get _grouped {
    final map = <String, List<NotificationTemplate>>{};
    for (final t in _filtered) {
      map.putIfAbsent(t.category, () => []).add(t);
    }
    return map;
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
              Text('Notification Wording', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
              const SizedBox(height: 3),
              Text('Edit what an in-app notification says — changes apply immediately, no deploy needed', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ])),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
          child: SearchField(hint: 'Search by key, title or wording…', controller: _searchCtrl),
        ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null && _templates.isEmpty
                ? ErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: EdgeInsets.all(pad),
                    children: _grouped.entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entry.key.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 10.5, color: AppColors.violet)),
                        const SizedBox(height: 8),
                        ...entry.value.map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TemplateCard(template: t),
                        )),
                      ]),
                    )).toList(),
                  )),
      ]);
    });
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({required this.template});
  final NotificationTemplate template;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  late final TextEditingController _titleCtrl = TextEditingController(text: widget.template.titleTemplate);
  late final TextEditingController _bodyCtrl = TextEditingController(text: widget.template.bodyTemplate);
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_markDirty);
    _bodyCtrl.addListener(_markDirty);
  }

  void _markDirty() { if (!_dirty) setState(() => _dirty = true); }

  @override
  void dispose() { _titleCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  List<String> get _placeholders {
    final matches = RegExp(r'\{([a-z_]+)\}').allMatches('${_titleCtrl.text} ${_bodyCtrl.text}');
    return matches.map((m) => m.group(1)!).toSet().toList()..sort();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await NotificationTemplateService.instance.update(widget.template.id, title: _titleCtrl.text, body: _bodyCtrl.text);
      if (mounted) { setState(() { _dirty = false; _saving = false; }); showSuccessToast(context, 'Saved.'); }
    } catch (e) {
      if (mounted) { setState(() => _saving = false); showErrorToast(context, e); }
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(widget.template.description ?? widget.template.templateKey,
            style: AppTheme.bodySub.copyWith(fontSize: 11.5))),
        Text(widget.template.templateKey, style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
      ]),
      const SizedBox(height: 10),
      LabeledTextField(label: 'Title', controller: _titleCtrl),
      const SizedBox(height: 8),
      LabeledTextField(label: 'Message', controller: _bodyCtrl, maxLines: 2),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (_placeholders.isNotEmpty) Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: _placeholders.map((p) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
          child: Text('{$p}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: AppColors.violet)),
        )).toList()))
        else const Spacer(),
        const SizedBox(width: 10),
        SizedBox(height: 32, child: FilledButton(
          onPressed: _dirty && !_saving ? _save : null,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16), textStyle: AppTheme.bodySm.copyWith(fontSize: 12)),
          child: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        )),
      ]),
    ]),
  );
}
