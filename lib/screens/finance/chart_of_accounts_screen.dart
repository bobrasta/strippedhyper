import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/chart_of_account.dart';
import '../../models/expense.dart';
import '../../services/accounting_service.dart';
import '../../services/expense_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/phone_layout.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';

const _categoryOrder = ['asset', 'liability', 'equity', 'revenue', 'expense'];
const _categoryLabels = {
  'asset': 'Assets', 'liability': 'Liabilities', 'equity': 'Equity',
  'revenue': 'Revenue', 'expense': 'Expenses',
};

Color _categoryColor(String type) => switch (type) {
  'asset'     => AppColors.cyan,
  'liability' => AppColors.coral,
  'equity'    => AppColors.violet,
  'revenue' || 'expense' => AppColors.amber,
  _           => AppColors.textMute,
};

class ChartOfAccountsScreen extends StatefulWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  State<ChartOfAccountsScreen> createState() => _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState extends State<ChartOfAccountsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  List<ChartOfAccount> _accounts = [];
  List<LedgerEntry>    _journal  = [];
  List<AccountCategoryOption> _categories = [];
  List<ExpenseCategory> _expenseCategories = [];
  bool    _loading = true;
  bool    _hideZero = true;
  bool    _showCreate = false;
  bool    _showEdit = false;
  bool    _showCreateCategory = false;
  ExpenseCategory? _newCategoryParent;
  ExpenseCategory? _editCategory;
  String? _error;
  ChartOfAccount? _selected;
  final Set<String> _collapsed = {};
  final Set<int> _collapsedCategories = {};

  List<ChartOfAccount> get _expenseAccounts => _accounts.where((a) => a.categoryType == 'expense').toList();

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate — same reasoning as MachineListScreen's own
    // fix: show the last-known bundle instantly on a fresh mount (this
    // widget isn't kept alive across navigation), then quietly refresh.
    final cachedAccounts = AccountingService.cachedAccounts;
    if (cachedAccounts != null) {
      _accounts = cachedAccounts;
      _journal = AccountingService.cachedJournal ?? [];
      _categories = AccountingService.cachedCategories ?? [];
      _expenseCategories = ExpenseService.cachedCategories ?? [];
      _selected = cachedAccounts.where((a) => a.balance != 0).isNotEmpty
          ? cachedAccounts.firstWhere((a) => a.balance != 0)
          : (cachedAccounts.isNotEmpty ? cachedAccounts.first : null);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() {
      // Only show the blank/shimmer state when there's genuinely nothing
      // to show yet — a background refresh of an already-populated bundle
      // (or a return visit seeded from the cache above) updates silently.
      if (_accounts.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AccountingService.instance.accounts(),
        AccountingService.instance.journal(),
        AccountingService.instance.categories(),
        ExpenseService.instance.categories(),
      ]);
      if (!mounted) return;
      final accounts = results[0] as List<ChartOfAccount>;
      setState(() {
        _accounts = accounts;
        _journal  = results[1] as List<LedgerEntry>;
        _categories = results[2] as List<AccountCategoryOption>;
        _expenseCategories = results[3] as List<ExpenseCategory>;
        if (_selected != null) {
          final match = accounts.where((a) => a.id == _selected!.id);
          _selected = match.isNotEmpty ? match.first : null;
        }
        _selected ??= accounts.where((a) => a.balance != 0).isNotEmpty ? accounts.firstWhere((a) => a.balance != 0) : (accounts.isNotEmpty ? accounts.first : null);
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _deleteAccount(ChartOfAccount a) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: const Text('Delete account'),
      content: Text('Delete "${a.code} ${a.name}"? This only works if it has never been posted to.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Delete')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await AccountingService.instance.deleteAccount(a.id);
      if (mounted) { showSuccessToast(context, 'Account deleted.'); setState(() => _selected = null); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _toggleActive(ChartOfAccount a) async {
    try {
      await AccountingService.instance.updateAccount(a.id, {'status': a.status == 'active' ? 'inactive' : 'active'});
      if (mounted) showSuccessToast(context, a.status == 'active' ? 'Account deactivated.' : 'Account reactivated.');
      _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _deleteCategory(ExpenseCategory c) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: context.pal.surface1,
      title: const Text('Delete category'),
      content: Text('Delete "${c.name}"? This only works if it has no expenses recorded and no subcategories.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Delete')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await ExpenseService.instance.deleteCategory(c.id);
      if (mounted) { showSuccessToast(context, 'Category deleted.'); _load(); }
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
        final phone = isPhoneWidth(cst.maxWidth);
        final groupCount = _accounts.map((a) => a.categoryType).toSet().length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Chart of Accounts', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('${_accounts.length} accounts · $groupCount groups · balances as at ${formatDate(DateTime.now())}', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              // Phones: the toggle shrinks to an icon, "New account" to "New",
              // so the title keeps its width.
              if (phone)
                IconButton(
                  tooltip: _hideZero ? 'Show zero balances' : 'Hide zero balances',
                  onPressed: () => setState(() => _hideZero = !_hideZero),
                  icon: Icon(_hideZero ? Symbols.visibility : Symbols.visibility_off, size: 20),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: () => setState(() => _hideZero = !_hideZero),
                  icon: Icon(_hideZero ? Symbols.visibility : Symbols.visibility_off, size: 15),
                  label: Text(_hideZero ? 'Show zero balances' : 'Hide zero balances'),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.icon(onPressed: () => setState(() => _showCreate = true), icon: const Icon(Symbols.add, size: 16), label: Text(phone ? 'New' : 'New account')),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            margin: EdgeInsets.symmetric(horizontal: pad),
            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(AppColors.rLg), border: Border.all(color: context.pal.border)),
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.violet,
              unselectedLabelColor: context.pal.textMute,
              indicatorColor: AppColors.violet,
              indicatorWeight: 2,
              labelStyle: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
              unselectedLabelStyle: AppTheme.bodySm,
              tabs: const [Tab(text: 'Accounts'), Tab(text: 'Journal'), Tab(text: 'Categories')],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                // A background refresh failing while stale-but-valid cached
                // data is already showing shouldn't blow that away — only
                // the "genuinely nothing to show" case surfaces the error.
                : _error != null && _accounts.isEmpty
                    ? ErrorView(message: _error!, onRetry: _load)
                    : TabBarView(controller: _tab, children: [
                        _accountsTab(context, pad),
                        _JournalTab(entries: _journal, pad: pad),
                        _categoriesTab(context, pad),
                      ]),
          ),
        ]);
      }),
      if (_showCreate)
        _AccountFormDialog(
          categories: _categories,
          onClose: () => setState(() => _showCreate = false),
          onSaved: () { setState(() => _showCreate = false); _load(); },
        ),
      if (_showEdit && _selected != null)
        _AccountFormDialog(
          categories: _categories,
          existing: _selected,
          onClose: () => setState(() => _showEdit = false),
          onSaved: () { setState(() => _showEdit = false); _load(); },
        ),
      if (_showCreateCategory)
        _CategoryFormDialog(
          expenseAccounts: _expenseAccounts,
          parent: _newCategoryParent,
          onClose: () => setState(() { _showCreateCategory = false; _newCategoryParent = null; }),
          onSaved: () { setState(() { _showCreateCategory = false; _newCategoryParent = null; }); _load(); },
        ),
      if (_editCategory != null)
        _CategoryFormDialog(
          expenseAccounts: _expenseAccounts,
          existing: _editCategory,
          onClose: () => setState(() => _editCategory = null),
          onSaved: () { setState(() => _editCategory = null); _load(); },
        ),
    ]);
  }

  Widget _accountsTab(BuildContext context, double pad) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    final byType = <String, List<ChartOfAccount>>{};
    for (final a in _accounts) { byType.putIfAbsent(a.categoryType, () => []).add(a); }

    final list = SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final type in _categoryOrder)
          if (byType[type] != null) ...[
            _groupCard(context, type, byType[type]!),
            const SizedBox(height: 10),
          ],
      ]),
    );

    if (!wide) {
      return Padding(padding: EdgeInsets.all(pad), child: Column(children: [
        list,
        if (_selected != null) ...[const SizedBox(height: 16), _accountRail(context)],
      ]));
    }
    return Padding(
      padding: EdgeInsets.all(pad),
      // Materialize-style 12-col split: list m7, info panel m5 — the panel
      // scales with window width instead of sitting pinned at a fixed px.
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 7, child: list),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: _selected == null ? const SizedBox.shrink() : _accountRail(context)),
      ]),
    );
  }

  Widget _groupCard(BuildContext context, String type, List<ChartOfAccount> all) {
    final color = _categoryColor(type);
    final shown = _hideZero ? all.where((a) => a.balance != 0).toList() : all;
    final hiddenCount = all.length - shown.length;
    final total = all.fold<int>(0, (s, a) => s + a.balance);
    final collapsed = _collapsed.contains(type);

    return Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => collapsed ? _collapsed.remove(type) : _collapsed.add(type)),
          child: Container(
            height: 42, padding: const EdgeInsets.symmetric(horizontal: 15),
            color: context.pal.surface2,
            child: Row(children: [
              Icon(collapsed ? Symbols.chevron_right : Symbols.expand_more, size: 15, color: context.pal.textDim),
              const SizedBox(width: 8),
              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 9),
              Text(_categoryLabels[type]!, style: AppTheme.cardTitle.copyWith(fontSize: 13.5)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: context.pal.surface3, borderRadius: BorderRadius.circular(5)),
                child: Text('${all.length} accounts', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
              ),
              const Spacer(),
              Text(tshSigned(total), style: AppTheme.monoSm.copyWith(fontSize: 13, color: total < 0 ? AppColors.coral : context.pal.text)),
            ]),
          ),
        ),
        if (!collapsed) ...[
          ...shown.map((a) {
            final active = _selected?.id == a.id;
            return InkWell(
              onTap: () => setState(() => _selected = a),
              child: Container(
                height: 38, padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: active ? AppColors.violet.withValues(alpha: 0.08) : null,
                  border: Border(bottom: BorderSide(color: context.pal.divider)),
                ),
                child: Row(children: [
                  SizedBox(width: 44, child: Text(a.code, style: AppTheme.monoXs.copyWith(fontSize: 11, color: context.pal.textDim))),
                  Expanded(child: Text(a.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: a.balance == 0 ? context.pal.textDim : context.pal.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(tshSigned(a.balance), style: AppTheme.monoSm.copyWith(fontSize: 12, color: a.balance == 0 ? context.pal.textDim : (a.balance < 0 ? AppColors.coral : context.pal.text))),
                ]),
              ),
            );
          }),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: Text('$hiddenCount account${hiddenCount == 1 ? '' : 's'} with a zero balance hidden', style: AppTheme.bodySub.copyWith(fontSize: 11)),
            ),
        ],
      ]),
    );
  }

  Widget _accountRail(BuildContext context) {
    final a = _selected!;
    final entries = _journal.where((e) => e.accountCode == a.code).toList()
      ..sort((x, y) => (y.createdAt ?? DateTime(0)).compareTo(x.createdAt ?? DateTime(0)));
    final debits  = entries.where((e) => e.isDebit).fold<int>(0, (s, e) => s + e.amount);
    final credits = entries.where((e) => !e.isDebit).fold<int>(0, (s, e) => s + e.amount);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(a.code, style: AppTheme.monoXs.copyWith(color: context.pal.textDim)),
            const SizedBox(width: 8),
            Expanded(child: Text(a.name, style: AppTheme.cardTitle.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Text('${a.categoryLabel} · ${a.currency}${a.status != 'active' ? ' · inactive' : ''}', style: AppTheme.bodySub.copyWith(fontSize: 11)),
          const SizedBox(height: 12),
          Text(tshSigned(a.balance), style: AppTheme.kpiValue.copyWith(fontSize: 24, color: a.balance < 0 ? AppColors.coral : context.pal.text)),
          const SizedBox(height: 13),
          Row(children: [
            _railStat('Debits', tshFromDouble(debits), AppColors.cyan),
            const SizedBox(width: 18),
            _railStat('Credits', tshFromDouble(credits), AppColors.coral),
            const Spacer(),
            _railStat('Postings', '${entries.length}', context.pal.text, alignEnd: true),
          ]),
          const SizedBox(height: 13),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => setState(() => _showEdit = true),
              icon: const Icon(Symbols.edit, size: 14), label: const Text('Edit'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _toggleActive(a),
              icon: Icon(a.status == 'active' ? Symbols.visibility_off : Symbols.visibility, size: 14),
              label: Text(a.status == 'active' ? 'Deactivate' : 'Reactivate'),
            )),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _deleteAccount(a),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.coral, side: BorderSide(color: AppColors.coral.withValues(alpha: 0.5)), padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Icon(Symbols.delete, size: 15),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Icon(Symbols.history, size: 13, color: AppColors.violet),
        const SizedBox(width: 8),
        Text('ACCOUNT LEDGER', style: AppTheme.labelCaps.copyWith(fontSize: 10.5)),
        const SizedBox(width: 8),
        Expanded(child: Container(width: double.infinity, height: 1, color: context.pal.divider)),
      ]),
      const SizedBox(height: 9),
      Container(
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        clipBehavior: Clip.antiAlias,
        child: entries.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No recent postings for this account.', style: AppTheme.bodySub.copyWith(fontSize: 12))))
            : Column(children: entries.take(10).map((e) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((e.description?.isNotEmpty ?? false) ? e.description! : '—', style: AppTheme.bodySm.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text([if (e.reference != null) e.reference!, if (e.createdAt != null) formatDate(e.createdAt!)].join(' · '), style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
                  ])),
                  Text('${e.isDebit ? '' : '-'}${tshFromDouble(e.amount)}', style: AppTheme.monoXs.copyWith(fontSize: 11.5, color: e.isDebit ? AppColors.cyan : AppColors.coral)),
                ]),
              )).toList()),
      ),
    ]);
  }

  Widget _railStat(String label, String value, Color color, {bool alignEnd = false}) => Column(
    crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTheme.labelCaps.copyWith(fontSize: 9)),
      const SizedBox(height: 3),
      Text(value, style: AppTheme.monoSm.copyWith(fontSize: 13.5, color: color)),
    ],
  );

  Widget _categoriesTab(BuildContext context, double pad) {
    final topLevel = _expenseCategories.where((c) => c.parentId == null).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final byParent = <int, List<ExpenseCategory>>{};
    for (final c in _expenseCategories) {
      if (c.parentId != null) {
        (byParent[c.parentId!] ??= []).add(c);
      }
    }
    for (final list in byParent.values) { list.sort((a, b) => a.name.compareTo(b.name)); }

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(
            '${_expenseCategories.length} categories · ${topLevel.length} top-level',
            style: AppTheme.bodySub.copyWith(fontSize: 12),
          )),
          FilledButton.icon(
            onPressed: () => setState(() { _newCategoryParent = null; _showCreateCategory = true; }),
            icon: const Icon(Symbols.add, size: 16),
            label: const Text('New category'),
          ),
        ]),
        const SizedBox(height: 12),
        if (topLevel.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
            child: Text('No expense categories yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)),
          )
        else
          Container(
            decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final parent in topLevel) _categoryTreeRow(context, parent, byParent[parent.id] ?? const []),
            ]),
          ),
      ]),
    );
  }

  Widget _categoryTreeRow(BuildContext context, ExpenseCategory parent, List<ExpenseCategory> children) {
    final collapsed = _collapsedCategories.contains(parent.id);
    return Column(children: [
      InkWell(
        onTap: children.isEmpty ? null : () => setState(() {
          collapsed ? _collapsedCategories.remove(parent.id) : _collapsedCategories.add(parent.id);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Icon(children.isEmpty ? Symbols.remove : (collapsed ? Symbols.chevron_right : Symbols.expand_more), size: 15, color: context.pal.textDim),
            const SizedBox(width: 8),
            Expanded(child: Text(parent.name, style: AppTheme.bodyStrong.copyWith(fontSize: 13))),
            if (children.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(color: context.pal.surface3, borderRadius: BorderRadius.circular(5)),
                child: Text('${children.length} sub', style: AppTheme.monoXs.copyWith(fontSize: 10, color: context.pal.textDim)),
              ),
            SizedBox(
              width: 160,
              child: Text(
                [if (parent.accountCode != null) parent.accountCode!, if (parent.accountName != null) parent.accountName!].join(' '),
                style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: context.pal.textDim),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 6),
            _iconBtn(context, Symbols.add, 'New subcategory', () => setState(() { _newCategoryParent = parent; _showCreateCategory = true; })),
            _iconBtn(context, Symbols.edit, 'Edit', () => setState(() => _editCategory = parent)),
            _iconBtn(context, Symbols.delete, 'Delete', () => _deleteCategory(parent), color: AppColors.coral),
          ]),
        ),
      ),
      if (!collapsed)
        ...children.map((c) => Container(
          padding: const EdgeInsets.only(left: 44, right: 15, top: 8, bottom: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Icon(Symbols.subdirectory_arrow_right, size: 13, color: context.pal.textDim),
            const SizedBox(width: 8),
            Expanded(child: Text(c.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
            _iconBtn(context, Symbols.edit, 'Edit', () => setState(() => _editCategory = c)),
            _iconBtn(context, Symbols.delete, 'Delete', () => _deleteCategory(c), color: AppColors.coral),
          ]),
        )),
    ]);
  }

  Widget _iconBtn(BuildContext context, IconData icon, String tooltip, VoidCallback onTap, {Color? color}) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 15, color: color ?? context.pal.textDim)),
    ),
  );
}

