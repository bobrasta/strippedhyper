import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userNameNotifier, userRoleNotifier, userLocationNotifier, roleDisplayName, allowedScreenKeys, can;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'current_user_avatar.dart';
import 'email_badge.dart';
import '../chat/chat_dock.dart' show ChatNavBadge;
import '../../theme/app_palette.dart';

class NavDestination {
  const NavDestination({
    required this.icon,
    required this.label,
    required this.key,
    this.count,
  });
  final IconData icon;
  final String label;
  final String key;
  final String? count;
}

const _operations = [
  NavDestination(icon: Symbols.space_dashboard,         label: 'Dashboard',  key: 'dashboard'),
  NavDestination(icon: Symbols.fact_check,              label: 'Approvals', key: 'approvals'),
  // 'inventory' key triggers the expandable group — rendered separately below
  NavDestination(icon: Symbols.inventory_2,             label: 'Inventory',  key: 'inventory'),
  // Suppliers sits outside both the Inventory group and Tendering &
  // Logistics: stores and the shipments department both use it, and it
  // appears once. Key kept as inventory_suppliers (search/deep links).
  NavDestination(icon: Symbols.business,                label: 'Suppliers',  key: 'inventory_suppliers'),
  // Task-assignment/availability board — Operations' job, not HR's.
  NavDestination(icon: Symbols.badge,                   label: 'Staff',      key: 'staff'),
  // Every role can request their own leave — this is personal self-service,
  // not an HR-department tool, so it doesn't belong under the HR section
  // header even though HR also manages the approvals for it separately.
  NavDestination(icon: Symbols.event,                   label: 'My Leave',   key: 'my_leave'),
  // Everyone's own expenses, sent to their manager for approval (2026-10-24).
  NavDestination(icon: Symbols.receipt_long,            label: 'My Expenses', key: 'my_expenses'),
  // Own per-diem/travel-plan submissions.
  NavDestination(icon: Symbols.flight_takeoff,          label: 'My Travel Plans', key: 'my_travel_plans'),
];
const _business = [
  NavDestination(icon: Symbols.payments,                label: 'Revenue',    key: 'revenue'),
  // 'purchases' key triggers the expandable group (Clickhuduma's Purchases
  // menu, just above Sales) — rendered separately below.
  NavDestination(icon: Symbols.shopping_cart,           label: 'Purchases',  key: 'purchases'),
  // 'sales' key triggers the expandable group — rendered separately below
  NavDestination(icon: Symbols.trending_up,             label: 'Sales',      key: 'sales'),
  // Quotations on its own, for engineers who prepare them without the Sales
  // menu (2026-10-23); hidden for anyone who has the Sales group.
  NavDestination(icon: Symbols.request_quote,           label: 'Quotations', key: 'quotations'),
  // 'finance' key triggers the expandable group — rendered separately below
  NavDestination(icon: Symbols.account_balance,         label: 'Finance',    key: 'finance'),
  // 'tendering' key triggers the expandable group for the Tendering,
  // Compliance & Delivering Logistics department — rendered separately
  // below, shown when any of its children (_tenderingChildren) is allowed.
  NavDestination(icon: Symbols.gavel,                   label: 'Tendering & Logistics', key: 'tendering'),
  NavDestination(icon: Symbols.groups,                  label: 'Customers',  key: 'customers'),
  NavDestination(icon: Symbols.mail,                    label: 'Email',      key: 'email'),
  NavDestination(icon: Symbols.forum,                   label: 'Chats',      key: 'chats'),
  NavDestination(icon: Symbols.groups_3,                label: 'Meetings',   key: 'meetings'),
  NavDestination(icon: Symbols.contract_edit,           label: 'Letters',    key: 'letters'),
];
const _hr = [
  // No standalone "HR Dashboard" item — its content is what the main
  // Dashboard nav entry shows for the hr role (see UnifiedDashboardScreen's
  // department delegation). One dashboard, not two.
  // Personal-info directory — position, statutory IDs, contracts,
  // discipline, career progression. Not the operational task-board above.
  NavDestination(icon: Symbols.badge,                   label: 'Directory',  key: 'hr_directory'),
  NavDestination(icon: Symbols.person_search,           label: 'Recruitment', key: 'hr_recruitment'),
  NavDestination(icon: Symbols.calendar_month,          label: 'Leave Calendar', key: 'hr_leave_calendar'),
  NavDestination(icon: Symbols.fingerprint,             label: 'Attendance', key: 'hr_attendance'),
  NavDestination(icon: Symbols.payments,                label: 'Payroll',    key: 'hr_payroll'),
  NavDestination(icon: Symbols.how_to_reg,              label: 'HR Approvals', key: 'hr_approvals'),
  NavDestination(icon: Symbols.assessment,              label: 'Reports',    key: 'hr_reports'),
  NavDestination(icon: Symbols.settings_applications,   label: 'HR Settings', key: 'hr_settings'),
];

