import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/auth/login_screen.dart';
import 'screens/trial/trial_expired_screen.dart' show TrialExpiredScreen, TrialPendingScreen;
import 'services/trusted_roots.dart';
import 'services/email_attachment_cache.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/email_outbox.dart';
import 'services/local_db.dart';
import 'services/permission_service.dart';
import 'services/trial_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'widgets/common/app_shell.dart';
import 'widgets/common/update_widgets.dart' show UpdateRequiredGate;

/// Global auth token — null means not logged in, non-null means authenticated.
late final ValueNotifier<String?> authTokenNotifier;

/// Global logged-in user's display name — updated on login and profile save.
final userNameNotifier = ValueNotifier<String>('');

/// Global logged-in user's id — used for "is this assigned to me" checks
/// (e.g. the service-ticket acknowledge button). Null until login/profile
/// resolves it.
final userIdNotifier = ValueNotifier<int?>(null);

/// Logged-in user's profile photo URL (null = show initials) and location
/// (region, falling back to zone) — drive the top bar / sidebar identity.
/// Set via [applyUserIdentity] from login, startup and profile changes.
final userAvatarUrlNotifier = ValueNotifier<String?>(null);
final userLocationNotifier = ValueNotifier<String?>(null);

/// Push a UserResource-shaped map (login `user`, /auth/me) into the global
/// identity notifiers the app shell listens to.
void applyUserIdentity(Map<dynamic, dynamic> user) {
  final name = user['name'] as String?;
  if (name != null && name.isNotEmpty) userNameNotifier.value = name;
  userAvatarUrlNotifier.value = user['avatar_url'] as String?;
  final region = (user['region'] as String?)?.trim();
  final zone = (user['zone'] as String?)?.trim();
  userLocationNotifier.value =
      (region != null && region.isNotEmpty) ? region : ((zone != null && zone.isNotEmpty) ? zone : null);
}

/// Role names are shown in ALL CAPS app-wide: 'sales_manager' -> 'SALES MANAGER'.
String roleDisplayName(String role) => role.replaceAll('_', ' ').trim().toUpperCase();

/// Global trial status — checked once on startup.
late final ValueNotifier<TrialStatus> trialNotifier;

/// Global logged-in user's role — drives sidebar filtering and screen guards.
final userRoleNotifier = ValueNotifier<String>('');

/// Global effective permissions (key -> scope) — see EffectivePermissionResolver
/// on the backend. Refreshed on login and app startup, same lifecycle as
/// [userRoleNotifier]. Every data-bearing call this only gates client-side
/// rendering with is independently re-checked server-side — a stale local
/// copy is a UI-convenience risk only, never a security boundary.
final userPermissionsNotifier = ValueNotifier<Map<String, String>>({});

/// Whether the current user's effective permissions include [key].
bool can(String key) => userPermissionsNotifier.value.containsKey(key);

/// The scope ('none'|'masked'|'own'|'team'|'all') the current user holds
/// [key] at, or null if they don't hold it at all.
String? scopeOf(String key) => userPermissionsNotifier.value[key];

Future<void> refreshPermissions() async {
  try {
    final perms = await PermissionService.instance.fetchMine();
    final map = {for (final p in perms) p.key: p.scope};
    userPermissionsNotifier.value = map;
    // Remembered per user so the next start renders with them at once.
    final uid = userIdNotifier.value;
    if (uid != null) LocalDb.instance?.setJson('$uid', _permissionsKey, map);
  } catch (_) {
    // Non-fatal — screens gated by can() just keep whatever they last had
    // until the next successful fetch (e.g. next login).
  }
}

const _permissionsKey = 'permissions';

/// The permissions remembered for [userId] at the last successful refresh.
Map<String, String>? _cachedPermissions(int userId) {
  try {
    final raw = LocalDb.instance?.getJson('$userId', _permissionsKey);
    if (raw is! Map || raw.isEmpty) return null;
    return raw.map((k, v) => MapEntry('$k', '$v'));
  } catch (_) {
    return null;
  }
}

/// Deletes everything stored on this device for the signed-in user
/// (cached responses, permissions, last-seen markers, failed sends). Runs on
/// logout, a 401 force-logout and after the user's own password changes.
void wipeLocalUserData() {
  final uid = userIdNotifier.value;
  try {
    if (uid != null) LocalDb.instance?.wipeUser(uid);
  } catch (_) {}
  if (uid != null) EmailAttachmentCache.instance.wipeUser(uid).catchError((_) {});
  ApiClient.instance.diskCache.resetSession();
  EmailOutbox.instance.reload();
}

