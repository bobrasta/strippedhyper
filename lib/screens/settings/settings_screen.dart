import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart'
    show
        authTokenNotifier,
        userNameNotifier,
        userRoleNotifier,
        userPermissionsNotifier,
        userAvatarUrlNotifier,
        applyUserIdentity,
        allowedScreenKeys,
        hasFinalMoneyAuthority,
        userIdNotifier,
        wipeLocalUserData,
        can;
import '../../models/expense.dart';
import '../../models/permission.dart';
import '../../services/api_client.dart';
import '../../utils/pdf_download.dart';
import '../../services/auth_service.dart';
import '../../services/expense_service.dart';
import '../../services/performance_service.dart';
import '../../services/permission_service.dart';
import '../../services/role_service.dart';
import '../../services/setting_service.dart';
import '../../services/staff_service.dart';
import 'org_chart_editor.dart';
import 'roles_graph_view.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/csv_export.dart';
import '../../utils/format.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dropdown.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../theme/app_palette.dart';
import '../../widgets/common/update_widgets.dart' show AppUpdatesCard;
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';
import '../../services/chat_controller.dart';
import '../chat/chat_review_screen.dart';

// e.g. 'sales_manager' -> 'Sales Manager' —shared by the Roles tab and the
// Invite dialog's role dropdown.
String _roleLabel(String name) => name.replaceAll('_', ' ').trim().toUpperCase();
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onNavigateTo});
  final void Function(String key)? onNavigateTo;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _section = 0;
  int _tab = 0;

  // Profile
  bool _loadingProfile = true;
  bool _showInvite = false;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  // Statutory IDs and next of kin (2026-10-24), keyed by their API field.
  final _idCtrls = {
    for (final k in const ['nssf_number', 'nida_number', 'tin_number',
        'next_of_kin_name', 'next_of_kin_phone', 'next_of_kin_relationship'])
      k: TextEditingController(),
  };
  final _newQualCtrl = TextEditingController();
  List<String> _qualifications = [];
  final _oldPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  bool _savingProfile = false;
  bool _savingPw = false;
  String? _profileMsg;
  String? _pwMsg;

  // Identity header — real fields only, read-only/HR-managed, populated
  // from the same GET /auth/me payload the profile form already fetches.
  String? _avatarUrl;
  bool _uploadingAvatar = false;
  String? _managerName;
  String? _positionTitle;
  String? _positionDepartment;
  String? _region;
  String? _zone;
  String? _hireDate;
  MyPerformance? _myPerformance;

  // Section 15.7: payment details — required before any travel plan can
  // be submitted (PerDiemController::store() 422s without one).
  final _paymentProviderCtrl = TextEditingController();
  final _paymentAccountNumberCtrl = TextEditingController();
  final _paymentAccountNameCtrl = TextEditingController();
  bool _savingPaymentProfile = false;
  String? _paymentProfileMsg;

  // Team members
  bool _loadingMembers = true;
  List<StaffMember> _staffList = [];
  String? _memberError;
  final _memberSearchCtrl = TextEditingController();
  String _memberSearch = '';
  String _memberRoleFilter = 'All';

  List<StaffMember> get _filteredStaffList {
    var list = _staffList;
    if (_memberRoleFilter != 'All') {
      list = list.where((m) => m.role == _memberRoleFilter).toList();
    }
    final q = _memberSearch.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (m) =>
                m.name.toLowerCase().contains(q) ||
                (m.email?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }
    return list;
  }

  // Approvals
  bool _loadingApprovals = true;
  final _thresholdCtrl = TextEditingController();
  bool _savingThreshold = false;
  // Chat review (settings key messaging_admin_access): off unless '1'.
  bool _chatReviewOn = false;
  bool _savingChatReview = false;
  List<ExpenseCategory> _expenseCategories = [];

  // Section 15.6/15.2: travel plan signature-block role labels + default
  // per-diem rate — Settings-adjustable per the spec, not hardcoded.
  final _perDiemDefaultRateCtrl = TextEditingController();
  final _sigTeamLeadCtrl = TextEditingController();
  final _sigCtoCtrl = TextEditingController();
  final _sigAccountantCtrl = TextEditingController();
  final _sigFinalReleaseCtrl = TextEditingController();
  bool _savingTravelPlanSettings = false;
  String? _travelPlanSettingsMsg;

  // Roles & Permissions
  bool _loadingRoles = true;
  List<RoleSummary> _roles = [];
  Map<String, List<PermissionCatalogItem>> _permissionCatalog = {};
  String? _rolesError;
  bool _rolesGraphView = false;

  // Activity / audit log (permission overrides)
  bool _loadingAudit = true;
  List<UserPermissionOverride> _auditLog = [];
  bool _auditThisWeekOnly = false;

  List<UserPermissionOverride> get _filteredAuditLog {
    if (!_auditThisWeekOnly) return _auditLog;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _auditLog.where((o) {
      final dt = o.createdAt != null ? DateTime.tryParse(o.createdAt!) : null;
      return dt != null && dt.isAfter(cutoff);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: this screen's several independent pieces
    // (profile, members, approvals, roles, audit log) each seed from their
    // own cache (if present) so a return visit shows the last-known data
    // immediately instead of blanking to a spinner, then each quietly
    // refreshes in the background — see MachineService's own doc comment
    // for the full reasoning. Direct field assignment (no setState needed
    // pre-first-build), matching each cached source's own parsing.
    final cachedProfile = AuthService.cachedProfile;
    if (cachedProfile != null) {
      _nameCtrl.text = cachedProfile['name'] as String? ?? '';
      _emailCtrl.text = cachedProfile['email'] as String? ?? '';
      _phoneCtrl.text = cachedProfile['phone'] as String? ?? '';
      _avatarUrl = cachedProfile['avatar_url'] as String?;
      _managerName = cachedProfile['manager_name'] as String?;
      _positionTitle = cachedProfile['position_title'] as String?;
      _positionDepartment = cachedProfile['position_department'] as String?;
      _region = cachedProfile['region'] as String?;
      _zone = cachedProfile['zone'] as String?;
      _hireDate = cachedProfile['hire_date'] as String?;
      _bioCtrl.text = cachedProfile['bio'] as String? ?? '';
      for (final e in _idCtrls.entries) {
        e.value.text = cachedProfile[e.key] as String? ?? '';
      }
      _qualifications = ((cachedProfile['qualifications'] as List?) ?? [])
          .cast<String>();
      final cachedPaymentProfile =
          cachedProfile['payment_profile'] as Map<String, dynamic>?;
      if (cachedPaymentProfile != null) {
        _paymentProviderCtrl.text =
            cachedPaymentProfile['provider'] as String? ?? '';
        _paymentAccountNumberCtrl.text =
            cachedPaymentProfile['account_number'] as String? ?? '';
        _paymentAccountNameCtrl.text =
            cachedPaymentProfile['account_name'] as String? ?? '';
      }
      _loadingProfile = false;
    }
    final cachedPerf = PerformanceService.cachedMine;
    if (cachedPerf != null) _myPerformance = cachedPerf;

    final cachedStaff = StaffService.instance.staffNotifier.value;
    if (cachedStaff.isNotEmpty) {
      _staffList = cachedStaff;
      _loadingMembers = false;
    }

    final cachedSettings = SettingService.cachedAll;
    final cachedExpenseCategories = ExpenseService.cachedCategories;
    if (cachedSettings != null && cachedExpenseCategories != null) {
      final sigLabelsRaw = cachedSettings['per_diem_signature_role_labels'];
      Map<String, dynamic> sigLabels = {};
      if (sigLabelsRaw != null && sigLabelsRaw.isNotEmpty) {
        try {
          sigLabels = jsonDecode(sigLabelsRaw) as Map<String, dynamic>;
        } catch (_) {}
      }
      _thresholdCtrl.text =
          cachedSettings['expense_director_threshold'] ?? '3000000';
      _expenseCategories = cachedExpenseCategories;
      _perDiemDefaultRateCtrl.text =
          cachedSettings['per_diem_default_daily_rate'] ?? '80000';
      _sigTeamLeadCtrl.text =
          sigLabels['team_lead'] as String? ?? 'Technical supervisor';
      _sigCtoCtrl.text = sigLabels['cto'] as String? ?? 'CTO';
      _sigAccountantCtrl.text =
          sigLabels['accountant_initiate'] as String? ?? 'Finance';
      _sigFinalReleaseCtrl.text =
          sigLabels['final_release'] as String? ?? 'Managing director';
      _loadingApprovals = false;
    }

    final cachedRoles = RoleService.cachedList;
    final cachedCatalog = RoleService.cachedCatalog;
    if (cachedRoles != null && cachedCatalog != null) {
      _roles = cachedRoles;
      _permissionCatalog = cachedCatalog;
      _loadingRoles = false;
    }

    final cachedAudit = PermissionService.cachedAllOverrides;
    if (cachedAudit != null) {
      _auditLog = cachedAudit;
      _loadingAudit = false;
    }

    _loadProfile();
    _loadMembers();
    _loadApprovals();
    _loadRoles();
    _loadAudit();
  }

  Future<void> _loadAudit() async {
    // The audit log is roles.manage-only server-side; don't fire a request
    // that's guaranteed to 403 for everyone else. (Empty map = permissions
    // not fetched yet — try anyway rather than hide it from an admin.)
    if (userPermissionsNotifier.value.isNotEmpty && !can('roles.manage')) {
      if (_loadingAudit) setState(() => _loadingAudit = false);
      return;
    }
    setState(() {
      if (_auditLog.isEmpty) _loadingAudit = true;
    });
    try {
      final log = await PermissionService.instance.allOverrides();
      if (mounted)
        setState(() {
          _auditLog = log;
          _loadingAudit = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loadingAudit = false);
    }
  }

  Future<void> _loadRoles() async {
    setState(() {
      if (_roles.isEmpty) _loadingRoles = true;
      _rolesError = null;
    });
    try {
      final rolesF = RoleService.instance.list();
      final catalogF = RoleService.instance.catalog();
      final roles = await rolesF;
      final catalog = await catalogF;
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _permissionCatalog = catalog;
        _loadingRoles = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _rolesError = friendlyError(e);
          _loadingRoles = false;
        });
    }
  }

  Future<void> _createRole(String name) async {
    try {
      await RoleService.instance.create(name);
      if (mounted) showSuccessToast(context, 'Role "$name" created.');
      await _loadRoles();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _saveRolePermissions(RoleSummary role, List<String> keys) async {
    try {
      await RoleService.instance.syncPermissions(role.id, keys);
      if (mounted)
        showSuccessToast(context, 'Permissions updated for "${role.name}".');
      await _loadRoles();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _deleteRole(RoleSummary role) async {
    try {
      await RoleService.instance.delete(role.id);
      if (mounted) showSuccessToast(context, 'Role "${role.name}" deleted.');
      await _loadRoles();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  Future<void> _loadApprovals() async {
    setState(() {
      if (_expenseCategories.isEmpty) _loadingApprovals = true;
    });
    try {
      final results = await Future.wait([
        SettingService.instance.all(),
        ExpenseService.instance.categories(),
      ]);
      if (!mounted) return;
      final settings = results[0] as Map<String, String?>;
      final sigLabelsRaw = settings['per_diem_signature_role_labels'];
      Map<String, dynamic> sigLabels = {};
      if (sigLabelsRaw != null && sigLabelsRaw.isNotEmpty) {
        try {
          sigLabels = jsonDecode(sigLabelsRaw) as Map<String, dynamic>;
        } catch (_) {}
      }
      setState(() {
        _thresholdCtrl.text =
            settings['expense_director_threshold'] ?? '3000000';
        _chatReviewOn = settings['messaging_admin_access'] == '1';
        _expenseCategories = results[1] as List<ExpenseCategory>;
        _perDiemDefaultRateCtrl.text =
            settings['per_diem_default_daily_rate'] ?? '80000';
        _sigTeamLeadCtrl.text =
            sigLabels['team_lead'] as String? ?? 'Technical supervisor';
        _sigCtoCtrl.text = sigLabels['cto'] as String? ?? 'CTO';
        _sigAccountantCtrl.text =
            sigLabels['accountant_initiate'] as String? ?? 'Finance';
        _sigFinalReleaseCtrl.text =
            sigLabels['final_release'] as String? ?? 'Managing director';
        _loadingApprovals = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingApprovals = false);
    }
  }

  Future<void> _saveThreshold() async {
    if (_savingThreshold) return;
    setState(() => _savingThreshold = true);
    try {
      await SettingService.instance.set(
        'expense_director_threshold',
        _thresholdCtrl.text.trim(),
      );
      if (mounted) {
        setState(() => _savingThreshold = false);
        showSuccessToast(context, 'Threshold updated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingThreshold = false);
        showErrorToast(context, e);
      }
    }
  }

  Future<void> _setChatReview(bool on) async {
    if (_savingChatReview) return;
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: dCtx.pal.surface1,
          title: Text('Switch chat review on?', style: AppTheme.bodyStrong),
          content: Text(
            'People you give the "Review Staff Chats" permission will be able to read any chat, '
            'including deleted messages and earlier versions of edited ones. Every chat shows staff '
            'a notice that review is on, and every read goes into the Activity Log.',
            style: AppTheme.bodySub.copyWith(fontSize: 12.5)),
          actions: [
            AppButton(label: 'Cancel', small: true, variant: BtnVariant.ghost, onPressed: () => Navigator.of(dCtx).pop(false)),
            AppButton(label: 'Switch on', small: true, variant: BtnVariant.primary, onPressed: () => Navigator.of(dCtx).pop(true)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _savingChatReview = true);
    try {
      await SettingService.instance.set('messaging_admin_access', on ? '1' : '0');
      if (!mounted) return;
      setState(() => _chatReviewOn = on);
      showSuccessToast(context, on ? 'Chat review is on.' : 'Chat review is off.');
      await ChatController.instance.reloadSettings();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _savingChatReview = false);
    }
  }

  Future<void> _saveTravelPlanSettings() async {
    if (_savingTravelPlanSettings) return;
    setState(() {
      _savingTravelPlanSettings = true;
      _travelPlanSettingsMsg = null;
    });
    try {
      await SettingService.instance.set(
        'per_diem_default_daily_rate',
        _perDiemDefaultRateCtrl.text.trim(),
      );
      await SettingService.instance.set(
        'per_diem_signature_role_labels',
        jsonEncode({
          'team_lead': _sigTeamLeadCtrl.text.trim(),
          'cto': _sigCtoCtrl.text.trim(),
          'accountant_initiate': _sigAccountantCtrl.text.trim(),
          'final_release': _sigFinalReleaseCtrl.text.trim(),
        }),
      );
      if (mounted)
        setState(() {
          _savingTravelPlanSettings = false;
          _travelPlanSettingsMsg = 'Saved.';
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _savingTravelPlanSettings = false;
          _travelPlanSettingsMsg = 'Save failed.';
        });
    }
  }

  Future<void> _toggleCategoryApproval(ExpenseCategory cat, bool value) async {
    final previous = List<ExpenseCategory>.from(_expenseCategories);
    setState(() {
      _expenseCategories = _expenseCategories
          .map(
            (c) => c.id == cat.id
                ? ExpenseCategory(
                    id: c.id,
                    name: c.name,
                    accountId: c.accountId,
                    requiresDirectorApproval: value,
                  )
                : c,
          )
          .toList();
    });
    try {
      await ExpenseService.instance.setCategoryRequiresDirector(cat.id, value);
    } catch (e) {
      if (mounted) {
        setState(() => _expenseCategories = previous);
        showErrorToast(context, e);
      }
    }
  }

  Future<void> _loadMembers({bool force = false}) async {
    setState(() {
      if (_staffList.isEmpty) _loadingMembers = true;
      _memberError = null;
    });
    try {
      final list = await StaffService.instance.list(force: force);
      if (mounted)
        setState(() {
          _staffList = list;
          _loadingMembers = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loadingMembers = false;
          _memberError = friendlyError(e);
        });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    for (final c in _idCtrls.values) {
      c.dispose();
    }
    _newQualCtrl.dispose();
    _oldPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _paymentProviderCtrl.dispose();
    _paymentAccountNumberCtrl.dispose();
    _paymentAccountNameCtrl.dispose();
    _thresholdCtrl.dispose();
    _perDiemDefaultRateCtrl.dispose();
    _sigTeamLeadCtrl.dispose();
    _sigCtoCtrl.dispose();
    _sigAccountantCtrl.dispose();
    _sigFinalReleaseCtrl.dispose();
    _memberSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await AuthService.instance.getProfile();
      if (profile != null) applyUserIdentity(profile);
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          if (profile != null) {
            _nameCtrl.text = profile['name'] as String? ?? '';
            _emailCtrl.text = profile['email'] as String? ?? '';
            _phoneCtrl.text = profile['phone'] as String? ?? '';
            _avatarUrl = profile['avatar_url'] as String?;
            _managerName = profile['manager_name'] as String?;
            _positionTitle = profile['position_title'] as String?;
            _positionDepartment = profile['position_department'] as String?;
            _region = profile['region'] as String?;
            _zone = profile['zone'] as String?;
            _hireDate = profile['hire_date'] as String?;
            _bioCtrl.text = profile['bio'] as String? ?? '';
            for (final e in _idCtrls.entries) {
              e.value.text = profile[e.key] as String? ?? '';
            }
            _qualifications = ((profile['qualifications'] as List?) ?? [])
                .cast<String>();
            final paymentProfile =
                profile['payment_profile'] as Map<String, dynamic>?;
            if (paymentProfile != null) {
              _paymentProviderCtrl.text =
                  paymentProfile['provider'] as String? ?? '';
              _paymentAccountNumberCtrl.text =
                  paymentProfile['account_number'] as String? ?? '';
              _paymentAccountNameCtrl.text =
                  paymentProfile['account_name'] as String? ?? '';
            }
          }
        });
      }
    } catch (_) {
      // getProfile() already catches internally and returns null, but guard
      // here too so a future refactor of that method can't leave this
      // section's spinner stuck forever.
      if (mounted) setState(() => _loadingProfile = false);
    }
    _loadMyPerformance();
  }

  // Header stat strip — reuses the same /performance/mine data the
  // separate My Performance screen already shows, rather than a second
  // computation. Silently absent if the call fails or the caller has
  // neither field nor sales activity (no fabricated fallback numbers).
  Future<void> _loadMyPerformance() async {
    try {
      final perf = await PerformanceService.instance.mine();
      if (mounted) setState(() => _myPerformance = perf);
    } catch (_) {
      // Stat strip just doesn't render — not worth surfacing an error for
      // what is a secondary, decorative part of the header.
    }
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    setState(() {
      _savingProfile = true;
      _profileMsg = null;
    });
    try {
      await ApiClient.instance.dio.put(
        '/auth/profile',
        data: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'bio': _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          'qualifications': _qualifications,
          for (final e in _idCtrls.entries)
            e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
        },
      );
      await AuthService.instance.updateStoredName(_nameCtrl.text.trim());
      userNameNotifier.value = _nameCtrl.text.trim();
      if (mounted)
        setState(() {
          _savingProfile = false;
          _profileMsg = 'Profile updated.';
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _savingProfile = false;
          _profileMsg = 'Update failed.';
        });
    }
  }

  void _addQualification() {
    final v = _newQualCtrl.text.trim();
    if (v.isEmpty ||
        _qualifications.length >= 12 ||
        _qualifications.contains(v))
      return;
    setState(() {
      _qualifications = [..._qualifications, v];
      _newQualCtrl.clear();
    });
  }

  void _removeQualification(String q) {
    setState(
      () => _qualifications = _qualifications.where((x) => x != q).toList(),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    if (Platform.isAndroid) {
      showErrorToast(
        context,
        Exception(
          'Photo upload isn\'t available on Android in this build — use the desktop app instead.',
        ),
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (!mounted ||
        result == null ||
        result.files.isEmpty ||
        result.files.first.path == null)
      return;
    final file = result.files.first;
    setState(() => _uploadingAvatar = true);
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path!, filename: file.name),
      });
      final res = await ApiClient.instance.dio.post(
        '/auth/avatar',
        data: formData,
      );
      final data = ApiClient.unwrap(res) as Map<String, dynamic>;
      userAvatarUrlNotifier.value = data['avatar_url'] as String?;
      if (mounted)
        setState(() {
          _avatarUrl = data['avatar_url'] as String?;
          _uploadingAvatar = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        showErrorToast(context, e);
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      await ApiClient.instance.dio.delete('/auth/avatar');
      userAvatarUrlNotifier.value = null;
      if (mounted)
        setState(() {
          _avatarUrl = null;
          _uploadingAvatar = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        showErrorToast(context, e);
      }
    }
  }

  Future<void> _savePaymentProfile() async {
    if (_savingPaymentProfile) return;
    setState(() {
      _savingPaymentProfile = true;
      _paymentProfileMsg = null;
    });
    try {
      await ApiClient.instance.dio.put(
        '/auth/payment-profile',
        data: {
          'provider': _paymentProviderCtrl.text.trim(),
          'account_number': _paymentAccountNumberCtrl.text.trim(),
          'account_name': _paymentAccountNameCtrl.text.trim(),
        },
      );
      if (mounted)
        setState(() {
          _savingPaymentProfile = false;
          _paymentProfileMsg = 'Payment details saved.';
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _savingPaymentProfile = false;
          _paymentProfileMsg = 'Save failed.';
        });
    }
  }

  Future<void> _changePassword() async {
    if (_savingPw) return;
    // Client-side only — the API's own min:8 check is the real gate, this
    // just avoids a round trip for the two mistakes a confirm field exists
    // to catch (matches hypermed-web's Blade `confirmed` validation, which
    // is likewise client/controller-side only on that platform too).
    if (_newPwCtrl.text.length < 8) {
      setState(() => _pwMsg = 'New password must be at least 8 characters.');
      return;
    }
    if (_newPwCtrl.text != _confirmPwCtrl.text) {
      setState(() => _pwMsg = 'Passwords do not match.');
      return;
    }
    setState(() {
      _savingPw = true;
      _pwMsg = null;
    });
    try {
      await ApiClient.instance.dio.post(
        '/auth/change-password',
        data: {
          'current_password': _oldPwCtrl.text,
          'new_password': _newPwCtrl.text,
        },
      );
      _oldPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      // New password: nothing kept on this device from before it survives.
      wipeLocalUserData();
      if (mounted)
        setState(() {
          _savingPw = false;
          _pwMsg = 'Password changed.';
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _savingPw = false;
          _pwMsg = friendlyError(e);
        });
    }
  }

  Future<void> _logout() async {
    final token = authTokenNotifier.value;
    if (token != null) await AuthService.instance.logout(token);
    authTokenNotifier.value = null;
  }

  // Index is the real, fixed position _buildSectionContent's switch keys off
  // of — kept stable even when a role can't see every entry. 'adminOnly'
  // sections carry org-wide or secret content (API key, billing, org
  // structure, director-only approval policy) that has no business being
  // visible to an individual contributor, so they're filtered out below for
  // anyone without authority.admin_tier rather than just hidden by CSS.
  static const _sections = [
    {'icon': Symbols.person, 'label': 'Profile'},
    {'icon': Symbols.domain, 'label': 'Workspace', 'adminOnly': true},
    {'icon': Symbols.tune, 'label': 'Preferences'},
    {'icon': Symbols.fact_check, 'label': 'Approvals', 'adminOnly': true},
    // Everyone views the org chart; OrgChartEditor gates editing.
    {'icon': Symbols.account_tree, 'label': 'Org Chart'},
  ];

  List<MapEntry<int, Map<String, Object>>> get _visibleSections {
    final isAdmin = can('authority.admin_tier');
    return _sections
        .asMap()
        .entries
        .where((e) => isAdmin || e.value['adminOnly'] != true)
        .toList();
  }

  static const _memberTabs = ['Members', 'Roles', 'Activity'];

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cst) {
        final narrow = cst.maxWidth < 720;
        final pad = narrow ? 16.0 : 24.0;

        final mainContent = SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Narrow: section chip strip
              if (narrow) ...[
                Text(
                  'Settings',
                  style: AppTheme.pageTitle.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _visibleSections.map((e) {
                      final active = _section == e.key;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _section = e.key;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? context.pal.surface2
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.pal.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                e.value['icon'] as IconData,
                                size: 14,
                                color: active
                                    ? context.pal.text
                                    : context.pal.textMute,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                e.value['label'] as String,
                                style: AppTheme.bodySm.copyWith(
                                  color: active
                                      ? context.pal.text
                                      : context.pal.textMute,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Section-specific content
              _buildSectionContent(context),
            ],
          ),
        );

        Widget layout;
        if (narrow) {
          layout = mainContent;
        } else {
          layout = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 220,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: context.pal.border)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: AppTheme.pageTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    ..._visibleSections.map(
                      (e) => _SettingsSideItem(
                        icon: e.value['icon'] as IconData,
                        label: e.value['label'] as String,
                        active: _section == e.key,
                        onTap: () => setState(() {
                          _section = e.key;
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.teal.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enterprise Plan',
                            style: AppTheme.bodyStrong.copyWith(
                              color: AppColors.teal,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_staffList.length} / 25 seats used',
                            style: AppTheme.bodySub.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value:
                                  (_staffList.isEmpty
                                      ? 18
                                      : _staffList.length) /
                                  25,
                              backgroundColor: context.pal.surface3,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.teal,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: mainContent),
            ],
          );
        }

        return Stack(
          children: [
            layout,
            if (_showInvite)
              _InviteDialog(
                onClose: () => setState(() => _showInvite = false),
                onSaved: () {
                  setState(() => _showInvite = false);
                  _loadMembers();
                },
              ),
          ],
        );
      },
    );
  }

  // ── Profile card ──────────────────────────────────────────────────────────
  // ── Identity header ──────────────────────────────────────────────────────
  // Real fields only — no bio/credentials/employee-ID, none of which exist
  // in the schema. Stat strip reuses /performance/mine (same data as the
  // separate My Performance screen) rather than a second computation, and
  // is simply absent for roles with neither field nor sales activity.
  static const _providers = [
    'M-Pesa',
    'Tigo Pesa',
    'Airtel Money',
    'Selcom',
    'Bank',
  ];

  bool get _payoutReady =>
      _paymentProviderCtrl.text.trim().isNotEmpty &&
      _paymentAccountNumberCtrl.text.trim().isNotEmpty &&
      _paymentAccountNameCtrl.text.trim().isNotEmpty;

  bool get _profileComplete =>
      _nameCtrl.text.trim().isNotEmpty &&
      _emailCtrl.text.trim().isNotEmpty &&
      _phoneCtrl.text.trim().isNotEmpty;

  // (value, label, highlight). Role-specific set from the backend; the
  // field/sales fallback only covers an older backend without it.
  List<(String, String, bool)> get _headerStats {
    final roleStats = _myPerformance?.profileStats;
    if (roleStats != null) {
      return [
        for (final st in roleStats)
          (st.isMoney ? tshShort(st.value) : _thousands(st.value), st.label, st.highlight),
      ];
    }
    final s = _myPerformance?.sales;
    if (s != null) {
      return [
        (tshShort(s.pipelineValue), 'Pipeline', false),
        ('${s.dealsWonAllTime}', 'Deals won', false),
        ('${s.accountsServed}', 'Accounts', false),
      ];
    }
    return const [];
  }

  static String _thousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  // The header's one shortcut, per role as in the design mock — each points
  // at the screen that role actually works in. Falls back to My performance
  // when the role can't open its usual screen.
  (String, IconData, String) get _headerCta {
    final role = userRoleNotifier.value;
    final cta = switch (role) {
      'technician' || 'team_leader' => ('Travel plans', Symbols.flight_takeoff, 'my_travel_plans'),
      'sales' || 'sales_manager' => ('My pipeline', Symbols.filter_alt, 'sales'),
      'accountant' || 'finance' || 'finance_manager' => ('Finance', Symbols.account_balance, 'finance'),
      'super_admin' || 'admin' => ('Company overview', Symbols.monitoring, 'dashboard'),
      'cto' => ('Approvals', Symbols.fact_check, 'approvals'),
      'storekeeper' || 'procurement_manager' || 'logistics' => ('Stock levels', Symbols.inventory_2, 'inventory'),
      'hr' => ('People overview', Symbols.groups, 'hr_dashboard'),
      _ => null,
    };
    final allowed = allowedScreenKeys(role);
    if (cta != null && (allowed == null || allowed.contains(cta.$3))) return cta;
    return ('My performance', Symbols.trending_up, 'my_performance');
  }

  Widget _identityHeaderCard(BuildContext context) {
    final name = _nameCtrl.text.trim().isEmpty
        ? userNameNotifier.value
        : _nameCtrl.text.trim();
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final stats = _headerStats;
    final hasAbout = _bioCtrl.text.trim().isNotEmpty || _qualifications.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: context.pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Photo and camera badge are one target: tap opens the
                // View / Change / Remove menu where the tap landed.
                MouseRegion(
                  cursor: _uploadingAvatar ? MouseCursor.defer : SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _uploadingAvatar
                        ? null
                        : (d) => _showAvatarMenu(d.globalPosition),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _loadingProfile
                            ? AvatarWidget(
                                initials: initials.isEmpty ? '?' : initials,
                                size: 64,
                                variant: AvatarVariant.teal,
                              )
                            : AvatarWidget(
                                initials: initials.isEmpty ? '?' : initials,
                                size: 64,
                                variant: AvatarVariant.teal,
                                imageUrl: _avatarUrl,
                              ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: IgnorePointer(
                            // Taps fall through to the avatar's own detector.
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: context.pal.surface2,
                                shape: BoxShape.circle,
                                border: Border.all(color: context.pal.border),
                              ),
                              alignment: Alignment.center,
                              child: _uploadingAvatar
                                  ? const SizedBox(
                                      width: 11,
                                      height: 11,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                      ),
                                    )
                                  : Icon(
                                      Symbols.photo_camera,
                                      size: 12,
                                      color: context.pal.textDim,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name.isEmpty ? '—' : name,
                              style: AppTheme.pageTitle.copyWith(fontSize: 18),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.tealSoft,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppColors.teal.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _roleLabel(userRoleNotifier.value),
                              style: TextStyle(
                                color: AppColors.teal,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          if (_positionTitle != null &&
                              _positionTitle!.isNotEmpty)
                            _HeaderMeta(
                              icon: Symbols.work,
                              text: _positionTitle!,
                            ),
                          if ((_region ?? _zone) != null &&
                              (_region ?? _zone)!.isNotEmpty)
                            _HeaderMeta(
                              icon: Symbols.location_on,
                              text: (_region ?? _zone)!,
                            ),
                          if (_hireDate != null && _hireDate!.isNotEmpty)
                            _HeaderMeta(
                              icon: Symbols.calendar_today,
                              text: 'Since ${_formatHireDate(_hireDate!)}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Shrinks rather than pushing the name off a phone screen.
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: AppButton(
                  label: _headerCta.$1,
                  icon: _headerCta.$2,
                  variant: BtnVariant.ghost,
                  small: true,
                  onPressed: () => widget.onNavigateTo?.call(_headerCta.$3),
                ))),
              ],
            ),
          ),
          // Bio + badges on the left, joined stat tiles on the right —
          // one band under the identity row, as in the design mockup.
          if (hasAbout || stats.isNotEmpty) ...[
            Container(height: 1, color: context.pal.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final about = _headerAbout(context);
                  final tiles = stats.isEmpty ? null : _headerStatTiles(context, stats);
                  // Too narrow for side-by-side: stack, stats below.
                  if (c.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasAbout) about,
                        if (hasAbout && tiles != null) const SizedBox(height: 14),
                        if (tiles != null)
                          SingleChildScrollView(scrollDirection: Axis.horizontal, child: tiles),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: hasAbout ? about : const SizedBox.shrink()),
                      if (tiles != null) ...[const SizedBox(width: 24), tiles],
                    ],
                  );
                },
              ),
            ),
          ],
          Container(height: 1, color: context.pal.border),
          Row(
            children: [
              Expanded(
                child: _ReadinessTile(
                  icon: Symbols.check_circle,
                  ok: _profileComplete,
                  label: 'Profile',
                  note: _profileComplete ? 'Complete' : 'Add your phone number',
                ),
              ),
              Container(width: 1, height: 44, color: context.pal.border),
              Expanded(
                child: _ReadinessTile(
                  icon: Symbols.payments,
                  ok: _payoutReady,
                  label: 'Payouts',
                  note: _payoutReady ? 'Ready' : 'Needed for travel plans',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerAbout(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_bioCtrl.text.trim().isNotEmpty) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            _bioCtrl.text.trim(),
            style: AppTheme.bodySm.copyWith(color: context.pal.textMute, height: 1.55),
          ),
        ),
        if (_qualifications.isNotEmpty) const SizedBox(height: 10),
      ],
      if (_qualifications.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in _qualifications)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: context.pal.surface2,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: context.pal.border),
                ),
                child: Text(
                  q,
                  style: AppTheme.bodySub.copyWith(fontSize: 11, color: context.pal.textMute),
                ),
              ),
          ],
        ),
    ],
  );

  // Joined tiles: the outer box's border colour shows through 1px gaps
  // between the tiles as dividers.
  Widget _headerStatTiles(BuildContext context, List<(String, String, bool)> stats) => Container(
    decoration: BoxDecoration(
      color: context.pal.border,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: context.pal.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 1),
            Container(
              constraints: const BoxConstraints(minWidth: 78),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: context.pal.bg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stats[i].$1,
                    style: AppTheme.pageTitle.copyWith(
                      fontSize: 22,
                      height: 1,
                      color: stats[i].$3 ? AppColors.green : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[i].$2.toUpperCase(),
                    maxLines: 1,
                    style: AppTheme.labelCaps.copyWith(fontSize: 10, letterSpacing: 0.8, color: context.pal.textDim),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _showAvatarMenu(Offset at) async {
    final hasPhoto = _avatarUrl != null;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (hasPhoto)
          const PopupMenuItem(value: 'view', child: _AvatarMenuRow(icon: Symbols.visibility, label: 'View photo')),
        PopupMenuItem(
          value: 'change',
          child: _AvatarMenuRow(icon: Symbols.photo_camera, label: hasPhoto ? 'Change photo' : 'Upload photo'),
        ),
        if (hasPhoto)
          PopupMenuItem(
            value: 'remove',
            child: _AvatarMenuRow(icon: Symbols.delete, label: 'Remove photo', color: AppColors.coral),
          ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'view':
        _viewAvatar();
      case 'change':
        _pickAndUploadAvatar();
      case 'remove':
        _removeAvatar();
    }
  }

  void _viewAvatar() {
    final url = _avatarUrl;
    if (url == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.pal.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.rLg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : const SizedBox(width: 240, height: 240, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      errorBuilder: (c, e, st) => SizedBox(
                        width: 240,
                        height: 160,
                        child: Center(child: Text('Could not load photo', style: AppTheme.bodySub)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: 'Close',
                      variant: BtnVariant.ghost,
                      small: true,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Change photo',
                      icon: Symbols.photo_camera,
                      small: true,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _pickAndUploadAvatar();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatHireDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  /// Fields side by side on wide screens, stacked on a phone.
  Widget _fieldRow(List<Widget> fields) => LayoutBuilder(builder: (_, box) => box.maxWidth < 560
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < fields.length; i++) ...[if (i > 0) const SizedBox(height: 12), fields[i]],
        ])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < fields.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: fields[i])],
        ]));

  Widget _profileCard(BuildContext context) => _SCard(
    title: 'Personal Information',
    trailing: GestureDetector(
      onTap: _logout,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.logout, size: 14, color: AppColors.coral),
          const SizedBox(width: 6),
          Text(
            'Sign out',
            style: AppTheme.bodySm.copyWith(
              color: AppColors.coral,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    ),
    child: _loadingProfile
        ? const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How you appear on approvals, tickets and payslips.',
                style: AppTheme.bodySub.copyWith(
                  fontSize: 12.5,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SettingsField(
                      label: 'Full name',
                      ctrl: _nameCtrl,
                      hint: 'Your name',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SettingsField(
                      label: 'Phone',
                      ctrl: _phoneCtrl,
                      hint: '+255 7XX XXX XXX',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsField(
                label: 'Work email',
                ctrl: _emailCtrl,
                hint: 'your@email.com',
              ),
              const SizedBox(height: 18),
              Text('Statutory IDs', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
              const SizedBox(height: 8),
              _fieldRow([
                _SettingsField(label: 'NSSF number', ctrl: _idCtrls['nssf_number']!, hint: 'NSSF membership no.'),
                _SettingsField(label: 'NIDA number', ctrl: _idCtrls['nida_number']!, hint: '20-digit national ID'),
                _SettingsField(label: 'TIN number', ctrl: _idCtrls['tin_number']!, hint: 'e.g. 123-456-789'),
              ]),
              const SizedBox(height: 18),
              Text('Next of kin', style: AppTheme.labelCaps.copyWith(fontSize: 10)),
              const SizedBox(height: 8),
              _fieldRow([
                _SettingsField(label: 'Name', ctrl: _idCtrls['next_of_kin_name']!, hint: 'Full name'),
                _SettingsField(label: 'Phone', ctrl: _idCtrls['next_of_kin_phone']!, hint: '+255 7XX XXX XXX'),
                _SettingsField(label: 'Relationship', ctrl: _idCtrls['next_of_kin_relationship']!, hint: 'e.g. Spouse, Parent'),
              ]),
              const SizedBox(height: 18),
              _SettingsField(
                label: 'Bio',
                ctrl: _bioCtrl,
                maxLines: 3,
                hint:
                    'A short line about your background — shown on your profile card.',
              ),
              const SizedBox(height: 14),
              Text(
                'Qualifications',
                style: AppTheme.labelCaps.copyWith(fontSize: 10),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in _qualifications)
                    Container(
                      padding: const EdgeInsets.only(
                        left: 9,
                        right: 4,
                        top: 4,
                        bottom: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.pal.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.pal.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            q,
                            style: AppTheme.bodySub.copyWith(
                              fontSize: 11.5,
                              color: context.pal.text,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _removeQualification(q),
                            child: Icon(
                              Symbols.close,
                              size: 13,
                              color: context.pal.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SettingsField(
                      label: '',
                      ctrl: _newQualCtrl,
                      hint:
                          'e.g. BSc Electronics & Telecommunication, 5 years experience',
                      onSubmitted: (_) => _addQualification(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _OutlineBtn(
                    label: 'Add',
                    saving: false,
                    onTap: _addQualification,
                  ),
                ],
              ),
              if (_managerName != null ||
                  _positionDepartment != null ||
                  _region != null) ...[
                const SizedBox(height: 16),
                Container(height: 1, color: context.pal.border),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_positionDepartment != null &&
                        _positionDepartment!.isNotEmpty)
                      Expanded(
                        child: _ReadOnlyField(
                          label: 'Department',
                          value: _positionDepartment!,
                        ),
                      ),
                    if (_managerName != null && _managerName!.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ReadOnlyField(
                          label: 'Reports to',
                          value: _managerName!,
                        ),
                      ),
                    ],
                    if ((_region ?? _zone) != null &&
                        (_region ?? _zone)!.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ReadOnlyField(
                          label: 'Branch',
                          value: (_region ?? _zone)!,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Managed by HR — contact HR to request a change.',
                  style: AppTheme.bodySub.copyWith(
                    fontSize: 10.5,
                    color: context.pal.textDim,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_profileMsg != null) ...[
                    Icon(
                      _profileMsg!.contains('failed')
                          ? Symbols.error
                          : Symbols.check_circle,
                      size: 14,
                      color: _profileMsg!.contains('failed')
                          ? AppColors.coral
                          : AppColors.teal,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _profileMsg!,
                      style: AppTheme.bodySub.copyWith(
                        color: _profileMsg!.contains('failed')
                            ? AppColors.coral
                            : AppColors.teal,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const Spacer(),
                  _TealBtn(
                    label: 'Save changes',
                    saving: _savingProfile,
                    onTap: _saveProfile,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Everything the system holds about you — profile, IDs, next of
              // kin, bank, employment and salary, payslips, leave, expenses.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Your data:', style: AppTheme.bodySub.copyWith(fontSize: 12.5, color: context.pal.textMute)),
                  OutlinedButton.icon(
                    onPressed: () => _exportMyData('pdf'),
                    icon: const Icon(Symbols.picture_as_pdf, size: 15),
                    label: const Text('Export as PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportMyData('xlsx'),
                    icon: const Icon(Symbols.table_view, size: 15),
                    label: const Text('Export as Excel'),
                  ),
                ],
              ),
            ],
          ),
  );

  /// Export my own data: PDF opens in the viewer (save/print there), Excel saves to Downloads.
  Future<void> _exportMyData(String format) {
    final slug = _nameCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final date = DateTime.now().toIso8601String().split('T').first;
    return downloadPdf(context, () async {
      final res = await ApiClient.instance.dio.get<List<int>>('/auth/profile/export',
          queryParameters: {'format': format}, options: Options(responseType: ResponseType.bytes));
      return res.data ?? const <int>[];
    }, 'my-data-${slug.isEmpty ? 'me' : slug}-$date.$format');
  }

  // ── Password card ─────────────────────────────────────────────────────────

  bool get _pwMismatch =>
      _confirmPwCtrl.text.isNotEmpty && _confirmPwCtrl.text != _newPwCtrl.text;

  int get _pwStrengthScore {
    final pw = _newPwCtrl.text;
    var score = 0;
    if (pw.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) score++;
    if (RegExp(r'\d').hasMatch(pw)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;
    if (pw.isNotEmpty && score == 0) score = 1;
    return score;
  }

  Widget _passwordCard(BuildContext context) => _SCard(
    title: 'Password & Security',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SettingsField(
                label: 'Current password',
                ctrl: _oldPwCtrl,
                hint: '••••••••',
                obscure: true,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsField(
                    label: 'New password',
                    ctrl: _newPwCtrl,
                    hint: 'At least 8 characters',
                    obscure: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  _PasswordStrengthMeter(
                    score: _pwStrengthScore,
                    hasInput: _newPwCtrl.text.isNotEmpty,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsField(
          label: 'Confirm new password',
          ctrl: _confirmPwCtrl,
          hint: '••••••••',
          obscure: true,
          onChanged: (_) => setState(() {}),
          hasError: _pwMismatch,
        ),
        // Live match feedback once they've started confirming.
        if (_confirmPwCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                _pwMismatch ? Symbols.error : Symbols.check_circle,
                size: 13,
                color: _pwMismatch ? AppColors.coral : AppColors.teal,
              ),
              const SizedBox(width: 5),
              Text(
                _pwMismatch ? "Passwords don't match" : 'Passwords match',
                style: AppTheme.bodySub.copyWith(
                  fontSize: 11.5,
                  color: _pwMismatch ? AppColors.coral : AppColors.teal,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            if (_pwMsg != null) ...[
              Icon(
                _pwMsg == 'Password changed.'
                    ? Symbols.check_circle
                    : Symbols.error,
                size: 14,
                color: _pwMsg == 'Password changed.'
                    ? AppColors.teal
                    : AppColors.coral,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _pwMsg!,
                  style: AppTheme.bodySub.copyWith(
                    color: _pwMsg == 'Password changed.'
                        ? AppColors.teal
                        : AppColors.coral,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            _OutlineBtn(
              label: 'Update password',
              saving: _savingPw,
              onTap: _changePassword,
            ),
          ],
        ),
      ],
    ),
  );

  // ── Payment details card (Section 15.7) ─────────────────────────────────
  // Required before any travel plan can be submitted — the account number
  // shown here is your own, never masked (masking only applies when
  // someone ELSE views your plan's payment details). Provider picker is a
  // client-side convenience over the same free-text `provider` column —
  // no backend schema change, "Other" still accepts any text.
  Widget _paymentProfileCard(BuildContext context) {
    final isBank = _paymentProviderCtrl.text.trim() == 'Bank';
    final isKnownProvider = _providers.contains(
      _paymentProviderCtrl.text.trim(),
    );
    final nameMismatch =
        _paymentAccountNameCtrl.text.trim().isNotEmpty &&
        _paymentAccountNameCtrl.text.trim().toLowerCase() !=
            _nameCtrl.text.trim().toLowerCase();

    return _SCard(
      title: 'Payout Details',
      child: _loadingProfile
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Used for travel-plan/per-diem payouts. Required before you can submit a travel plan.',
                  style: AppTheme.bodySub.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textDim,
                  ),
                ),
                if (!_payoutReady) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.amberSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Symbols.warning, size: 14, color: AppColors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Not set up — travel plan submission is blocked.',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'PROVIDER',
                  style: AppTheme.labelCaps.copyWith(fontSize: 10),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _providers)
                      _ProviderChip(
                        label: p,
                        selected: _paymentProviderCtrl.text.trim() == p,
                        onTap: () =>
                            setState(() => _paymentProviderCtrl.text = p),
                      ),
                    _ProviderChip(
                      label: 'Other',
                      selected:
                          !isKnownProvider &&
                          _paymentProviderCtrl.text.trim().isNotEmpty,
                      onTap: () =>
                          setState(() => _paymentProviderCtrl.text = ''),
                    ),
                  ],
                ),
                if (!isKnownProvider) ...[
                  const SizedBox(height: 10),
                  _SettingsField(
                    label: '',
                    ctrl: _paymentProviderCtrl,
                    hint: 'Provider name',
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SettingsField(
                        label: isBank ? 'Account Number' : 'Mobile Number',
                        ctrl: _paymentAccountNumberCtrl,
                        hint: isBank ? '0150 2345 6789 01' : '+255 7XX XXX XXX',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _SettingsField(
                        label: 'Name on account',
                        ctrl: _paymentAccountNameCtrl,
                        hint: 'Must match your ID',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (nameMismatch) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Symbols.info, size: 13, color: AppColors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Differs from your profile name — Finance may hold the payout for review.',
                          style: TextStyle(
                            color: AppColors.amber,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_paymentProfileMsg != null) ...[
                      Icon(
                        _paymentProfileMsg!.contains('failed')
                            ? Symbols.error
                            : Symbols.check_circle,
                        size: 14,
                        color: _paymentProfileMsg!.contains('failed')
                            ? AppColors.coral
                            : AppColors.teal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _paymentProfileMsg!,
                        style: AppTheme.bodySub.copyWith(
                          color: _paymentProfileMsg!.contains('failed')
                              ? AppColors.coral
                              : AppColors.teal,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const Spacer(),
                    _TealBtn(
                      label: 'Save payment details',
                      saving: _savingPaymentProfile,
                      onTap: _savePaymentProfile,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ── Section content ───────────────────────────────────────────────────────
  Widget _buildSectionContent(BuildContext context) => switch (_section) {
    0 => _profileSection(context),
    1 => _workspaceSection(context),
    2 => _preferencesSection(context),
    3 => _approvalsSection(context),
    4 => const OrgChartEditor(),
    _ => const SizedBox.shrink(),
  };

  // ── Section 0: Profile & Security ─────────────────────────────────────────
  Widget _profileSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _identityHeaderCard(context),
      const SizedBox(height: 16),
      _profileCard(context),
      const SizedBox(height: 16),
      _paymentProfileCard(context),
      const SizedBox(height: 16),
      _passwordCard(context),
    ],
  );

  // ── Section 6: Approvals ──────────────────────────────────────────────────
  Widget _approvalsSection(BuildContext context) => _loadingApprovals
      ? const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SCard(
              title: 'Expense Escalation Threshold',
              icon: Symbols.trending_up,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expenses above this amount always require Director approval, even outside a flagged category. Director-only.',
                    style: AppTheme.bodySub.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingsField(
                          label: 'Threshold (TZS)',
                          ctrl: _thresholdCtrl,
                          hint: '3000000',
                        ),
                      ),
                      // The CTO's admin tier sees money routing but can't
                      // change it (SettingController::MONEY_ROUTING_KEYS).
                      if (hasFinalMoneyAuthority(userRoleNotifier.value)) ...[
                        const SizedBox(width: 14),
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: _TealBtn(
                            label: 'Save',
                            saving: _savingThreshold,
                            onTap: _saveThreshold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SCard(
              title: 'Categories Requiring Director Approval',
              icon: Symbols.rule_folder,
              child: Column(
                children: [
                  Text(
                    'These categories always escalate to the Director, regardless of amount —e.g. new order payments, machine imports.',
                    style: AppTheme.bodySub.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (_expenseCategories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No expense categories found.',
                        style: AppTheme.bodySub,
                      ),
                    )
                  else
                    ..._expenseCategories.map(
                      (cat) => _ToggleRow(
                        label: cat.name,
                        sub: cat.requiresDirectorApproval
                            ? 'Always requires Director approval'
                            : 'CTO can approve directly (unless over threshold)',
                        value: cat.requiresDirectorApproval,
                        onChanged: (v) {
                          if (hasFinalMoneyAuthority(userRoleNotifier.value)) _toggleCategoryApproval(cat, v);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SCard(
              title: 'Chat Review',
              icon: Symbols.visibility,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Off by default: nobody can read chats they are not in. When on, only people the Director gives the "Review Staff Chats" permission can read chats, read-only. Staff see a notice and every read is logged. Director-only.',
                    style: AppTheme.bodySub.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  _ToggleRow(
                    label: 'Allow chat review',
                    sub: _chatReviewOn ? 'On: staff are told chats may be reviewed' : 'Off: chats are private',
                    value: _chatReviewOn,
                    // Only the Director's own seat changes this (the API checks too).
                    onChanged: hasFinalMoneyAuthority(userRoleNotifier.value) && !_savingChatReview
                        ? _setChatReview : null,
                  ),
                  if (_chatReviewOn && ChatController.instance.settings.canAudit) ...[
                    const SizedBox(height: 8),
                    AppButton(
                      label: 'Open chat review',
                      icon: Symbols.forum,
                      small: true,
                      onPressed: () => pushPhoneDetail(context, (_) => const ChatReviewScreen()),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SCard(
              title: 'Travel Plan Settings',
              icon: Symbols.route,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default per-diem rate pre-fills each new itinerary day. Signature-block labels are the role titles shown on the exported travel plan — the plan\'s real approval chain (Team Lead / CTO / Accountant / final release) doesn\'t change, only what each line is called.',
                    style: AppTheme.bodySub.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  _SettingsField(
                    label: 'Default per-diem rate (TZS/day)',
                    ctrl: _perDiemDefaultRateCtrl,
                    hint: '80000',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingsField(
                          label: 'Team lead stage label',
                          ctrl: _sigTeamLeadCtrl,
                          hint: 'Technical supervisor',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SettingsField(
                          label: 'CTO stage label',
                          ctrl: _sigCtoCtrl,
                          hint: 'CTO',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingsField(
                          label: 'Accountant-initiate stage label',
                          ctrl: _sigAccountantCtrl,
                          hint: 'Finance',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SettingsField(
                          label: 'Final-release stage label',
                          ctrl: _sigFinalReleaseCtrl,
                          hint: 'Managing director',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_travelPlanSettingsMsg != null) ...[
                        Icon(
                          _travelPlanSettingsMsg!.contains('failed')
                              ? Symbols.error
                              : Symbols.check_circle,
                          size: 14,
                          color: _travelPlanSettingsMsg!.contains('failed')
                              ? AppColors.coral
                              : AppColors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _travelPlanSettingsMsg!,
                          style: AppTheme.bodySub.copyWith(
                            color: _travelPlanSettingsMsg!.contains('failed')
                                ? AppColors.coral
                                : AppColors.teal,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      const Spacer(),
                      _TealBtn(
                        label: 'Save',
                        saving: _savingTravelPlanSettings,
                        onTap: _saveTravelPlanSettings,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

  // ── Section 0: Workspace ──────────────────────────────────────────────────
  Widget _workspaceSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Team & Roles
      Text('Team & Roles', style: AppTheme.pageTitle),
      const SizedBox(height: 4),
      Text(
        'Manage team members, permissions and security settings.',
        style: AppTheme.bodySub,
      ),
      const SizedBox(height: 20),

      // Tab bar
      Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.pal.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _memberTabs
                .asMap()
                .entries
                .map(
                  (e) => GestureDetector(
                    onTap: () => setState(() => _tab = e.key),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _tab == e.key
                                ? AppColors.teal
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        e.value,
                        style: AppTheme.bodySm.copyWith(
                          color: _tab == e.key
                              ? context.pal.text
                              : context.pal.textMute,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Tab content
      switch (_tab) {
        0 => _membersTab(context),
        1 => _rolesTab(context),
        2 => _activityTab(context),
        _ => const SizedBox.shrink(),
      },
    ],
  );

  // ── Tab 0: Members ────────────────────────────────────────────────────────
  Widget _memberSearchField(BuildContext context) => SearchField(
    hint: 'Search members…',
    controller: _memberSearchCtrl,
    onChanged: (v) => setState(() => _memberSearch = v),
  );

  Widget _memberRoleFilterDropdown(BuildContext context) {
    final roleNames = _roles.map((r) => r.name).toList()..sort();
    final items = ['All', ...roleNames];
    final value = items.contains(_memberRoleFilter) ? _memberRoleFilter : 'All';
    return SizedBox(
      width: 180,
      child: AppSelectField<String>(
        value: value,
        items: items
            .map(
              (r) => AppSelectItem(
                value: r,
                label: r == 'All' ? 'All' : _roleLabel(r),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => _memberRoleFilter = v),
      ),
    );
  }

  Widget _membersTab(BuildContext context) => Column(
    children: [
      LayoutBuilder(
        builder: (ctx2, cst2) {
          final n2 = cst2.maxWidth < 520;
          final searchBox = _memberSearchField(context);
          final roleFilter = _memberRoleFilterDropdown(context);
          final refreshBtn = Tooltip(
            message:
                'Refresh from server — this list is cached per device/session, so a member added elsewhere won\'t show up until refreshed.',
            child: GestureDetector(
              onTap: _loadingMembers ? null : () => _loadMembers(force: true),
              child: Container(
                height: 32,
                width: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.pal.surface1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.pal.border),
                ),
                child: _loadingMembers
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.pal.textMute,
                        ),
                      )
                    : Icon(
                        Symbols.refresh,
                        size: 16,
                        color: context.pal.textMute,
                      ),
              ),
            ),
          );
          final inviteBtn = GestureDetector(
            onTap: () => setState(() => _showInvite = true),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Symbols.person_add,
                    size: 14,
                    color: Color(0xFF06120F),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Invite Member',
                    style: AppTheme.bodyStrong.copyWith(
                      color: const Color(0xFF06120F),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
          if (n2) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchBox,
                const SizedBox(height: 8),
                Row(
                  children: [
                    roleFilter,
                    const Spacer(),
                    refreshBtn,
                    const SizedBox(width: 8),
                    inviteBtn,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 260, child: searchBox),
              const SizedBox(width: 10),
              roleFilter,
              const Spacer(),
              refreshBtn,
              const SizedBox(width: 8),
              inviteBtn,
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: context.pal.surface1,
          borderRadius: BorderRadius.circular(AppColors.rLg),
          border: Border.all(color: context.pal.border),
        ),
        child: _loadingMembers
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : _memberError != null && _staffList.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    _memberError!,
                    style: AppTheme.bodySub.copyWith(color: AppColors.coral),
                  ),
                ),
              )
            : HScrollTable(
                minWidth: 640,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: context.pal.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 20),
                          _MemberTh('Member', flex: 3),
                          _MemberTh('Role', flex: 1),
                          _MemberTh('2FA', flex: 1),
                          _MemberTh('Last Active', flex: 1),
                          const SizedBox(width: 60),
                        ],
                      ),
                    ),
                    if (_filteredStaffList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No members found.')),
                      )
                    else
                      ..._filteredStaffList.map(
                        (m) => _MemberRow(
                          member: m,
                          canManage: can('roles.manage'),
                          onEditRole: () =>
                              _showEditMemberRoleDialog(context, m),
                          onManagePermissions: () =>
                              _showManagePermissionsDialog(context, m),
                          onResetPassword: () =>
                              _showResetPasswordDialog(context, m),
                          onDeactivate: () =>
                              _showDeactivateMemberDialog(context, m),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    ],
  );

  void _showEditMemberRoleDialog(BuildContext context, StaffMember member) {
    showDialog(
      context: context,
      builder: (_) => _EditMemberRoleDialog(
        member: member,
        roleNames: _roles.map((r) => r.name).toList(),
        onSave: (role) async {
          await StaffService.instance.update(member.id, {'role': role});
          StaffService.instance.invalidateCache();
          await _loadMembers();
        },
      ),
    );
  }

  void _showManagePermissionsDialog(BuildContext context, StaffMember member) {
    showDialog(
      context: context,
      builder: (_) =>
          _ManagePermissionsDialog(member: member, catalog: _permissionCatalog),
    );
  }

  void _showResetPasswordDialog(BuildContext context, StaffMember member) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('Reset Password', style: AppTheme.cardTitle),
        content: SizedBox(
          width: 320,
          child: Text(
            "Reset ${member.name}'s password back to the default? "
            "They'll need to be given the default password and should change it themselves afterward.",
            style: AppTheme.bodySm,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await StaffService.instance.resetPassword(member.id);
                // Resetting your own password: same as changing it.
                if (member.id == userIdNotifier.value) wipeLocalUserData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "${member.name}'s password was reset to the default.",
                      ),
                      backgroundColor: AppColors.teal,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) showErrorToast(context, e);
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showDeactivateMemberDialog(BuildContext context, StaffMember member) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('Deactivate Staff Member', style: AppTheme.cardTitle),
        content: SizedBox(
          width: 320,
          child: Text(
            "Deactivate ${member.name}? They'll no longer be able to sign in. "
            "This doesn't delete their history — it can be reversed by an admin later if needed.",
            style: AppTheme.bodySm,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await StaffService.instance.delete(member.id);
                StaffService.instance.invalidateCache();
                await _loadMembers();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${member.name} was deactivated.'),
                      backgroundColor: AppColors.coral,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) showErrorToast(context, e);
              }
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Roles ──────────────────────────────────────────────────────────
  static List<Color> get _rolePalette => [
    AppColors.teal,
    AppColors.blue,
    AppColors.violet,
    AppColors.amber,
    AppColors.coral,
    AppColors.info,
    AppColors.textDim,
  ];

  String _permLabel(String key) {
    for (final items in _permissionCatalog.values) {
      for (final p in items) {
        if (p.key == key) return p.label;
      }
    }
    return key;
  }

  Widget _rolesTab(BuildContext context) {
    final canManage = can('roles.manage');

    if (_loadingRoles) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_rolesError != null && _roles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Text(_rolesError!, style: AppTheme.bodySub),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_roles.length} roles defined',
                style: AppTheme.bodySub,
              ),
            ),
            Container(
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.pal.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.pal.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RolesViewToggleBtn(
                    icon: Symbols.list,
                    label: 'List',
                    active: !_rolesGraphView,
                    onTap: () => setState(() => _rolesGraphView = false),
                  ),
                  _RolesViewToggleBtn(
                    icon: Symbols.hub,
                    label: 'Graph',
                    active: _rolesGraphView,
                    onTap: () => setState(() => _rolesGraphView = true),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (canManage)
              _OutlineBtn(
                label: 'New Role',
                saving: false,
                onTap: () => _showNewRoleDialog(context),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_rolesGraphView)
          RolesGraphView(
            roles: _roles,
            catalog: _permissionCatalog,
            overrides: _auditLog,
          )
        else
          ..._roles.asMap().entries.map((entry) {
            final role = entry.value;
            final color = _rolePalette[entry.key % _rolePalette.length];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.pal.surface1,
                borderRadius: BorderRadius.circular(AppColors.rLg),
                border: Border.all(color: context.pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _roleLabel(role.name),
                          style: AppTheme.bodyStrong.copyWith(
                            color: color,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${role.permissionCount} permission${role.permissionCount == 1 ? '' : 's'}',
                          style: AppTheme.bodySub.copyWith(fontSize: 12),
                        ),
                      ),
                      if (canManage) ...[
                        GestureDetector(
                          onTap: () => _showEditRoleDialog(context, role),
                          child: Icon(
                            Symbols.edit,
                            size: 15,
                            color: context.pal.textDim,
                          ),
                        ),
                        if (!role.isSystem) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _deleteRole(role),
                            child: Icon(
                              Symbols.delete,
                              size: 15,
                              color: context.pal.textDim,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  if (role.permissionKeys.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: role.permissionKeys.map((key) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tealSoft,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: AppColors.teal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            _permLabel(key),
                            style: AppTheme.monoXs.copyWith(
                              fontSize: 10.5,
                              color: AppColors.teal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  void _showNewRoleDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: context.pal.surface1,
        title: Text('New Role', style: AppTheme.cardTitle),
        content: SizedBox(
          width: 320,
          child: LabeledTextField(
            label: 'Role name',
            controller: ctrl,
            hint: 'e.g. regional_sales_lead',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogCtx).pop();
              _createRole(name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditRoleDialog(BuildContext context, RoleSummary role) {
    showDialog(
      context: context,
      builder: (_) => _EditRolePermissionsDialog(
        role: role,
        catalog: _permissionCatalog,
        onSave: (keys) => _saveRolePermissions(role, keys),
      ),
    );
  }

  // ── Tab 3: Activity ───────────────────────────────────────────────────────
  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2)
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    if (parts.isNotEmpty && parts.first.isNotEmpty)
      return parts.first[0].toUpperCase();
    return '?';
  }

  Widget _activityTab(BuildContext context) {
    final log = _filteredAuditLog;

    return Column(
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () =>
                  setState(() => _auditThisWeekOnly = !_auditThisWeekOnly),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _auditThisWeekOnly
                      ? AppColors.tealSoft
                      : context.pal.surface1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _auditThisWeekOnly
                        ? AppColors.teal.withValues(alpha: 0.4)
                        : context.pal.border,
                  ),
                ),
                child: Center(
                  child: Text(
                    _auditThisWeekOnly ? 'This week' : 'All time',
                    style: AppTheme.bodySub.copyWith(
                      fontSize: 12,
                      color: _auditThisWeekOnly
                          ? AppColors.teal
                          : context.pal.text,
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            _OutlineBtn(
              label: 'Export log',
              saving: false,
              onTap: _exportAuditLog,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(AppColors.rLg),
            border: Border.all(color: context.pal.border),
          ),
          child: _loadingAudit
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : log.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No permission grants or denials yet.',
                      style: AppTheme.bodySub.copyWith(
                        color: context.pal.textDim,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: log.asMap().entries.map((e) {
                    final entry = e.value;
                    final isLast = e.key == log.length - 1;
                    final allow = entry.effect == 'allow';
                    final dt = entry.createdAt != null
                        ? DateTime.tryParse(entry.createdAt!)
                        : null;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: isLast
                          ? null
                          : BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: context.pal.divider),
                              ),
                            ),
                      child: Row(
                        children: [
                          AvatarWidget(
                            initials: _initialsOf(entry.userName ?? '?'),
                            size: 30,
                            variant: allow
                                ? AvatarVariant.teal
                                : AvatarVariant.coral,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      entry.userName ?? 'Unknown',
                                      style: AppTheme.bodyStrong.copyWith(
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${allow ? 'granted' : 'denied'} "${entry.label}"',
                                        style: AppTheme.bodySub.copyWith(
                                          fontSize: 12,
                                          color: allow
                                              ? AppColors.teal
                                              : AppColors.coral,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    if (entry.createdByName != null)
                                      'by ${entry.createdByName}',
                                    if (entry.reason != null &&
                                        entry.reason!.isNotEmpty)
                                      entry.reason!,
                                  ].join(' —'),
                                  style: AppTheme.bodySub.copyWith(
                                    fontSize: 11.5,
                                    color: context.pal.textDim,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            dt != null ? timeAgo(dt) : '—',
                            style: AppTheme.monoXs.copyWith(
                              color: context.pal.textDim,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _exportAuditLog() async {
    try {
      final path = await CsvExport.permissionAuditLog(_filteredAuditLog);
      if (path != null && mounted)
        showSuccessToast(
          context,
          'Exported ${_filteredAuditLog.length} entries to CSV',
        );
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  // ── Section 5: Preferences ────────────────────────────────────────────────
  Widget _preferencesSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppUpdatesCard(),
      const SizedBox(height: 16),
      _SCard(
        title: 'Appearance',
        icon: Symbols.palette,
        child: Column(
          children: [
            ValueListenableBuilder<AppThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, _) => Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Theme', style: AppTheme.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          'Choose your interface appearance',
                          style: AppTheme.bodySub,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 220,
                    child: DropdownFieldBox<AppThemeMode>(
                      value: mode,
                      items: AppTheme.pickerOrder
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.$1,
                                  child: Text(e.$2),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                            if (v != null) themeNotifier.value = v;
                          },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<TextSizePref>(
              valueListenable: textSizeNotifier,
              builder: (_, sizePref, _) => Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Text Size', style: AppTheme.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          'Adjust text size across the whole app',
                          style: AppTheme.bodySub,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SegmentedButton<TextSizePref>(
                    segments: const [
                      ButtonSegment(
                        value: TextSizePref.small,
                        label: Text('Small'),
                      ),
                      ButtonSegment(
                        value: TextSizePref.medium,
                        label: Text('Medium'),
                      ),
                      ButtonSegment(
                        value: TextSizePref.large,
                        label: Text('Large'),
                      ),
                    ],
                    selected: {sizePref},
                    onSelectionChanged: (s) => textSizeNotifier.value = s.first,
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ── Data classes ────────────────────────────────────────────────────────────

class _EditMemberRoleDialog extends StatefulWidget {
  const _EditMemberRoleDialog({
    required this.member,
    required this.roleNames,
    required this.onSave,
  });
  final StaffMember member;
  final List<String> roleNames;
  final Future<void> Function(String role) onSave;

  @override
  State<_EditMemberRoleDialog> createState() => _EditMemberRoleDialogState();
}

class _EditMemberRoleDialogState extends State<_EditMemberRoleDialog> {
  late String _role = widget.roleNames.contains(widget.member.role)
      ? widget.member.role
      : (widget.roleNames.isNotEmpty
            ? widget.roleNames.first
            : widget.member.role);
  bool _saving = false;

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_role);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorToast(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedRoles = [...widget.roleNames]..sort();
    return AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text(
        'Edit Role — ${widget.member.name}',
        style: AppTheme.cardTitle,
      ),
      content: SizedBox(
        width: 320,
        child: _HDropdown(
          label: 'Role',
          value: _role,
          items: sortedRoles,
          display: sortedRoles.map(_roleLabel).toList(),
          onChanged: (v) => setState(() => _role = v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _ManagePermissionsDialog extends StatefulWidget {
  const _ManagePermissionsDialog({required this.member, required this.catalog});
  final StaffMember member;
  final Map<String, List<PermissionCatalogItem>> catalog;

  @override
  State<_ManagePermissionsDialog> createState() =>
      _ManagePermissionsDialogState();
}

class _ManagePermissionsDialogState extends State<_ManagePermissionsDialog> {
  bool _loading = true;
  List<UserPermission> _effective = [];
  List<UserPermissionOverride> _overrides = [];
  String? _newKey;
  String _newEffect = 'allow';
  final _reasonCtrl = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _permLabel(String key) {
    for (final items in widget.catalog.values) {
      for (final p in items) {
        if (p.key == key) return p.label;
      }
    }
    return key;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final effF = PermissionService.instance.fetchForUser(widget.member.id);
      final ovrF = PermissionService.instance.overridesForUser(
        widget.member.id,
      );
      final eff = await effF;
      final ovr = await ovrF;
      if (!mounted) return;
      setState(() {
        _effective = eff;
        _overrides = ovr;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showErrorToast(context, e);
      }
    }
  }

  Future<void> _addOverride() async {
    if (_newKey == null || _adding) return;
    setState(() => _adding = true);
    try {
      await PermissionService.instance.addOverride(
        widget.member.id,
        key: _newKey!,
        effect: _newEffect,
        reason: _reasonCtrl.text.trim().isEmpty
            ? null
            : _reasonCtrl.text.trim(),
      );
      _reasonCtrl.clear();
      _newKey = null;
      await _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeOverride(UserPermissionOverride o) async {
    try {
      await PermissionService.instance.removeOverride(widget.member.id, o.id);
      await _load();
    } catch (e) {
      if (mounted) showErrorToast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPerms = widget.catalog.values.expand((v) => v).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final overriddenKeys = _overrides.map((o) => o.key).toSet();
    final roleGranted = _effective
        .where((p) => !overriddenKeys.contains(p.key))
        .toList();

    return AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text(
        'Manage Permissions — ${widget.member.name}',
        style: AppTheme.cardTitle,
      ),
      content: SizedBox(
        width: 460,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FROM ROLE (${_roleLabel(widget.member.role)})',
                      style: AppTheme.labelCaps,
                    ),
                    const SizedBox(height: 8),
                    roleGranted.isEmpty
                        ? Text(
                            'No permissions from role.',
                            style: AppTheme.bodySub.copyWith(fontSize: 12),
                          )
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: roleGranted
                                .map(
                                  (p) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.pal.surface2,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      _permLabel(p.key),
                                      style: AppTheme.monoXs.copyWith(
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                    const SizedBox(height: 20),
                    Text('INDIVIDUAL OVERRIDES', style: AppTheme.labelCaps),
                    const SizedBox(height: 8),
                    if (_overrides.isEmpty)
                      Text(
                        'No individual overrides.',
                        style: AppTheme.bodySub.copyWith(fontSize: 12),
                      )
                    else
                      ..._overrides.map(
                        (o) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (o.effect == 'allow'
                                        ? AppColors.teal
                                        : AppColors.coral)
                                    .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color:
                                  (o.effect == 'allow'
                                          ? AppColors.teal
                                          : AppColors.coral)
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                o.effect == 'allow'
                                    ? Symbols.add_circle
                                    : Symbols.block,
                                size: 14,
                                color: o.effect == 'allow'
                                    ? AppColors.teal
                                    : AppColors.coral,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.label,
                                      style: AppTheme.bodySm.copyWith(
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (o.reason != null)
                                      Text(
                                        o.reason!,
                                        style: AppTheme.bodySub.copyWith(
                                          fontSize: 10.5,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _removeOverride(o),
                                child: Icon(
                                  Symbols.close,
                                  size: 14,
                                  color: context.pal.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('ADD OVERRIDE', style: AppTheme.labelCaps),
                    const SizedBox(height: 8),
                    DropdownFieldBox<String>(
                      value: _newKey,
                      hint: 'Choose a permission',
                      items: allPerms
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.key,
                                  child: Text(p.label),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => _newKey = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Allow'),
                          selected: _newEffect == 'allow',
                          onSelected: (_) =>
                              setState(() => _newEffect = 'allow'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Deny'),
                          selected: _newEffect == 'deny',
                          onSelected: (_) =>
                              setState(() => _newEffect = 'deny'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LabeledTextField(label: 'Reason (optional)', controller: _reasonCtrl),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _newKey == null || _adding
                            ? null
                            : _addOverride,
                        child: _adding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Add Override'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EditRolePermissionsDialog extends StatefulWidget {
  const _EditRolePermissionsDialog({
    required this.role,
    required this.catalog,
    required this.onSave,
  });
  final RoleSummary role;
  final Map<String, List<PermissionCatalogItem>> catalog;
  final ValueChanged<List<String>> onSave;

  @override
  State<_EditRolePermissionsDialog> createState() =>
      _EditRolePermissionsDialogState();
}

class _EditRolePermissionsDialogState
    extends State<_EditRolePermissionsDialog> {
  late final Set<String> _selected = widget.role.permissionKeys.toSet();

  @override
  Widget build(BuildContext context) {
    final modules = widget.catalog.keys.toList()..sort();
    return AlertDialog(
      backgroundColor: context.pal.surface1,
      title: Text(
        'Edit Permissions — ${widget.role.name}',
        style: AppTheme.cardTitle,
      ),
      content: SizedBox(
        width: 420,
        height: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final module in modules) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(module.toUpperCase(), style: AppTheme.labelCaps),
                ),
                ...widget.catalog[module]!.map(
                  (p) => CheckboxListTile(
                    value: _selected.contains(p.key),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(p.label, style: AppTheme.bodySm),
                    subtitle: p.description != null
                        ? Text(
                            p.description!,
                            style: AppTheme.bodySub.copyWith(fontSize: 11),
                          )
                        : null,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(p.key);
                      } else {
                        _selected.remove(p.key);
                      }
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onSave(_selected.toList());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ── Shared card wrapper ─────────────────────────────────────────────────────
class _SCard extends StatelessWidget {
  const _SCard({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.pal.surface1,
      borderRadius: BorderRadius.circular(AppColors.rLg),
      border: Border.all(color: context.pal.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon!, size: 16, color: context.pal.textMute),
              const SizedBox(width: 8),
            ] else
              const SizedBox(width: 8),
            Flexible(child: Text(title, style: AppTheme.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

// ── Button helpers ──────────────────────────────────────────────────────────
class _TealBtn extends StatelessWidget {
  const _TealBtn({
    required this.label,
    required this.saving,
    required this.onTap,
  });
  final String label;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: saving ? null : onTap,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.teal,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: saving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: AppTheme.bodyStrong.copyWith(
                  color: const Color(0xFF06120F),
                  fontSize: 13,
                ),
              ),
      ),
    ),
  );
}

class _RolesViewToggleBtn extends StatelessWidget {
  const _RolesViewToggleBtn({
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.tealSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: active
            ? Border.all(color: AppColors.teal.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: active ? AppColors.teal : context.pal.textMute,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTheme.bodySm.copyWith(
              fontSize: 12,
              color: active ? AppColors.teal : context.pal.textMute,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({
    required this.label,
    required this.saving,
    required this.onTap,
  });
  final String label;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: saving ? null : onTap,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: context.pal.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: saving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, style: AppTheme.bodySm),
      ),
    ),
  );
}

// ── Dropdown helper ─────────────────────────────────────────────────────────
// ── Existing shared widgets (unchanged) ─────────────────────────────────────
class _SettingsSideItem extends StatelessWidget {
  const _SettingsSideItem({
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
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? context.pal.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: active ? context.pal.text : context.pal.textMute,
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySm.copyWith(
              color: active ? context.pal.text : context.pal.textMute,
              fontSize: 13,
            ),
          )),
        ],
      ),
    ),
  );
}

class _MemberTh extends StatelessWidget {
  const _MemberTh(this.label, {required this.flex});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.monoXs.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
  );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    this.canManage = false,
    this.onEditRole,
    this.onManagePermissions,
    this.onResetPassword,
    this.onDeactivate,
  });
  final StaffMember member;
  final bool canManage;
  final VoidCallback? onEditRole;
  final VoidCallback? onManagePermissions;
  final VoidCallback? onResetPassword;
  final VoidCallback? onDeactivate;

  // Reads the live map first: [member] can be a copy loaded at the start of
  // the session, and polls deliberately don't replace it for a timestamp tick.
  String _lastActiveLabel(Map<int, DateTime?> live) {
    final dt = live.containsKey(member.id) ? live[member.id] : member.lastActiveAt;
    if (dt == null) return 'Never'; // hasn't used the app since accounts were set up
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 5) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel(member.role);
    final roleColor = switch (member.role.toLowerCase()) {
      'admin' => AppColors.teal,
      'finance' => AppColors.amber,
      'sales' => AppColors.violet,
      _ => context.pal.textMute,
    };
    final isActive =
        member.availStatus == AvailStatus.available ||
        member.availStatus == AvailStatus.atDesk;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.pal.divider)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Row(
                children: [
                  AvatarWidget(
                    initials: member.initials,
                    size: 28,
                    variant: member.variant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                member.name,
                                style: AppTheme.bodyStrong.copyWith(
                                  fontSize: 12.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.teal,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Active',
                                style: AppTheme.bodySub.copyWith(
                                  color: AppColors.teal,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          member.email ?? '—',
                          style: AppTheme.bodySub.copyWith(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  roleLabel,
                  style: AppTheme.bodySub.copyWith(
                    color: roleColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: member.twoFa == true
                  ? Row(
                      children: [
                        Icon(
                          Symbols.verified_user,
                          size: 14,
                          color: AppColors.teal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Enabled',
                          style: AppTheme.bodySub.copyWith(
                            color: AppColors.teal,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(Symbols.warning, size: 14, color: AppColors.amber),
                        const SizedBox(width: 4),
                        Text(
                          'Off',
                          style: AppTheme.bodySub.copyWith(
                            color: AppColors.amber,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ValueListenableBuilder<Map<int, DateTime?>>(
                valueListenable: StaffService.instance.lastActiveNotifier,
                builder: (_, live, _) => Text(
                  _lastActiveLabel(live),
                  style: AppTheme.monoXs.copyWith(fontSize: 11),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: canManage
                ? PopupMenuButton<String>(
                    icon: Icon(
                      Symbols.more_horiz,
                      size: 16,
                      color: context.pal.textDim,
                    ),
                    onSelected: (v) {
                      if (v == 'role') onEditRole?.call();
                      if (v == 'perms') onManagePermissions?.call();
                      if (v == 'reset') onResetPassword?.call();
                      if (v == 'deactivate') onDeactivate?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'role',
                        child: Text('Edit Role'),
                      ),
                      const PopupMenuItem(
                        value: 'perms',
                        child: Text('Manage Permissions'),
                      ),
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('Reset Password'),
                      ),
                      PopupMenuItem(
                        value: 'deactivate',
                        child: Text(
                          'Deactivate',
                          style: TextStyle(color: AppColors.coral),
                        ),
                      ),
                    ],
                  )
                : Icon(
                    Symbols.more_horiz,
                    size: 16,
                    color: context.pal.textDim,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });
  final String label, sub;
  final bool value;
  // Null shows the switch disabled (e.g. a Director-only setting).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(sub, style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.teal,
          inactiveThumbColor: context.pal.textDim,
          inactiveTrackColor: context.pal.surface3,
        ),
      ],
    ),
  );
}

// The Settings text input — now the shared LabeledTextField (FieldFocusBox),
// so this page and every other screen draw fields from one piece of code.
class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.hasError = false,
  });
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final bool hasError;

  @override
  Widget build(BuildContext context) => LabeledTextField(
    label: label,
    controller: ctrl,
    hint: hint,
    obscure: obscure,
    maxLines: maxLines,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    hasError: hasError,
  );
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(label, style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
          const SizedBox(width: 4),
          Icon(Symbols.lock, size: 10, color: context.pal.textDim),
        ],
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: AppTheme.bodySm.copyWith(
          color: context.pal.textDim,
          fontSize: 12.5,
        ),
      ),
    ],
  );
}

class _AvatarMenuRow extends StatelessWidget {
  const _AvatarMenuRow({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: color ?? context.pal.textMute),
      const SizedBox(width: 10),
      Text(label, style: AppTheme.bodySm.copyWith(color: color ?? context.pal.text)),
    ],
  );
}

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: context.pal.textMute),
      const SizedBox(width: 5),
      Text(
        text,
        style: AppTheme.bodySub.copyWith(
          fontSize: 11.5,
          color: context.pal.textMute,
        ),
      ),
    ],
  );
}

class _ReadinessTile extends StatelessWidget {
  const _ReadinessTile({
    required this.icon,
    required this.ok,
    required this.label,
    required this.note,
  });
  final IconData icon;
  final bool ok;
  final String label, note;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.teal : AppColors.amber;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Icon(
            ok ? Symbols.check_circle : Symbols.warning,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.bodySm.copyWith(fontSize: 12)),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: ok ? context.pal.textMute : AppColors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.tealSoft : context.pal.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected
              ? AppColors.teal.withValues(alpha: 0.5)
              : context.pal.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected ? context.pal.text : context.pal.textMute,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

class _PasswordStrengthMeter extends StatelessWidget {
  const _PasswordStrengthMeter({required this.score, required this.hasInput});
  final int score;
  final bool hasInput;

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF4E555D),
      AppColors.coral,
      AppColors.amber,
      AppColors.cyan,
      AppColors.teal,
    ];
    const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    final color = colors[score];

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 1; i <= 4; i++) ...[
                if (i > 1) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= score ? color : context.pal.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            hasInput ? labels[score] : '',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ),
      ],
    );
  }
}

// ── Invite dialog ───────────────────────────────────────────────────────────
class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.onClose, this.onSaved});
  final VoidCallback onClose;
  final VoidCallback? onSaved;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _role = 'technician';
  String _group = 'field';
  String _zone = 'Dar es Salaam';
  bool _saving = false;
  String? _error;

  List<String> _roleNames = ['technician'];

  static const _groups = ['field', 'office', 'admin'];
  static const _groupLabels = ['Field Technician', 'Office / Sales', 'Admin'];
  static const _zones = [
    'Dar es Salaam',
    'Arusha',
    'Kilimanjaro',
    'Mwanza',
    'Mbeya',
    'Dodoma',
    'Tanga',
    'Morogoro',
    'HQ · Dar es Salaam',
  ];

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await RoleService.instance.list();
      if (!mounted || roles.isEmpty) return;
      setState(() {
        _roleNames = roles.map((r) => r.name).toList();
        _role = _roleNames.contains('technician')
            ? 'technician'
            : _roleNames.first;
      });
    } catch (_) {
      // Non-fatal —keeps the single-item fallback list so the dialog stays usable.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty)
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await StaffService.instance.create({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': _role,
        'group': _group,
        'zone': _zone,
        'workload': 0.0,
        'is_active': true,
      });
      StaffService.instance.invalidateCache();
      widget.onSaved?.call();
    } catch (e) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
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
          width: 480,
          decoration: BoxDecoration(
            color: context.pal.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.pal.borderStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0x70000000),
                blurRadius: 60,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Symbols.person_add, size: 18, color: AppColors.teal),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Add Team Member', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Icon(
                        Symbols.close,
                        size: 18,
                        color: context.pal.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SettingsField(
                            label: 'Full name',
                            ctrl: _nameCtrl,
                            hint: 'e.g. Asha Komba',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _SettingsField(
                            label: 'Email',
                            ctrl: _emailCtrl,
                            hint: 'email@company.tz',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SettingsField(
                            label: 'Phone',
                            ctrl: _phoneCtrl,
                            hint: '+255 7XX XXX XXX',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _HDropdown(
                            label: 'Role',
                            value: _role,
                            items: _roleNames,
                            display: _roleNames.map(_roleLabel).toList(),
                            onChanged: (v) => setState(() => _role = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _HDropdown(
                            label: 'Group',
                            value: _group,
                            items: _groups,
                            display: _groupLabels,
                            onChanged: (v) => setState(() => _group = v),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _HDropdown(
                            label: 'Zone / Region',
                            value: _zone,
                            items: _zones,
                            onChanged: (v) => setState(() => _zone = v),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.coral,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _OutlineBtn(
                        label: 'Cancel',
                        saving: false,
                        onTap: widget.onClose,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TealBtn(
                        label: 'Add Member',
                        saving: _saving,
                        onTap: _save,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      )),
    ),
  );
}

class _HDropdown extends StatelessWidget {
  const _HDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.display,
    required this.onChanged,
  });
  final String label, value;
  final List<String> items;
  final List<String>? display;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    // min: inside a dialog an unsized Column took the whole screen height
    // (the Edit Role card stretched to the bottom of the window).
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTheme.fieldLabel),
      const SizedBox(height: 6),
      DropdownFieldBox<String>(
        value: value,
        items: items
                .asMap()
                .entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.value,
                    child: Text(display != null ? display![e.key] : e.value),
                  ),
                )
                .toList(),
        onChanged: (v) {
              if (v != null) onChanged(v);
            },
      ),
    ],
  );
}
