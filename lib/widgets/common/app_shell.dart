import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../screens/approvals/approvals_screen.dart';
import '../../screens/customers/customers_screen.dart';
import '../../screens/dashboard/unified_dashboard_screen.dart';
import '../../screens/finance/creditors_screen.dart';
import '../../screens/finance/receivables_screen.dart';
import '../../screens/email/email_screen.dart';
import '../../screens/chat/chats_screen.dart';
import '../../screens/meetings/meetings_screen.dart';
import '../../screens/letters/letters_screen.dart';
import '../../screens/finance/bank_reconciliation_screen.dart';
import '../../screens/finance/chart_of_accounts_screen.dart';
import '../../screens/finance/expenses_screen.dart';
import '../../screens/finance/finance_dashboard_screen.dart';
import '../../screens/finance/finance_reports_screen.dart';
import '../../screens/finance/vendor_bills_screen.dart';
import '../../screens/finance/vendor_fees_screen.dart';
import '../../screens/hr/hr_approval_screen.dart';
import '../../screens/hr/hr_attendance_screen.dart';
import '../../screens/hr/hr_dashboard_screen.dart';
import '../../screens/hr/hr_directory_screen.dart';
import '../../screens/hr/hr_leave_calendar_screen.dart';
import '../../screens/hr/hr_payroll_screen.dart';
import '../../screens/hr/hr_recruitment_screen.dart';
import '../../screens/hr/hr_reports_screen.dart';
import '../../screens/hr/hr_settings_screen.dart';
import '../../screens/hr/my_leave_screen.dart';
import '../../screens/inventory/inventory_items_screen.dart';
import '../../screens/inventory/locations_screen.dart';
import '../../screens/inventory/suppliers_screen.dart';
import '../../screens/inventory/stock_movements_screen.dart';
import '../../screens/inventory/requisitions_screen.dart';
import '../../screens/inventory/purchase_orders_screen.dart';
import '../../screens/reports/reports_screen.dart';
import '../../screens/revenue/revenue_screen.dart';
import '../../screens/self_service/my_travel_plans_screen.dart';
import '../../screens/self_service/travel_plan_viewer.dart';
import '../../services/per_diem_service.dart';
import '../../screens/sales/sales_screen.dart';
import '../../screens/sales/invoices_screen.dart';
import '../../screens/sales/quotations_screen.dart';
import '../../screens/sales/sales_dashboard_screen.dart';
import '../../screens/sales/sales_orders_screen.dart';
import '../../screens/sales/all_sales_screen.dart';
import '../../screens/purchases/all_purchases_screen.dart';
import '../../screens/purchases/purchase_returns_screen.dart';
import '../../screens/sales/invoice_builder_screen.dart';
import '../../screens/sales/team_screen.dart';
import '../../screens/performance/my_performance_screen.dart';
import '../../screens/performance/team_performance_screen.dart';
import '../../screens/performance/contributions_screen.dart';
import '../../screens/self_service/my_expenses_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/delegations_screen.dart';
import '../../screens/settings/notification_templates_screen.dart';
import '../../screens/settings/activity_log_screen.dart';
import '../../screens/settings/downloads_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/procurement/device_registrations_screen.dart';
import '../../screens/procurement/tenders_screen.dart';
import '../../screens/procurement/nest_tenders_screen.dart';
import '../../screens/procurement/shipments_screen.dart';
import '../../screens/procurement/shipment_registers_screen.dart';
import '../../screens/procurement/shipment_settings_screen.dart';
import '../../screens/staff/staff_screen.dart';
import '../../main.dart' show trialNotifier, userRoleNotifier, allowedScreenKeys, defaultScreenKey, hasAccountantAuthority;
import '../../models/notification.dart';
import '../../models/search_result.dart';
import '../people/person_profile.dart' show showPersonProfile;
import '../../screens/trial/trial_expired_screen.dart';
import '../../services/api_client.dart';
import '../../services/background_sync.dart';
import '../../services/disk_cache.dart';
import '../../services/shell_navigation.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'email_badge.dart';
import 'sidebar.dart';
import 'sidebar_rail.dart';
import 'top_bar.dart';
import '../chat/chat_dock.dart';
import '../../services/chat_controller.dart';
import '../../services/phone_notifications.dart';
import 'update_widgets.dart' show UpdateBanner;