/// Unread notification count — updated by BackgroundSync; drives the bell badge.
final notificationCountNotifier = ValueNotifier<int>(0);

/// The Email nav badge: unread inbox mail across the user's accounts
/// (BackgroundSync, EmailScreen) and sends that failed and wait in the
/// outbox (EmailOutbox).
final emailBadgeNotifier = ValueNotifier<({int unread, int failed})>((unread: 0, failed: 0));

const _screenKeys = [
  'dashboard', 'approvals',
  'inventory', 'finance', 'staff', 'my_leave', 'reports', 'settings',
  'sales', 'customers', 'revenue', 'email', 'hr_approvals', 'hr_settings',
  'hr_dashboard', 'hr_directory', 'hr_recruitment', 'hr_leave_calendar',
  'hr_attendance', 'hr_payroll', 'hr_reports', 'notifications', 'delegations',
  'notification_templates', 'activity_log',
  // 2026-10-23: Quotations on its own (engineers) and Staff Contributions.
  'quotations', 'contributions',
  // 2026-10-26: Purchases menu (Clickhuduma's), above Sales.
  'purchases',
  // Section 16: Vendor Fees/Delivery Jobs/Vendors registry, one combined
  // screen key like 'finance' or 'inventory' already are.
  'vendor_fees',
  // Section 19: Tenders & Contracts + Device Registrations share one gate
  // (screens.tenders), like 'inventory' covers its sub-screens.
  'tenders',
  // Section 18: import/export shipments (screens.shipments).
  'shipments',
  // 2026-11-03: Letters on the letterhead (everyone, see _universalScreenKeys).
  'letters',
  // 2026-11-04: in-app chat (everyone; the API decides who can be messaged).
  'chats',
];

/// Returns the set of screen keys accessible for the current user. Primarily
/// driven by their effective `screens.*` permissions (see PermissionSeeder's
/// seedScreenPermissions() on the backend) — so a brand-new role built via
/// the Role Builder can see relevant screens immediately, with no Flutter
/// redeploy needed. Falls back to the pre-Phase-1 hardcoded table below only
/// when the user holds none of those permissions at all (e.g. the
/// permissions fetch failed, or they're on an older backend that predates
/// this seed step) — [role] is only consulted in that fallback path.
Set<String>? allowedScreenKeys(String role) {
  final perms = userPermissionsNotifier.value;
  if (perms.containsKey('authority.admin_tier')) return null; // full access
  final fromPermissions = _screenKeys.where((k) => perms.containsKey('screens.$k')).toSet();
  if (fromPermissions.isNotEmpty) return {...fromPermissions, ..._universalScreenKeys};
  final legacy = _legacyAllowedScreenKeys(role);
  return legacy == null ? null : {...legacy, ..._universalScreenKeys};
}

/// Every role gets these whatever its screens.* grants — everyone has their
/// own mailbox, notifications and meetings (the APIs only ever serve the
/// caller's own mail, and the meetings they attend unless meetings.manage).
/// My Expenses too (2026-10-24): everyone submits their own expenses to their manager.
const _universalScreenKeys = {'email', 'chats', 'notifications', 'meetings', 'my_expenses', 'letters'};