// ── New / edit account dialog ────────────────────────────────────────────────

class _AccountFormDialog extends StatefulWidget {
  const _AccountFormDialog({required this.categories, this.existing, required this.onClose, required this.onSaved});
  final List<AccountCategoryOption> categories;
  final ChartOfAccount? existing;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<_AccountFormDialog> {
  late final _codeCtrl = TextEditingController(text: widget.existing?.code ?? '');
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _balanceCtrl = TextEditingController(text: widget.existing != null ? '' : '0');
  late String _currency = widget.existing?.currency ?? 'TZS';
  int? _categoryId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null && widget.categories.isNotEmpty) {
      final match = widget.categories.where((c) => c.type == widget.existing!.categoryType);
      _categoryId = match.isNotEmpty ? match.first.id : widget.categories.first.id;
    } else if (widget.categories.isNotEmpty) {
      _categoryId = widget.categories.first.id;
    }
  }

  @override
  void dispose() { _codeCtrl.dispose(); _nameCtrl.dispose(); _balanceCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    if (_codeCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Code and name are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      if (_isEdit) {
        await AccountingService.instance.updateAccount(widget.existing!.id, {
          'code': _codeCtrl.text.trim(), 'name': _nameCtrl.text.trim(), 'currency': _currency,
        });
      } else {
        await AccountingService.instance.createAccount({
          'code': _codeCtrl.text.trim(), 'name': _nameCtrl.text.trim(),
          'category_id': _categoryId, 'currency': _currency,
          'opening_balance': int.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0,
        });
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 440,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.account_balance, size: 18, color: AppColors.violet),
                const SizedBox(width: 10),
                Expanded(child: Text(_isEdit ? 'Edit Account' : 'New Account', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                  ),
                ],
                Row(children: [
                  SizedBox(width: 110, child: _field('Code', _codeCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Name', _nameCtrl)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  if (!_isEdit) ...[
                    Expanded(child: _dropdown('Category', _categoryId, widget.categories
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))).toList(),
                        (v) => setState(() => _categoryId = v))),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: _dropdown('Currency', _currency,
                      const ['TZS', 'USD', 'EUR'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      (v) => setState(() => _currency = v ?? 'TZS'))),
                ]),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  _field('Opening Balance (TSh)', _balanceCtrl, number: true),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isEdit ? 'Save' : 'Create', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );

  Widget _field(String label, TextEditingController ctrl, {bool number = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    LabeledTextField(label: label, controller: ctrl, keyboardType: number ? TextInputType.number : TextInputType.text),
  ]);

  Widget _dropdown<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<T>(
      value: value,
      items: items,
      onChanged: onChanged,
    ),
  ]);
}