import '../../theme/app_palette.dart';
// ── Breakpoints (content-area width) ──────────────────────────────────────────
//   < 720   → Mobile   : page-title top bar + role-aware bottom tab bar
//                        (4 tabs + More → drawer with the full menu)
//   720–1099 → Tablet  : 64 px icon-rail sidebar + compact top bar (+ drawer)
//   ≥ 1100  → Desktop  : full 232 px labeled sidebar + full top bar

/// Root shell — adapts navigation chrome to three device classes.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialScreenKey});

  /// Screen to open first instead of the role's landing screen (still
  /// permission-gated). Used by tests to open a given screen directly.
  final String? initialScreenKey;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late String _activeKey;

  // Set only via _navigateToEntity — carries an optional target for the
  // screen being navigated to (a specific entity id, or which tab to open).
  // _navigate() clears both so a stale deep-link target never leaks into a
  // plain sidebar click.
  int? _pendingEntityId;
  int? _pendingTabIndex;
  // Bumped on every navigation so the content navigator starts fresh, even
  // when the same sidebar item is clicked again from inside a pushed page.
  int _navEpoch = 0;

  @override
  void initState() {
    super.initState();
    _activeKey = widget.initialScreenKey == null
        ? defaultScreenKey(userRoleNotifier.value)
        : _gatedKey(widget.initialScreenKey!);
    BackgroundSync.instance.start();
    ChatController.instance.start();
    // Android: notification permission + taps on pop-ups (no-op elsewhere).
    unawaited(PhoneNotifications.instance.init());
    ChatController.instance.openRequests.addListener(_onChatOpenRequest);
    _diskEvents = ApiClient.instance.diskCache.events.listen(_onDiskEvent);
    // Desktop pop-up clicks navigate through these.
    ShellNavigation.openScreen = _navigate;
    ShellNavigation.openNotification = _openNotification;
  }

  @override
  void dispose() {
    if (ShellNavigation.openScreen == _navigate) {
      ShellNavigation.openScreen = null;
      ShellNavigation.openNotification = null;
    }
    _diskEvents?.cancel();
    BackgroundSync.instance.stop();
    ChatController.instance.openRequests.removeListener(_onChatOpenRequest);
    ChatController.instance.stop();
    super.dispose();
  }

  // A chat pop-up was tapped. Phones show chats on the Chats screen (wider
  // layouts open the floating chat window, see ChatDock).
  void _onChatOpenRequest() {
    if (ChatController.instance.openRequests.value == null || !mounted) return;
    if (MediaQuery.sizeOf(context).width < 720 && _activeKey != 'chats') _navigate('chats');
  }

  // ── Disk-cache freshness ──────────────────────────────────────────────────
  //
  // A screen's first requests this session may be answered from the disk
  // cache while the network copy is fetched in the background. Once every
  // key served from disk since the screen mounted is revalidated and any of
  // them changed, the screen is rebuilt with the fresh data: silently if the
  // user hasn't touched it yet, otherwise behind an "Updated data available"
  // chip so nothing moves under their finger.

  StreamSubscription<DiskCacheEvent>? _diskEvents;
  // Bumped to remount just the screen (not the content navigator, so pages
  // it pushed stay open).
  int _screenRemount = 0;
  String? _freshnessMount;
  final _diskPending = <String>{};
  bool _diskChanged = false;
  bool _contentTouched = false;
  bool _showUpdatedChip = false;

  void _onDiskEvent(DiskCacheEvent e) {
    if (!mounted) return;
    switch (e) {
      case ServedFromDisk():
        setState(() => _diskPending.add(e.key));
      case Revalidated(:final changed):
        // Not one of this screen's keys (it was served before navigating).
        if (!_diskPending.contains(e.key)) return;
        setState(() {
          _diskPending.remove(e.key);
          _diskChanged |= changed;
          if (_diskPending.isNotEmpty || !_diskChanged) return;
          _diskChanged = false;
          if (_contentTouched) {
            _showUpdatedChip = true;
          } else {
            _screenRemount++;
          }
        });
    }
  }

  void _refreshScreen() => setState(() {
    _showUpdatedChip = false;
    _screenRemount++;
  });

  /// Starts freshness tracking over whenever a different screen (or a
  /// remount of it) is built.
  void _trackMount() {
    final mount = '$_navEpoch|$_activeKey|$_screenRemount';
    if (mount == _freshnessMount) return;
    _freshnessMount = mount;
    _diskPending.clear();
    _diskChanged = false;
    _contentTouched = false;
    _showUpdatedChip = false;
  }

  // ── Screen router ─────────────────────────────────────────────────────────

  // Sub-module keys use the parent module as the permission gate.
  String _gatedKey(String key) {
    final allowed = allowedScreenKeys(userRoleNotifier.value);
    String permKey = key;
    if (key.startsWith('inventory_')) permKey = 'inventory';
    if (key == 'inventory_suppliers' && allowed != null && !allowed.contains('inventory') && allowed.contains('shipments')) permKey = 'shipments';
    if (key.startsWith('sales_'))     permKey = 'sales';
    if (key.startsWith('purchases_')) permKey = 'purchases';
    if (key.startsWith('finance_'))   permKey = 'finance';
    if (key == 'tender_devices' || key == 'nest_tenders') permKey = 'tenders';
    if (const {'tmda_permits', 'clearing_fees', 'shipment_settings'}.contains(key)) permKey = 'shipments';
    return (allowed == null || allowed.contains(permKey))
        ? key
        : defaultScreenKey(userRoleNotifier.value);
  }

  bool _isAllowed(String key) => _gatedKey(key) == key;

  // The content navigator's key, renewed whenever _navEpoch moves so a fresh
  // navigator never inherits the old one's pushed pages (a reused GlobalKey
  // would carry its state across). Lets the back button pop pushed pages.
  GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();
  int _contentNavKeyEpoch = 0;

  void _navigate(String key) {
    setState(() {
      _navEpoch++;
      _activeKey = _gatedKey(key);
      _pendingEntityId = null;
      _pendingTabIndex = null;
    });
  }

  /// Like [_navigate], but also carries a specific entity id and/or tab
  /// index for the target screen to pick up (e.g. a notification's "open
  /// this exact ticket" or "open Approvals on the Per Diem tab").
  void _navigateToEntity(String key, {int? entityId, int? tabIndex}) {
    setState(() {
      _navEpoch++;
      _activeKey = _gatedKey(key);
      _pendingEntityId = entityId;
      _pendingTabIndex = tabIndex;
    });
  }

  /// Routes a tapped notification to wherever its recipient acts on it.
  /// `n == null` means "View all" with no specific entity in mind.
  void _openNotification(AppNotification? n) {
    if (n == null) {
      _navigate('notifications');
      return;
    }
    final entityId = int.tryParse(n.entityId ?? '');
    // Payroll "Money is out" (payroll_paid) has no NotificationType of its own.
    if (n.entityType == 'payroll_run') return _navigate('hr_payroll');
    // Invites, circulated minutes and action items all open the meeting.
    if (n.entityType == 'meeting') return _navigateToEntity('meetings', entityId: entityId);
    // Clearing & vendor fees: Approvals → Clearing & Vendor Fees, where the
    // manager, Finance and the Director act on them.
    if (n.entityType == 'vendor_fee') return _navigateToEntity('approvals', tabIndex: 5);
    // Expenses: whoever acts on one (manager, CTO, Director, Finance) gets
    // Approvals → Expenses; the submitter's own outcomes open My Expenses.
    // Keyed on the record, so no expense notification lands anywhere else.
    if (n.entityType == 'expense') {
      final ownOutcome = n.type == NotificationType.expenseRejected
          || n.type == NotificationType.expensePaid
          // "Approved" goes to the submitter, and as "ready to pay" to Finance.
          || (n.type == NotificationType.expenseApproved && !hasAccountantAuthority(userRoleNotifier.value));
      return (ownOutcome || !_isAllowed('approvals'))
          ? _navigate('my_expenses')
          : _navigateToEntity('approvals', tabIndex: 2);
    }
    switch (n.type) {
      case NotificationType.leaveRequested:
        _navigateToEntity('hr_approvals', tabIndex: 0);
      case NotificationType.stockOutRequested:
      case NotificationType.stockOutApproved:
      case NotificationType.stockOutRejected:
        _navigateToEntity('approvals', tabIndex: 0);
      case NotificationType.perDiemPending:
      case NotificationType.perDiemApproved:
        _navigateToEntity('approvals', tabIndex: 1);
      // Decided — the requester's own plan, in the travel-plan viewer.
      case NotificationType.perDiemPaid:
      case NotificationType.perDiemRejected:
        _openTravelPlan(entityId);
      case NotificationType.expensePending:
      case NotificationType.expenseApproved:
        _navigateToEntity('approvals', tabIndex: 2);
      case NotificationType.expenseRejected:
      case NotificationType.expensePaid:
        _navigate('my_expenses');
      case NotificationType.leaveApproved:
      case NotificationType.leaveRejected:
        _navigate('my_leave');
      case NotificationType.lateArrival:
        _navigateToEntity('hr_approvals', tabIndex: 2);
      case NotificationType.leadFollowUp:
      case NotificationType.dealUpdated:
        _navigateToEntity('sales', entityId: entityId);
      case NotificationType.taskAssigned:
      case NotificationType.taskCompleted:
        _navigateToEntity('staff', entityId: entityId);
      case NotificationType.quotationPrepared:
        _navigate(_isAllowed('sales_quotations') ? 'sales_quotations' : 'quotations');
      case NotificationType.stockPullRequired:
        _navigate('sales_orders');
      case NotificationType.tenderDeadline:
      case NotificationType.tenderOverdue:
        _navigateToEntity('tenders', entityId: entityId);
      case NotificationType.deviceRenewal:
        _navigateToEntity('tender_devices', entityId: entityId);
      case NotificationType.shipmentUpdate:
        _navigateToEntity('shipments', entityId: entityId);
      case NotificationType.nestTender:
        _navigateToEntity('nest_tenders', entityId: entityId);
      default:
        _navigate('notifications');
    }
  }

  Future<void> _openTravelPlan(int? id) async {
    if (id == null) return _navigate('my_travel_plans');
    try {
      final plan = await PerDiemService.instance.show(id);
      if (mounted) await openTravelPlanViewer(context, plan);
    } catch (_) {
      if (mounted) _navigate('my_travel_plans');
    }
  }

  /// Routes a tapped global-search result to wherever it lives. Types with
  /// an existing "deep link to one record" hook land on that exact record;
  /// everything else opens the right list screen. Result types from modules
  /// this build doesn't have (machines, service tickets) are ignored.
  void _openSearchResult(SearchResult r) {
    switch (r.type) {
      case 'sales_lead':
        _navigateToEntity('sales', entityId: r.id);
      case 'hospital':
        _navigate('customers');
      case 'inventory_item':
        _navigate('inventory_items');
      case 'supplier':
        _navigate('inventory_suppliers');
      case 'location':
        _navigate('inventory_locations');
      case 'staff':
        // A colleague's profile, wherever the user is.
        showPersonProfile(context, r.id);
      case 'quotation':
        _navigate('sales_quotations');
      case 'sales_order':
        _navigate('sales_orders');
      case 'invoice':
        _navigate('sales_invoices');
      case 'contact':
        _navigate('customers');
      case 'vendor_bill':
        _navigate('finance_bills');
      case 'expense':
        _navigate('finance_expenses');
      case 'page':
        if (r.pageKey != null) _navigate(r.pageKey!);
      case 'purchase_order':
        _navigate('purchases_list');
      case 'requisition':
        _navigate('inventory_requisitions');
      case 'shipment':
        _navigateToEntity('shipments', entityId: r.id);
      case 'tender':
        _navigateToEntity('tenders', entityId: r.id);
      case 'nest_tender':
        _navigateToEntity('nest_tenders', entityId: r.id);
      case 'device_registration':
        _navigateToEntity('tender_devices', entityId: r.id);
      case 'meeting':
        _navigateToEntity('meetings', entityId: r.id);
      case 'letter':
        _navigate('letters');
    }
  }

  // Pages a screen pushes (Navigator.push — builders, detail pages) open
  // inside the content area, so the sidebar and top bar stay put.
  Widget _content() {
    if (_contentNavKeyEpoch != _navEpoch) {
      _contentNavKey = GlobalKey<NavigatorState>();
      _contentNavKeyEpoch = _navEpoch;
    }
    _trackMount();
    final navigator = _ContentNavigator(
      key: ValueKey('content-$_navEpoch'),
      navigatorKey: _contentNavKey,
      child: KeyedSubtree(key: ValueKey('screen-$_screenRemount'), child: _buildScreen()),
    );
    // Any tap, scroll or key press in the content counts as "touched".
    return Listener(
      onPointerDown: (_) => _contentTouched = true,
      onPointerSignal: (_) => _contentTouched = true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, _) {
          _contentTouched = true;
          return KeyEventResult.ignored;
        },
        child: Stack(children: [
          Positioned.fill(child: navigator),
          if (_diskPending.isNotEmpty)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            ),
          if (_showUpdatedChip)
            Positioned(
              top: 8, left: 12, right: 12,
              child: Center(child: _UpdatedDataChip(onRefresh: _refreshScreen)),
            ),
        ]),
      ),
    );
  }

  Widget _buildScreen() => switch (_activeKey) {
    'dashboard' => UnifiedDashboardScreen(onNavigateTo: _navigate),
    'inventory' || 'inventory_items' => const InventoryItemsScreen(),
    'inventory_suppliers'    => const SuppliersScreen(),
    'inventory_movements'    => const StockMovementsScreen(),
    'inventory_requisitions' => const RequisitionsScreen(),
    'inventory_orders'       => const PurchaseOrdersScreen(),
    'inventory_locations'    => const LocationsScreen(),
    'revenue'                => const RevenueScreen(),
    'finance' || 'finance_dashboard' => FinanceDashboardScreen(onNavigateTo: _navigate),
    'finance_expenses'       => const ExpensesScreen(),
    'finance_bills'          => const VendorBillsScreen(),
    'finance_creditors'      => const CreditorsScreen(),
    'finance_ledger'         => const ChartOfAccountsScreen(),
    'finance_reports'        => const FinanceReportsScreen(),
    'finance_bank_rec'       => const BankReconciliationScreen(),
    'finance_receivables'    => const ReceivablesScreen(),
    'vendor_fees'            => const VendorFeesScreen(),
    'tmda_permits'           => const TmdaPermitsScreen(),
    'clearing_fees'          => const ClearingFeesScreen(),
    'shipment_settings'      => const ShipmentSettingsScreen(embedded: true),
    'shipments'              => ShipmentsScreen(key: ValueKey('shipments-$_pendingEntityId'), initialShipmentId: _pendingEntityId),
    'tenders'                => TendersScreen(key: ValueKey('tenders-$_pendingEntityId'), initialTenderId: _pendingEntityId),
    'tender_devices'         => DeviceRegistrationsScreen(key: ValueKey('devices-$_pendingEntityId'), initialDeviceId: _pendingEntityId),
    'nest_tenders'           => NestTendersScreen(key: ValueKey('nest-$_pendingEntityId'), initialTenderId: _pendingEntityId),
    'email'     => const EmailScreen(),
    'chats'     => const ChatsScreen(),
    'meetings'  => MeetingsScreen(key: ValueKey('meetings-$_pendingEntityId'), initialMeetingId: _pendingEntityId),
    'letters'   => const LettersScreen(),
    'sales' || 'sales_leads' => SalesScreen(initialLeadId: _pendingEntityId),
    'sales_dashboard'         => SalesDashboardScreen(onNavigateTo: _navigate),
    'sales_quotations'       => const QuotationsScreen(),
    'sales_orders'           => SalesOrdersScreen(onNavigateTo: _navigate),
    'sales_invoices'         => InvoicesScreen(onNavigateTo: _navigate),
    'purchases' || 'purchases_list' => const AllPurchasesScreen(key: ValueKey('purchases_list')),
    'purchases_new'          => const AllPurchasesScreen(key: ValueKey('purchases_new'), openNew: true),
    'purchases_returns'      => const PurchaseReturnsScreen(),
    'sales_history'          => const AllSalesScreen(key: ValueKey('sales_history')),
    'sales_drafts'           => const AllSalesScreen(key: ValueKey('sales_drafts'), initialKind: 'draft'),
    'sales_new'              => InvoiceBuilderScreen(key: const ValueKey('sales_new'), onDone: _afterSaleSaved),
    'sales_new_draft'        => InvoiceBuilderScreen(key: const ValueKey('sales_new_draft'), initialStatus: 'draft', onDone: _afterSaleSaved),
    'sales_new_quotation'    => InvoiceBuilderScreen(key: const ValueKey('sales_new_quotation'), initialStatus: 'quotation', onDone: _afterSaleSaved),
    'sales_team'             => const TeamScreen(),
    'team_performance'       => const TeamPerformanceScreen(),
    'my_performance'         => const MyPerformanceScreen(),
    'quotations'             => const QuotationsScreen(),
    'my_expenses'            => const MyExpensesScreen(),
    'contributions'          => const ContributionsScreen(),
    'customers' => const CustomersScreen(),
    'staff'          => StaffScreen(initialTaskId: _pendingEntityId),
    'my_leave'       => const MyLeaveScreen(),
    'my_travel_plans'    => const MyTravelPlansScreen(),
    'hr_approvals'   => HrApprovalScreen(initialTabIndex: _pendingTabIndex),
    'hr_settings'    => const HrSettingsScreen(),
    'hr_dashboard'   => const HrDashboardScreen(),
    'hr_directory'   => HrDirectoryScreen(onNavigateTo: _navigate),
    'hr_recruitment' => const HrRecruitmentScreen(),
    'hr_leave_calendar' => HrLeaveCalendarScreen(onNavigateTo: _navigate),
    'hr_attendance'  => const HrAttendanceScreen(),
    'hr_payroll'     => const HrPayrollScreen(),
    'hr_reports'     => const HrReportsScreen(),
    'approvals'      => ApprovalsScreen(initialTabIndex: _pendingTabIndex),
    'notifications'  => NotificationsScreen(onOpenNotification: _openNotification),
    'reports'        => ReportsScreen(onNavigateTo: _navigate),
    'settings'  => SettingsScreen(onNavigateTo: _navigate),
    'delegations' => const DelegationsScreen(),
    'notification_templates' => const NotificationTemplatesScreen(),
    'activity_log' => const ActivityLogScreen(),
    'downloads' => const DownloadsScreen(),
    _ => _PlaceholderScreen(title: _activeKey),
  };

  // After Add sale / Add draft / Add quotation, show the list it landed in.
  void _afterSaleSaved(String status) => _navigate(switch (status) {
    'quotation' => 'sales_quotations',
    'draft'     => 'sales_drafts',
    _           => 'sales_history',
  });

  // Resolved sidebar key:
  // - inventory sub-keys → sidebar uses the sub-key directly for child highlighting
  String get _sidebarKey {
    if (_activeKey == 'inventory') return 'inventory_items';
    if (_activeKey == 'sales')     return 'sales_leads';
    if (_activeKey == 'purchases') return 'purchases_list';
    if (_activeKey == 'finance')   return 'finance_dashboard';
    return _activeKey;
  }

  // ── Mobile bottom tabs ────────────────────────────────────────────────────

  /// Bottom-tab candidates in priority order. Each user gets Home, their
  /// role's landing screen, then the first others they're allowed into —
  /// four in all — so a tab never bounces someone back to their default
  /// screen.
  static const _tabPriority = [
    'approvals',
    'sales_leads', 'sales_history', 'customers',
    'inventory_items', 'revenue', 'finance_receivables', 'finance_expenses',
    'hr_directory', 'hr_approvals', 'hr_attendance',
    'staff', 'my_leave', 'notifications',
  ];

  /// Screen key a landing key resolves to in the tab bar.
  static String _tabKeyOf(String key) => switch (key) {
    'inventory' => 'inventory_items',
    'sales'     => 'sales_leads',
    'finance'   => 'finance_dashboard',
    _           => key,
  };

  List<String> get _mobileTabs {
    final home    = _isAllowed('dashboard') ? 'dashboard' : defaultScreenKey(userRoleNotifier.value);
    final landing = _tabKeyOf(defaultScreenKey(userRoleNotifier.value));
    final tabs = <String>[home];
    // A *_dashboard landing is what Home already shows (department delegation).
    for (final k in [if (!landing.endsWith('dashboard')) landing, ..._tabPriority]) {
      if (tabs.length == 4) break;
      if (!tabs.contains(k) && _isAllowed(k)) tabs.add(k);
    }
    return tabs;
  }

  /// Which tab (if any) owns the current screen.
  String? _activeTab(List<String> tabs) {
    final k = _tabKeyOf(_activeKey);
    if (tabs.contains(k)) return k;
    if (k.endsWith('dashboard') && tabs.first == 'dashboard') return 'dashboard';
    return null;
  }

  String get _pageTitle => _activeKey == 'dashboard'
      ? 'Home'
      : navEntryFor(_activeKey)?.label ?? 'Hypermed';

  // ── Back button (Android / phones & tablets) ──────────────────────────────

  /// Back steps out in order: open drawer → the screen itself (a page it
  /// pushed, or its own PopScope) → home tab → leave the app.
  Future<void> _handleBack() async {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    // maybePop is false only when the screen has nothing to close itself.
    final nav = _contentNavKey.currentState;
    if (nav != null && await nav.maybePop()) return;
    if (!mounted) return;
    final home = _mobileTabs.first;
    if (_activeKey != home) {
      _navigate(home);
      return;
    }
    SystemNavigator.pop();
  }

  Widget _withBackHandling(Widget child) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: child,
  );

  // ── Shared drawer ─────────────────────────────────────────────────────────

  Widget _buildDrawer() => Drawer(
    width: 272,
    backgroundColor: context.pal.sidebarBg,
    // Clear the status bar and the gesture bar on phones.
    child: SafeArea(child: Column(children: [
      // Drawer header with close button
      Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.pal.border)),
        ),
        child: Row(children: [
          Expanded(child: Text('Menu', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.closeDrawer(),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: context.pal.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Symbols.close, size: 16, color: context.pal.textDim),
            ),
          ),
        ]),
      ),
      // Full nav sections (reuses Sidebar, fills drawer width)
      Expanded(
        child: Sidebar(
          width: 272,
          activeKey: _sidebarKey,
          onSelect: (k) {
            _scaffoldKey.currentState?.closeDrawer();
            _navigate(k);
          },
        ),
      ),
    ])),
  );

  // ── Trial banner ──────────────────────────────────────────────────────────

  Widget _trialBanner() => ValueListenableBuilder(
    valueListenable: trialNotifier,
    builder: (_, trial, _) => trial.showBanner
        ? TrialBanner(status: trial)
        : const SizedBox.shrink(),
  );

  // ── Layouts ───────────────────────────────────────────────────────────────

  /// Paints the active theme's diagonal wash (aurora) behind the shell body,
  /// or just its flat [AppPalette.bg] for every other theme — same visual
  /// result as before for themes with no [AppPalette.bgGradient] set.
  Decoration _bgDecoration(BuildContext context) {
    final grad = context.pal.bgGradient;
    if (grad == null) return BoxDecoration(color: context.pal.bg);
    return BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad,
    ));
  }

  /// Desktop (≥ 1100 px) — persistent 232 px labeled sidebar.
  Widget _buildDesktop() => Scaffold(
    backgroundColor: context.pal.bg,
    body: Stack(children: [DecoratedBox(
      decoration: _bgDecoration(context),
      child: Column(
        children: [
          TopBar(onOpenNotification: _openNotification, onOpenSearchResult: _openSearchResult, canOpenPage: _isAllowed, onOpenProfile: () => _navigate('settings')),
          const UpdateBanner(),
          _trialBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Sidebar(
                  activeKey: _sidebarKey,
                  onSelect: (k) => _navigate(k),
                ),
                Expanded(child: ClipRect(child: _content())),
              ],
            ),
          ),
        ],
      ),
    ),
    // Messenger-style chat button + docked window over the page.
    const ChatDock(),
    ]),
  );

  /// Tablet (720–1099 px) — 64 px icon rail + compact top bar + drawer.
  Widget _buildTablet() => _withBackHandling(Scaffold(
    key: _scaffoldKey,
    backgroundColor: context.pal.bg,
    appBar: PreferredSize(
      preferredSize: Size.fromHeight(56 + MediaQuery.paddingOf(context).top),
      child: Container(
        color: context.pal.topbarBg,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: TopBar(
          onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
          onOpenNotification: _openNotification,
          onOpenSearchResult: _openSearchResult, canOpenPage: _isAllowed,
          onOpenProfile: () => _navigate('settings'),
        ),
      ),
    ),
    drawer: _buildDrawer(),
    body: Stack(children: [DecoratedBox(
      decoration: _bgDecoration(context),
      child: Column(
        children: [
          const UpdateBanner(),
          _trialBanner(),
          Expanded(child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SidebarRail(
                activeKey: _sidebarKey,
                onSelect: (k) => _navigate(k),
              ),
              Expanded(child: ClipRect(child: _content())),
            ],
          )),
        ],
      ),
    ),
    const ChatDock(),
    ]),
  ));

  /// Mobile (< 720 px) — page-title top bar, role-aware bottom tabs, and the
  /// full menu in a drawer behind "More".
  Widget _buildMobile() {
    final tabs = _mobileTabs;
    return _withBackHandling(Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.pal.bg,
      appBar: PreferredSize(
        // Status-bar inset + 56 px bar, so the bar never sits under the clock.
        preferredSize: Size.fromHeight(56 + MediaQuery.paddingOf(context).top),
        child: Container(
          color: context.pal.topbarBg,
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: TopBar(
            compact: true,
            title: _pageTitle,
            onOpenNotification: _openNotification,
            onOpenSearchResult: _openSearchResult, canOpenPage: _isAllowed,
            onOpenProfile: () => _navigate('settings'),
          ),
        ),
      ),
      drawer: _buildDrawer(),
      bottomNavigationBar: _BottomTabBar(
        tabs: tabs,
        activeTab: _activeTab(tabs),
        onSelect: (k) => _navigate(k),
        onMore: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      body: DecoratedBox(
        decoration: _bgDecoration(context),
        child: Column(
          children: [
            _trialBanner(),
            Expanded(child: ClipRect(child: _content())),
          ],
        ),
      ),
    ));
  }

  // ── Root build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1100) return _buildDesktop();
    if (width >= 720)  return _buildTablet();
    return _buildMobile();
  }
}