// Sub-items shown when Sales group is expanded. No "Dashboard" row here —
// tapping the "Sales" parent header already lands on sales_dashboard (see
// _SalesGroup below), and the main Dashboard nav entry shows the same
// screen too (UnifiedDashboardScreen's department delegation) — a third
// entry for the identical screen would be the same duplication we removed
// from HR.
// Order set by the user (2026-10-02), Clickhuduma style: All sales first,
// then add/list pairs for sales, drafts and quotations.
const _salesChildren = [
  (key: 'sales_history',       icon: Symbols.point_of_sale,  label: 'All sales'),
  (key: 'sales_new',           icon: Symbols.add_shopping_cart, label: 'Add sale'),
  (key: 'sales_new_draft',     icon: Symbols.edit_note,      label: 'Add draft'),
  (key: 'sales_drafts',        icon: Symbols.draft,          label: 'List drafts'),
  (key: 'sales_new_quotation', icon: Symbols.note_add,       label: 'Add quotation'),
  (key: 'sales_quotations',    icon: Symbols.request_quote,  label: 'List quotations'),
  (key: 'sales_leads',       icon: Symbols.trending_up,   label: 'Leads'),
  // Sales Orders hidden from the menu for now (user, 2026-09-30); the screen
  // still exists and notifications/search can still open it.
  // (key: 'sales_orders',      icon: Symbols.shopping_cart, label: 'Sales Orders'),
  (key: 'sales_invoices',    icon: Symbols.receipt_long,  label: 'Invoices'),
  // sales.create_subordinate_user-gated — filtered out below for anyone who
  // doesn't hold it (a plain 'sales' rep), so these only ever appear for a
  // sales_manager building their own team / reviewing team performance.
  (key: 'sales_team',        icon: Symbols.group,         label: 'Team'),
  (key: 'team_performance',  icon: Symbols.bar_chart,     label: 'Team Performance'),
];
// Sub-items of Purchases (user, 2026-10-26: Clickhuduma's Purchases menu).
// A purchase is a purchase order here, so Clickhuduma's separate "Purchase
// Order" row would list the same records again — List purchases covers both.
const _purchasesChildren = [
  (key: 'purchases_list',    icon: Symbols.list_alt,       label: 'List purchases'),
  (key: 'purchases_new',     icon: Symbols.add_circle,     label: 'Add purchase'),
  (key: 'purchases_returns', icon: Symbols.undo,           label: 'List purchase returns'),
];