// ── New / edit expense category dialog ───────────────────────────────────────

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({required this.expenseAccounts, this.parent, this.existing, required this.onClose, required this.onSaved});
  final List<ChartOfAccount> expenseAccounts;
  final ExpenseCategory? parent;   // fixed parent, for "new subcategory"
  final ExpenseCategory? existing; // edit mode
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  int? _accountId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  bool get _isSubcategory => widget.parent != null;

  @override
  void initState() {
    super.initState();
    if (!_isEdit && !_isSubcategory && widget.expenseAccounts.isNotEmpty) {
      _accountId = widget.expenseAccounts.first.id;
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (!_isEdit && !_isSubcategory && _accountId == null) {
      setState(() => _error = 'Choose a GL account.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      if (_isEdit) {
        await ExpenseService.instance.updateCategoryDetails(widget.existing!.id, {'name': _nameCtrl.text.trim()});
      } else if (_isSubcategory) {
        await ExpenseService.instance.createCategory({'name': _nameCtrl.text.trim(), 'parent_id': widget.parent!.id});
      } else {
        await ExpenseService.instance.createCategory({'name': _nameCtrl.text.trim(), 'account_id': _accountId});
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [BoxShadow(color: Color(0x70000000), blurRadius: 60, offset: Offset(0, 20))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Symbols.category, size: 18, color: AppColors.violet),
                const SizedBox(width: 10),
                Text(
                  _isEdit ? 'Edit Category' : (_isSubcategory ? 'New Subcategory' : 'New Category'),
                  style: AppTheme.bodyStrong,
                ),
                const Spacer(),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                  ),
                ],
                if (_isSubcategory) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Under: ${widget.parent!.name}', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],
                _field('Name', _nameCtrl),
                if (!_isEdit && !_isSubcategory) ...[
                  const SizedBox(height: 14),
                  _dropdown('GL Account', _accountId, widget.expenseAccounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.code} ${a.name}', overflow: TextOverflow.ellipsis))).toList(),
                      (v) => setState(() => _accountId = v)),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(onTap: widget.onClose,
                  child: Container(height: 38,
                    decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text('Cancel', style: AppTheme.bodySm))))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(onTap: _save,
                  child: Container(height: 38,
                    decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isEdit ? 'Save' : 'Create', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );

  Widget _field(String label, TextEditingController ctrl) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    LabeledTextField(label: label, controller: ctrl),
  ]);

  Widget _dropdown<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<T>(
      value: value,
      items: items,
      onChanged: onChanged,
    ),
  ]);
}