Set<String>? _legacyAllowedScreenKeys(String role) => switch (role) {
  'super_admin' || 'admin' => null,
  'cto'            => {'dashboard', 'approvals', 'inventory', 'finance', 'tenders', 'shipments', 'staff', 'my_leave', 'my_travel_plans', 'reports', 'settings', 'notifications'},
  'technician'     => {'dashboard', 'my_leave', 'my_travel_plans', 'reports', 'settings', 'notifications'},
  'team_leader'    => {'dashboard', 'approvals', 'staff', 'my_leave', 'my_travel_plans', 'reports', 'settings', 'notifications'},
  'sales_manager' || 'sales' => {'dashboard', 'sales', 'purchases', 'customers', 'revenue', 'email', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
  'finance_manager' || 'finance' => {'dashboard', 'revenue', 'finance', 'vendor_fees', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
  'cs'             => {'dashboard', 'customers', 'email', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
  'storekeeper'    => {'dashboard', 'inventory', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
  // HR does not get the operational 'staff' (task-assignment board) key —
  // that's Operations' job. The hr_* keys below are HR's own dedicated
  // section (dashboard, personal-info directory, recruitment, leave
  // calendar, attendance, payroll, reports).
  'hr'             => {
    'dashboard', 'my_leave', 'hr_dashboard', 'hr_directory', 'hr_recruitment',
    'hr_leave_calendar', 'hr_attendance', 'hr_payroll', 'hr_approvals',
    'hr_reports', 'hr_settings', 'reports', 'settings', 'notifications',
  },
  'procurement_manager' => {'dashboard', 'approvals', 'inventory', 'vendor_fees', 'tenders', 'shipments', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
  // No 'staff' (the task-assignment board) — accountant handles payments,
  // not staff task assignment.
  'accountant'     => {'dashboard', 'approvals', 'revenue', 'finance', 'vendor_fees', 'my_leave', 'reports', 'settings', 'notifications'},
  'logistics'      => {'dashboard', 'inventory', 'sales', 'vendor_fees', 'shipments', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
  // Head of the Administrative Wing: HR + sales staff work + meetings.
  'administrator'  => {
    'dashboard', 'sales', 'customers', 'revenue', 'staff', 'my_leave',
    'hr_dashboard', 'hr_directory', 'hr_recruitment', 'hr_leave_calendar', 'hr_attendance', 'hr_payroll',
    'hr_approvals', 'hr_reports', 'hr_settings', 'reports', 'settings', 'notifications',
  },
  _                => {'dashboard', 'staff', 'my_leave', 'reports', 'settings', 'notifications'},
};

/// Returns the default landing screen key for [role].
String defaultScreenKey(String role) => switch (role) {
  'cto' || 'team_leader'           => 'approvals',
  'sales_manager' || 'sales'      => 'sales_dashboard',
  'cs'                             => 'customers',
  'storekeeper'                    => 'inventory',
  // Not 'approvals' — the PO chain they created doesn't route back through
  // them for any of its 4 stages (sales_manager/director/accountant), so
  // that page shows nothing they can act on. Inventory is where their real
  // authority (create_po, approve_requisition) actually lives.
  'procurement_manager'            => 'inventory',
  'accountant'                     => 'approvals',
  'logistics'                      => 'inventory',
  _                                => 'dashboard',
};

/// Whether the current user holds [key]. Driven by the effective
/// permissions the backend resolved (so a Role Builder change or a per-user
/// override — e.g. the CTO's admin-tier — shows up without a client
/// release); falls back to the role's built-in grants only until the
/// permission set has loaded. The backend re-checks every action regardless.
bool _holds(String key, String role, Set<String> legacyRoles) =>
    userPermissionsNotifier.value.isEmpty ? legacyRoles.contains(role) : can(key);

/// Approve/reject quotations and sales orders over a rep's discount limit —
/// User::hasSalesApprovalAuthority() on the backend.
bool hasSalesApprovalAuthority(String role) =>
    _holds('sales.approve_order', role, const {'super_admin', 'admin', 'sales_manager'});

/// Send a quotation to the client — User::hasSalesIssueQuotationAuthority().
/// Engineers who only prepare quotations don't hold it.
bool hasSalesIssueQuotationAuthority(String role) =>
    _holds('sales.issue_quotation', role, const {'super_admin', 'admin', 'sales_manager', 'sales'});

/// Convert quotations to orders — User::hasSalesEditAuthority().
bool hasSalesEditAuthority(String role) =>
    _holds('sales.edit', role, const {'super_admin', 'admin', 'sales_manager', 'sales'});

/// User::hasCtoApprovalAuthority() — the CTO stage of approvals.
bool hasCtoApprovalAuthority(String role) =>
    _holds('authority.cto_tier', role, const {'super_admin', 'admin', 'cto'});

/// User::hasTeamLeadAuthority().
bool hasTeamLeadAuthority(String role) =>
    _holds('authority.team_lead_tier', role, const {'super_admin', 'admin', 'cto', 'team_leader'});

/// Admin tier — sees and runs everything (User::hasDirectorAuthority()).
/// The Director, and the CTO through a per-user override. NOT final
/// authorisation of money: that's [hasFinalMoneyAuthority].
bool hasDirectorAuthority(String role) =>
    _holds('authority.admin_tier', role, const {'super_admin', 'admin'});

/// The Director's money sign-off (User::hasFinalMoneyAuthority()) —
/// Director-stage approval of expenses, POs, per diems, vendor bills/fees,
/// payroll, salary changes and credit notes, and releasing payments.
bool hasFinalMoneyAuthority(String role) =>
    _holds('authority.final_money_approval', role, const {'super_admin', 'admin'});

/// The procurement.create_po grant.
bool hasProcurementCreateAuthority(String role) =>
    _holds('procurement.create_po', role, const {'super_admin', 'admin', 'procurement_manager'});

/// The procurement.approve_po_sales_stage grant.
bool hasProcurementSalesStageAuthority(String role) =>
    _holds('procurement.approve_po_sales_stage', role, const {'super_admin', 'admin', 'sales_manager'});

/// The procurement.initiate_payment grant (accountant + Director) — never
/// implied by admin tier, so the CTO doesn't get payment handling.
bool hasAccountantAuthority(String role) =>
    _holds('procurement.initiate_payment', role, const {'super_admin', 'admin', 'accountant'});

/// The staff.manage grant (create/edit/deactivate staff, change roles).
bool hasStaffManageAuthority(String role) =>
    _holds('staff.manage', role, const {'super_admin', 'admin', 'hr'});

/// The tasks.manage_board grant (create/reassign/delete a general,
/// non-ticket task on the Staff screen's task board). This only toggles the
/// button; the backend enforces the real check regardless.
bool hasTaskManageAuthority(String role) => _holds('tasks.manage_board', role, const {
  'super_admin', 'admin', 'sales_manager', 'finance_manager', 'cto', 'team_leader',
});

/// Derive initials from a display name (e.g. "Joseph Mwakasege" → "JM").
String nameInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  if (parts.first.isNotEmpty) return parts.first[0].toUpperCase();
  return '?';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before any request: trust the server's certificate root even on PCs
  // whose Windows root store doesn't have it yet (see trusted_roots.dart).
  await installBundledRootCertificates();

  // The local store first: the remembered trial status, permissions and
  // server address below all come from it.
  await LocalDb.open();

  final (stored, storedName, storedRoleRaw, storedId) = await (
    AuthService.instance.getStoredToken(),
    AuthService.instance.getStoredUserName(),
    AuthService.instance.getStoredRole(),
    AuthService.instance.getStoredUserId(),
  ).wait;
  var storedRole = storedRoleRaw;
  authTokenNotifier = ValueNotifier<String?>(stored);
  userNameNotifier.value = storedName ?? '';
  userIdNotifier.value   = storedId;

  // If already logged in but role or id wasn't cached (e.g. logged in before
  // that storage was introduced), fetch it from /auth/me now before rendering.
  if (stored != null && (storedRole == null || storedRole.isEmpty || storedId == null)) {
    final profile = await AuthService.instance.getProfile();
    storedRole = profile?['role'] as String?;
    final freshName = profile?['name'] as String?;
    if (freshName != null && freshName.isNotEmpty) {
      userNameNotifier.value = freshName;
    }
    final freshId = profile?['id'];
    if (freshId is num) userIdNotifier.value = freshId.toInt();
  }

  userRoleNotifier.value = storedRole ?? '';

  // The Email badge belongs to whoever is signed in.
  EmailOutbox.instance.reload();
  userIdNotifier.addListener(() {
    emailBadgeNotifier.value = (unread: 0, failed: 0);
    EmailOutbox.instance.reload();
  });

  // Clear the shell's photo/location on logout so the next user never
  // briefly sees the previous one's. Logout and a 401 force-logout both land
  // here: also wipe what this device stored for the user, and stop writing
  // anything more for them.
  authTokenNotifier.addListener(() {
    if (authTokenNotifier.value == null) {
      userAvatarUrlNotifier.value = null;
      userLocationNotifier.value = null;
      wipeLocalUserData();
      userIdNotifier.value = null;
    }
  });
  // Photo/location aren't persisted locally — fetch them in the background
  // so the first frame isn't held up by the network.
  if (stored != null) {
    AuthService.instance.getProfile().then((p) {
      if (p != null) applyUserIdentity(p);
    });
  }

  // Permission refresh, trial check, and local-notifier setup are all
  // independent of each other — run them concurrently instead of stacked
  // sequential awaits, so a slow/unreachable network only costs one wait
  // before the first frame renders, not three added together. All three are
  // already internally timeout-bounded and catch their own errors.
  //
  // With a remembered trial status / permission set (the usual case) the
  // first frame doesn't wait on the network at all: it renders with those
  // and the fresh answers replace them when they arrive.
  final trialFuture = TrialService.instance.check();
  final cachedTrial = TrialService.instance.cachedUsable();
  final uid = userIdNotifier.value;
  final cachedPerms = stored != null && uid != null ? _cachedPermissions(uid) : null;
  if (cachedPerms != null) userPermissionsNotifier.value = cachedPerms;
  final otherFutures = <Future<void>>[
    localNotifier.setup(appName: 'Hypermed'),
    // Lets a clicked pop-up bring the window forward (BackgroundSync).
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      windowManager.ensureInitialized().catchError((_) {}),
    if (stored != null && cachedPerms == null) refreshPermissions(),
  ];
  if (stored != null && cachedPerms != null) unawaited(refreshPermissions());
  await Future.wait(otherFutures);
  if (cachedTrial != null) {
    trialNotifier = ValueNotifier<TrialStatus>(cachedTrial);
    unawaited(trialFuture.then((fresh) {
      if (fresh.isFallback) return; // offline — keep the remembered status
      TrialService.instance.remember(fresh);
      if (!fresh.sameAs(trialNotifier.value)) trialNotifier.value = fresh;
    }));
  } else {
    final fresh = await trialFuture;
    TrialService.instance.remember(fresh);
    trialNotifier = ValueNotifier<TrialStatus>(fresh);
  }

  // Installs an update downloaded last session ("install on next start")
  // before any UI appears — the installer relaunches the app afterwards.
  if (await UpdateService.instance.start()) exit(0);
  // Company-wide update policy lives in backend settings, so it needs a
  // session: read it now if logged in, and again after each login.
  if (authTokenNotifier.value != null) unawaited(UpdateService.instance.refreshPolicy());
  authTokenNotifier.addListener(() {
    if (authTokenNotifier.value != null) unawaited(UpdateService.instance.refreshPolicy());
  });

  runApp(const HypermedApp());
}

class HypermedApp extends StatelessWidget {
  const HypermedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) {
        // theme/darkTheme are set to the same ThemeData for every mode
        // except plain light/dark, so themeMode only actually matters for
        // that pair — the other modes are single fixed palettes.
        final resolvedTheme = AppTheme.of(mode);
        return MaterialApp(
        title: 'Hypermed',
        debugShowCheckedModeBanner: false,
        theme:     resolvedTheme,
        darkTheme: resolvedTheme,
        themeMode: mode == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light,
        // App-wide text bump — multiplies on top of the device's own text
        // scale rather than replacing it, so OS accessibility settings still
        // apply. User-adjustable via Settings → Preferences → Text Size.
        builder: (context, child) => ValueListenableBuilder<TextSizePref>(
          valueListenable: textSizeNotifier,
          builder: (_, sizePref, _) {
            final mq = MediaQuery.of(context);
            final deviceFactor = mq.textScaler.scale(1.0);
            // Phones: dialogs keep a 16 px side margin instead of Material's
            // 40 px, which would spend a fifth of the width on empty space.
            final theme = Theme.of(context);
            final scoped = mq.size.width < 600
                ? Theme(
                    data: theme.copyWith(dialogTheme: theme.dialogTheme.copyWith(
                        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24))),
                    child: child!,
                  )
                : child!;
            return MediaQuery(
              data: mq.copyWith(
                  textScaler: TextScaler.linear(deviceFactor * sizePref.scale)),
              child: scoped,
            );
          },
        ),
        home: UpdateRequiredGate(child: ValueListenableBuilder<TrialStatus>(
          valueListenable: trialNotifier,
          builder: (_, trial, _) {
            // Awaiting admin approval
            if (trial.isPending) {
              return TrialPendingScreen(status: trial);
            }
            // Trial expired / revoked → show locked screen regardless of auth
            if (!trial.isValid) {
              return TrialExpiredScreen(status: trial);
            }
            // Normal auth gate
            return ValueListenableBuilder<String?>(
              valueListenable: authTokenNotifier,
              builder: (_, token, _) =>
                  token == null ? const LoginScreen() : const AppShell(),
            );
          },
        )),
      );
      },
    );
  }
}