// Sub-items shown when Finance group is expanded. No "Dashboard" row — same
// reasoning as _salesChildren above.
const _financeChildren = [
  (key: 'finance_receivables', icon: Symbols.credit_score,       label: 'Credit & Receivables'),
  (key: 'finance_expenses',  icon: Symbols.receipt_long,          label: 'Expenses'),
  (key: 'finance_creditors', icon: Symbols.account_balance,       label: 'Creditors'),
  (key: 'finance_bills',     icon: Symbols.account_balance_wallet, label: 'Supplier Invoices'),
  (key: 'finance_ledger',    icon: Symbols.book,                  label: 'Chart of Accounts'),
  (key: 'finance_reports',   icon: Symbols.assessment,            label: 'Reports'),
  (key: 'finance_bank_rec',  icon: Symbols.sync_alt,              label: 'Bank Reconciliation'),
];

// Sub-items of the Tendering, Compliance & Delivering Logistics department.
// Each child keeps its own gate: shipments = screens.shipments (Section 18 —
// procurement/logistics staff; CTO, MD, Sales Manager read-only);
// tenders/tender_devices = screens.tenders (Section 19 — procurement staff,
// CTO read-only, admin tier); vendor_fees =
// Section 16, which finance also holds (it verifies receipts), so a finance
// user sees the group with just that one row.
const _tenderingChildren = [
  (key: 'shipments',         icon: Symbols.flight_land,    label: 'Shipments'),
  (key: 'nest_tenders',      icon: Symbols.travel_explore, label: 'NeST Tenders'),
  (key: 'tenders',           icon: Symbols.gavel,          label: 'Tenders & Contracts'),
  (key: 'tender_devices',    icon: Symbols.verified,       label: 'Device Registrations'),
  (key: 'tmda_permits',      icon: Symbols.verified_user,  label: 'TMDA Permits'),
  (key: 'clearing_fees',     icon: Symbols.receipt_long,   label: 'Clearing Fees'),
  (key: 'vendor_fees',       icon: Symbols.local_shipping, label: 'Vendors & Delivery'),
  (key: 'shipment_settings', icon: Symbols.tune,           label: 'Module Settings'),
];

const _system = [
  NavDestination(icon: Symbols.trending_up,             label: 'My Performance', key: 'my_performance'),
  // Who did what per person (quotations, invoices from them, installations,
  // services) — the Director's record for gauging bonuses.
  NavDestination(icon: Symbols.workspace_premium,       label: 'Staff Contributions', key: 'contributions'),
  NavDestination(icon: Symbols.assessment,              label: 'Reports',       key: 'reports'),
  NavDestination(icon: Symbols.notifications,           label: 'Notifications', key: 'notifications'),
  NavDestination(icon: Symbols.download,                label: 'Downloads',     key: 'downloads'),
  NavDestination(icon: Symbols.badge,                   label: 'Delegations',   key: 'delegations'),
  NavDestination(icon: Symbols.chat_bubble,             label: 'Notification Wording', key: 'notification_templates'),
  NavDestination(icon: Symbols.history,                 label: 'Activity Log',  key: 'activity_log'),
  NavDestination(icon: Symbols.settings,                label: 'Settings',      key: 'settings'),
];

// Sub-items shown when Inventory group is expanded
const _inventoryChildren = [
  (key: 'inventory_items',        icon: Symbols.list_alt,            label: 'Items'),
  (key: 'inventory_movements',    icon: Symbols.swap_vert,           label: 'Movements'),
  (key: 'inventory_requisitions', icon: Symbols.assignment,          label: 'Requisitions'),
  (key: 'inventory_orders',       icon: Symbols.receipt_long,        label: 'Purchase Orders'),
  (key: 'inventory_locations',    icon: Symbols.warehouse,           label: 'Locations'),
];