class _JournalTab extends StatelessWidget {
  const _JournalTab({required this.entries, required this.pad});
  final List<LedgerEntry> entries;
  final double pad;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(child: Text('No postings yet', style: TextStyle(color: context.pal.textMute)));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(90),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2.5),
            3: FlexColumnWidth(1.3),
            4: FlexColumnWidth(1.3),
            5: FlexColumnWidth(1.5),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.border))),
              children: ['Account', 'Description', 'Reference', 'Debit', 'Credit', 'Date'].map((h) =>
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(h.toUpperCase(), style: AppTheme.monoXs.copyWith(fontWeight: FontWeight.w500)),
                )).toList(),
            ),
            ...entries.asMap().entries.map((e) {
              final t = e.value;
              return TableRow(
                decoration: BoxDecoration(
                  border: e.key == entries.length - 1 ? null : Border(bottom: BorderSide(color: context.pal.divider)),
                ),
                children: [
                  _Cell(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.accountCode, style: AppTheme.monoXs.copyWith(color: context.pal.textMute)),
                    Text(t.accountName, style: AppTheme.bodySub.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis),
                  ])),
                  _Cell(child: Text(t.description ?? '—', style: AppTheme.bodySm.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis)),
                  _Cell(child: Text(t.reference ?? '—', style: AppTheme.monoXs.copyWith(color: context.pal.textMute))),
                  _Cell(child: Text(t.isDebit ? tshFromDouble(t.amount) : '—',
                      style: AppTheme.monoSm.copyWith(fontSize: 12, color: AppColors.cyan))),
                  _Cell(child: Text(!t.isDebit ? tshFromDouble(t.amount) : '—',
                      style: AppTheme.monoSm.copyWith(fontSize: 12, color: AppColors.coral))),
                  _Cell(child: Text(t.createdAt != null ? formatDate(t.createdAt!) : '—', style: AppTheme.monoXs)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: child,
  );
}