// ── Bottom tab bar (mobile) ────────────────────────────────────────────────────

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.tabs,
    required this.activeTab,
    required this.onSelect,
    required this.onMore,
  });

  /// Screen keys for the primary tabs (up to 4); "More" is always last.
  final List<String> tabs;
  /// The tab owning the current screen, or null → "More" is active.
  final String? activeTab;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  static ({String label, IconData icon}) _entry(String key) => key == 'dashboard'
      ? (label: 'Home', icon: Symbols.space_dashboard)
      : navEntryFor(key) ?? (label: key, icon: Symbols.apps);

  @override
  Widget build(BuildContext context) {
    // Bottom safe area so the bar clears the iOS home indicator / Android gesture bar.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: 64 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset, left: 4, right: 4),
      decoration: BoxDecoration(
        color: context.pal.topbarBg,
        border: Border(top: BorderSide(color: context.pal.border)),
      ),
      child: Row(
        children: [
          for (final k in tabs)
            Expanded(child: _BottomTab(
              icon: _entry(k).icon,
              label: _entry(k).label,
              active: activeTab == k,
              badge: k == 'email',
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(k);
              },
            )),
          Expanded(child: _BottomTab(
            icon: Symbols.menu,
            label: 'More',
            active: activeTab == null,
            // Email lives in the drawer when it isn't a tab.
            badge: !tabs.contains('email'),
            onTap: () {
              HapticFeedback.selectionClick();
              onMore();
            },
          )),
        ],
      ),
    );
  }
}