/// Human label + icon for a screen key, as the menu names it — used by the
/// mobile top bar (page title) and bottom tab bar. Keys outside the menu
/// (detail pages, group parents) get their nearest sensible name.
({String label, IconData icon})? navEntryFor(String key) {
  const aliases = {
    'sales': 'Leads', 'sales_dashboard': 'Sales', 'inventory': 'Items', 'purchases': 'Purchases',
    'finance_dashboard': 'Finance',
    'sales_orders': 'Sales Orders', 'hr_dashboard': 'HR',
  };
  if (aliases.containsKey(key)) {
    final base = navEntryFor(switch (key) {
      'sales' => 'sales_leads',
      'inventory' => 'inventory_items',
      'sales_orders' => 'sales_invoices',
      'hr_dashboard' => 'hr_directory',
      'sales_dashboard' => 'sales',
      'purchases' => 'purchases_list',
      _ => 'finance',
    });
    return (label: aliases[key]!, icon: base?.icon ?? Symbols.apps);
  }
  for (final d in [..._operations, ..._business, ..._hr, ..._system]) {
    if (d.key == key) return (label: d.label, icon: d.icon);
  }
  for (final c in [..._purchasesChildren, ..._salesChildren, ..._financeChildren, ..._tenderingChildren, ..._inventoryChildren]) {
    if (c.key == key) return (label: c.label, icon: c.icon);
  }
  return null;
}

/// Every menu screen with its menu group, for the top-bar search's "Pages".
/// Callers filter by what the user may open.
List<({String key, String label, IconData icon, String group})> allNavPages() {
  final out = <({String key, String label, IconData icon, String group})>[];
  final seen = <String>{};
  void addAll(String group, Iterable<({String key, String label, IconData icon})> items) {
    for (final i in items) {
      if (seen.add(i.key)) out.add((key: i.key, label: i.label, icon: i.icon, group: group));
    }
  }
  ({String key, String label, IconData icon}) d(NavDestination n) => (key: n.key, label: n.label, icon: n.icon);
  addAll('Sales', _salesChildren);
  addAll('Purchases', _purchasesChildren);
  addAll('Finance', _financeChildren);
  addAll('Tendering & Logistics', _tenderingChildren);
  addAll('Inventory', _inventoryChildren);
  addAll('Operations', _operations.map(d));
  addAll('Business', _business.map(d));
  addAll('HR', _hr.map(d));
  addAll('System', _system.map(d));
  return out;
}

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.activeKey,
    required this.onSelect,
    this.width = 232,
  });

  final String activeKey;
  final ValueChanged<String> onSelect;
  final double width;


  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: userRoleNotifier,
      builder: (_, role, _) {
        final allowed = allowedScreenKeys(role);
        bool canShow(String key) {
          // Downloads is a purely local file list (whatever's already on
          // this machine's disk) — not gated by server permissions, same
          // as every role already seeing Notifications/Settings.
          if (key == 'downloads') return true;
          // My Performance is deliberately universal — every role benchmarks
          // their own real activity (tasks always; sales/field sections only
          // when that role actually has any), not gated by a screens.*
          // permission like module-specific pages are.
          if (key == 'my_performance') return true;
          if (key == 'quotations') return allowed != null && allowed.contains('quotations') && !allowed.contains('sales');
          if (allowed == null) return true;
          if (key == 'inventory_suppliers') return allowed.contains('inventory') || allowed.contains('shipments');
          if (key.startsWith('inventory_')) return allowed.contains('inventory');
          if (key.startsWith('sales_'))     return allowed.contains('sales');
          if (key.startsWith('purchases_')) return allowed.contains('purchases');
          if (key.startsWith('finance_'))   return allowed.contains('finance');
          if (key == 'tender_devices' || key == 'nest_tenders') return allowed.contains('tenders');
          if (const {'tmda_permits', 'clearing_fees', 'shipment_settings'}.contains(key)) return allowed.contains('shipments');
          if (key == 'tendering')           return _tenderingChildren.any((c) => canShow(c.key));
          return allowed.contains(key);
        }

        List<NavDestination> filter(List<NavDestination> items) =>
            items.where((d) => canShow(d.key)).toList();

        final ops = filter(_operations);
        final hr  = filter(_hr);
        final biz = filter(_business);
        final sys = filter(_system);

        return Container(
          width: width,
          decoration: BoxDecoration(
            color: context.pal.sidebarBg,
            border: Border(right: BorderSide(color: context.pal.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ops.isNotEmpty) ...[
                        _SectionLabel('Operations'),
                        ...ops.map((d) => d.key == 'inventory'
                          ? _InventoryGroup(
                              activeKey: activeKey,
                              onSelect: onSelect,
                            )
                          : _NavItem(d, active: d.key == activeKey, onTap: () => onSelect(d.key))),
                      ],
                      if (hr.isNotEmpty) ...[
                        _SectionLabel('HR'),
                        ...hr.map((d) => _NavItem(d, active: d.key == activeKey, onTap: () => onSelect(d.key))),
                      ],
                      if (biz.isNotEmpty) ...[
                        _SectionLabel('Business'),
                        ...biz.map((d) => switch (d.key) {
                          'sales'   => _SalesGroup(activeKey: activeKey, onSelect: onSelect),
                          'finance' => _FinanceGroup(activeKey: activeKey, onSelect: onSelect),
                          'purchases' => _NavGroup(
                              icon: Symbols.shopping_cart,
                              label: 'Purchases',
                              children: _purchasesChildren,
                              activeKey: activeKey,
                              onSelect: onSelect,
                            ),
                          'tendering' => _NavGroup(
                              icon: Symbols.gavel,
                              label: 'Tendering & Logistics',
                              tooltip: 'Tendering, Compliance & Delivering Logistics',
                              children: _tenderingChildren.where((c) => canShow(c.key)).toList(),
                              activeKey: activeKey,
                              onSelect: onSelect,
                            ),
                          _         => _NavItem(d, active: d.key == activeKey, onTap: () => onSelect(d.key)),
                        }),
                      ],
                      if (sys.isNotEmpty) ...[
                        _SectionLabel('System'),
                        ...sys.map((d) => _NavItem(d, active: d.key == activeKey, onTap: () => onSelect(d.key))),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              // The avatar and name open the user's own profile (Settings → Profile).
              InkWell(onTap: () => onSelect('settings'), child: _SidebarFooter()),
            ],
          ),
        );
      },
    );
  }
}

// ── Expandable Inventory group ─────────────────────────────────────────────────

class _InventoryGroup extends StatefulWidget {
  const _InventoryGroup({required this.activeKey, required this.onSelect});
  final String activeKey;
  final ValueChanged<String> onSelect;

  @override
  State<_InventoryGroup> createState() => _InventoryGroupState();
}

class _InventoryGroupState extends State<_InventoryGroup> {
  // Suppliers keeps its inventory_ key but lives outside this group.
  bool _ownsKey(String k) => k.startsWith('inventory_') && k != 'inventory_suppliers';
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = _ownsKey(widget.activeKey);
  }

  @override
  void didUpdateWidget(_InventoryGroup old) {
    super.didUpdateWidget(old);
    if (_ownsKey(widget.activeKey)) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (_open) {
              setState(() => _open = false);
            } else {
              setState(() => _open = true);
              widget.onSelect('inventory_items');
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _open ? context.pal.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                if (_open)
                  Positioned(
                    left: -22, top: 4, bottom: 4,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppColors.teal,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                        boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 8)],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Icon(Symbols.inventory_2,
                      size: 19,
                      color: _open ? context.pal.text : context.pal.textMute,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text('Inventory',
                        style: AppTheme.bodySm.copyWith(
                          color: _open ? context.pal.text : context.pal.textMute,
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                        )),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(Symbols.chevron_right,
                          size: 16, color: context.pal.textDim),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: _open
            ? Column(
                children: _inventoryChildren.map((c) => _SubNavItem(
                  icon:   c.icon,
                  label:  c.label,
                  active: widget.activeKey == c.key,
                  onTap:  () => widget.onSelect(c.key),
                )).toList(),
              )
            : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Expandable Sales group ─────────────────────────────────────────────────────

class _SalesGroup extends StatefulWidget {
  const _SalesGroup({required this.activeKey, required this.onSelect});
  final String activeKey;
  final ValueChanged<String> onSelect;

  @override
  State<_SalesGroup> createState() => _SalesGroupState();
}

class _SalesGroupState extends State<_SalesGroup> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.activeKey.startsWith('sales_');
  }

  @override
  void didUpdateWidget(_SalesGroup old) {
    super.didUpdateWidget(old);
    if (widget.activeKey.startsWith('sales_')) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (_open) {
              setState(() => _open = false);
            } else {
              setState(() => _open = true);
              widget.onSelect('sales_history');
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _open ? context.pal.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(children: [
              if (_open)
                Positioned(
                  left: -22, top: 4, bottom: 4,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                      boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 8)],
                    ),
                  ),
                ),
              Row(children: [
                Icon(Symbols.trending_up,
                  size: 19,
                  color: _open ? context.pal.text : context.pal.textMute,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text('Sales',
                    style: AppTheme.bodySm.copyWith(
                      color: _open ? context.pal.text : context.pal.textMute,
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                    )),
                ),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(Symbols.chevron_right,
                      size: 16, color: context.pal.textDim),
                ),
              ]),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: _open
            ? Column(
                children: _salesChildren
                    .where((c) => !{'sales_team', 'team_performance'}.contains(c.key) || can('sales.create_subordinate_user'))
                    .map((c) => _SubNavItem(
                  icon:   c.icon,
                  label:  c.label,
                  active: widget.activeKey == c.key,
                  onTap:  () => widget.onSelect(c.key),
                )).toList(),
              )
            : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Expandable Finance group ────────────────────────────────────────────────────