/// Material 3-style destination: a soft pill behind the (filled) icon marks
/// the active tab, so it reads at a glance, not just by colour.
class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  /// Shows the Email badge on the icon.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.teal : context.pal.textMute;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: active ? 56 : 40,
                height: 30,
                decoration: BoxDecoration(
                  color: active ? AppColors.teal.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, size: 22, color: color, fill: active ? 1 : 0),
              ),
              // On the icon's top-right corner, painted outside the layout
              // so it can't push the label or overflow a narrow bar.
              if (badge)
                const Positioned(top: -4, right: -6, child: EmailNavBadge(compact: true)),
            ]),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'TildaSans',
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "Updated data available" chip ─────────────────────────────────────────────

class _UpdatedDataChip extends StatelessWidget {
  const _UpdatedDataChip({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Material(
    color: context.pal.surface2,
    elevation: 4,
    shape: StadiumBorder(side: BorderSide(color: context.pal.borderStrong)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onRefresh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.sync, size: 15, color: AppColors.teal),
          const SizedBox(width: 6),
          Flexible(child: Text('Updated data available',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySm.copyWith(fontSize: 12.5))),
          Text(' · ', style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
          Text('Refresh', style: AppTheme.bodyStrong.copyWith(fontSize: 12.5, color: AppColors.teal)),
        ]),
      ),
    ),
  );
}