class _FinanceGroup extends StatefulWidget {
  const _FinanceGroup({required this.activeKey, required this.onSelect});
  final String activeKey;
  final ValueChanged<String> onSelect;

  @override
  State<_FinanceGroup> createState() => _FinanceGroupState();
}

class _FinanceGroupState extends State<_FinanceGroup> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.activeKey.startsWith('finance_') || widget.activeKey == 'finance';
  }

  @override
  void didUpdateWidget(_FinanceGroup old) {
    super.didUpdateWidget(old);
    if (widget.activeKey.startsWith('finance_')) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (_open) {
              setState(() => _open = false);
            } else {
              setState(() => _open = true);
              widget.onSelect('finance_dashboard');
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _open ? context.pal.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(children: [
              if (_open)
                Positioned(
                  left: -22, top: 4, bottom: 4,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                      boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 8)],
                    ),
                  ),
                ),
              Row(children: [
                Icon(Symbols.account_balance,
                  size: 19,
                  color: _open ? context.pal.text : context.pal.textMute,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text('Finance',
                    style: AppTheme.bodySm.copyWith(
                      color: _open ? context.pal.text : context.pal.textMute,
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                    )),
                ),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(Symbols.chevron_right,
                      size: 16, color: context.pal.textDim),
                ),
              ]),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: _open
            ? Column(
                children: _financeChildren.map((c) => _SubNavItem(
                  icon:   c.icon,
                  label:  c.label,
                  active: widget.activeKey == c.key,
                  onTap:  () => widget.onSelect(c.key),
                )).toList(),
              )
            : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Expandable group of rows (Purchases; Tendering & Logistics) ────────────────

class _NavGroup extends StatefulWidget {
  const _NavGroup({required this.icon, required this.label, this.tooltip, required this.children, required this.activeKey, required this.onSelect});
  final IconData icon;
  final String label;
  final String? tooltip;
  final List<({String key, IconData icon, String label})> children;
  final String activeKey;
  final ValueChanged<String> onSelect;

  @override
  State<_NavGroup> createState() => _NavGroupState();
}

class _NavGroupState extends State<_NavGroup> {
  late bool _open;

  bool get _containsActive => widget.children.any((c) => c.key == widget.activeKey);

  @override
  void initState() {
    super.initState();
    _open = _containsActive;
  }

  @override
  void didUpdateWidget(_NavGroup old) {
    super.didUpdateWidget(old);
    if (_containsActive) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          // No department dashboard (see feedback on module dashboards) —
          // opening the group lands on its first row instead.
          onTap: () {
            if (_open) {
              setState(() => _open = false);
            } else {
              setState(() => _open = true);
              if (!_containsActive) widget.onSelect(widget.children.first.key);
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _open ? context.pal.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(children: [
              if (_open)
                Positioned(
                  left: -22, top: 4, bottom: 4,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                      boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 8)],
                    ),
                  ),
                ),
              Row(children: [
                Icon(widget.icon,
                  size: 19,
                  color: _open ? context.pal.text : context.pal.textMute,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Tooltip(
                    message: widget.tooltip ?? '',
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySm.copyWith(
                        color: _open ? context.pal.text : context.pal.textMute,
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                      )),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(Symbols.chevron_right,
                      size: 16, color: context.pal.textDim),
                ),
              ]),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: _open
            ? Column(
                children: widget.children.map((c) => _SubNavItem(
                  icon:   c.icon,
                  label:  c.label,
                  active: widget.activeKey == c.key,
                  onTap:  () => widget.onSelect(c.key),
                )).toList(),
              )
            : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SubNavItem extends StatelessWidget {
  const _SubNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(left: 26, right: 12, top: 1, bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? AppColors.tealSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(children: [
        Icon(icon, size: 15,
            color: active ? AppColors.teal : context.pal.textDim),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label,
            style: AppTheme.bodySm.copyWith(
              color: active ? AppColors.teal : context.pal.textMute,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              fontSize: 12.5,
            )),
        ),
      ]),
    ),
  );
}

// ── Standard nav item ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
    child: Text(text.toUpperCase(), style: AppTheme.monoXs.copyWith(letterSpacing: 0.12)),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.dest, {required this.active, required this.onTap});
  final NavDestination dest;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? context.pal.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            if (active)
              Positioned(
                left: -22, top: 4, bottom: 4,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                    boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 8)],
                  ),
                ),
              ),
            Row(
              children: [
                Icon(dest.icon,
                  size: 19,
                  color: active ? context.pal.text : context.pal.textMute,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(dest.label,
                    style: AppTheme.bodySm.copyWith(
                      color: active ? context.pal.text : context.pal.textMute,
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                    )),
                ),
                if (dest.key == 'email') const EmailNavBadge(),
                if (dest.key == 'chats') const ChatNavBadge(),
                if (dest.count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? AppColors.tealSoft : context.pal.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(dest.count!,
                      style: AppTheme.bodySub.copyWith(
                        fontSize: 11,
                        color: active ? AppColors.teal : context.pal.textMute,
                        fontWeight: FontWeight.w500,
                      )),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────────

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.pal.border)),
      ),
      child: Row(
        children: [
          const CurrentUserAvatar(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([userNameNotifier, userRoleNotifier, userLocationNotifier]),
              builder: (_, _) {
                final name = userNameNotifier.value;
                final role = roleDisplayName(userRoleNotifier.value);
                final location = userLocationNotifier.value;
                final subtitle = [
                  if (role.isNotEmpty) role,
                  if (location != null && location.isNotEmpty) location,
                ].join(' · ');
                return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : 'User',
                    style: AppTheme.bodyStrong.copyWith(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                      style: AppTheme.bodySub.copyWith(fontSize: 10.5, color: context.pal.textDim),
                      overflow: TextOverflow.ellipsis),
                ],
              );
              },
            ),
          ),
          Icon(Symbols.more_horiz, size: 18, color: context.pal.textDim),
        ],
      ),
    );
  }
}