// ── Placeholder ───────────────────────────────────────────────────────────────

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 12),
      Text(title, style: TextStyle(color: context.pal.textMute, fontSize: 18)),
    ]),
  );
}

/// Nested navigator for the shell's content area. The current screen is its
/// single page (updated in place as the shell rebuilds); anything a screen
/// pushes stacks on top of it within the content area (switching in place on
/// desktop, with the platform transition on phones) rather than covering the
/// whole window. Dialogs still use the
/// root navigator (showDialog's default), so they cover the full window.
class _ContentNavigator extends StatelessWidget {
  const _ContentNavigator({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  static const _noTransition = _InstantPageTransitions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Desktop: pages switch in place. Phones keep their platform's own
    // transition (slide + swipe-back on iOS, Material on Android) so a
    // detail page reads as "on top of" the list.
    return Theme(
      data: theme.copyWith(pageTransitionsTheme: PageTransitionsTheme(builders: {
        ...theme.pageTransitionsTheme.builders,
        TargetPlatform.linux: _noTransition, TargetPlatform.windows: _noTransition,
        TargetPlatform.macOS: _noTransition, TargetPlatform.fuchsia: _noTransition,
      })),
      child: Navigator(
        key: navigatorKey,
        pages: [MaterialPage(key: const ValueKey('screen'), child: child)],
        onDidRemovePage: (_) {},
      ),
    );
  }
}

class _InstantPageTransitions extends PageTransitionsBuilder {
  const _InstantPageTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) => child;
}
