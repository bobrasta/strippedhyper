import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show can;
import '../../services/sales_team_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../utils/api_error.dart';
import '../../utils/format.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/labeled_field.dart';
import '../../widgets/common/phone_layout.dart';

// sales.create_subordinate_user has existed in the permission catalog since
// the original access-control pass, granted to sales_manager, but nothing
// ever surfaced it — a sales_manager had no way to build or see their own
// team at all. Gated by can() (matching the backend's permission check),
// not by role.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<TeamMember> _team = [];
  List<TeamActivity> _activity = [];
  bool _loading = true;
  String? _error;
  bool _showAdd = false;
  bool _showAssign = false;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known team + activity feed
    // immediately on a return visit instead of blanking to a spinner, then
    // quietly refresh in the background — see MachineService for the full
    // reasoning. cachedTeam (not cachedTeam.isNotEmpty) is the presence
    // signal since a manager legitimately having zero reports is a valid,
    // already-loaded state, not "nothing fetched yet".
    final cachedTeam = SalesTeamService.cachedTeam;
    if (cachedTeam != null) {
      _team = cachedTeam;
      _activity = SalesTeamService.cachedActivity ?? [];
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_team.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final (team, activity) = await SalesTeamService.instance.load();
      if (mounted) setState(() { _team = team; _activity = activity; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!can('sales.create_subordinate_user')) {
      return Center(child: Text('You do not have access to team management.', style: AppTheme.bodySub));
    }
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
        final pad = cst.maxWidth < 560 ? 16.0 : 26.0;
        final wide = cst.maxWidth >= 1000;
        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(width: 2, height: 36, decoration: BoxDecoration(color: AppColors.violet, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Sales Team', style: AppTheme.pageTitle.copyWith(fontSize: 23)),
                const SizedBox(height: 3),
                Text('${_team.length} rep${_team.length == 1 ? '' : 's'} reporting to you', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ])),
              OutlinedButton.icon(onPressed: () => setState(() => _showAssign = true), icon: const Icon(Symbols.link, size: 16), label: const Text('Assign existing rep')),
              const SizedBox(width: 10),
              FilledButton.icon(onPressed: () => setState(() => _showAdd = true), icon: const Icon(Symbols.person_add, size: 16), label: const Text('Add subordinate')),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  // A background refresh failing while stale-but-valid
                  // cached data is already showing shouldn't blow that away.
                  : _error != null && _team.isEmpty
                      ? ErrorView(message: _error!, onRetry: _load)
                      : wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(flex: 2, child: _teamList(context)),
                              const SizedBox(width: 16),
                              SizedBox(width: 300, child: _activityPanel(context)),
                            ])
                          : Column(children: [
                              _teamList(context),
                              const SizedBox(height: 16),
                              _activityPanel(context),
                            ]),
            ),
          ]),
        );
      }),
      if (_showAdd)
        _AddSubordinateDialog(
          onClose: () => setState(() => _showAdd = false),
          onSaved: () { setState(() => _showAdd = false); _load(); },
        ),
      if (_showAssign)
        _AssignExistingDialog(
          onClose: () => setState(() => _showAssign = false),
          onAssigned: () { setState(() => _showAssign = false); _load(); },
        ),
    ]);
  }

  Widget _teamList(BuildContext context) {
    if (_team.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.group, size: 40, color: context.pal.textMute),
          const SizedBox(height: 10),
          Text('No reports yet.', style: AppTheme.bodySub),
          const SizedBox(height: 4),
          Text('Add a sales rep, or assign an existing unmanaged one.', style: AppTheme.bodySub.copyWith(fontSize: 12)),
        ])),
      );
    }
    return Container(
      decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          height: 36, padding: const EdgeInsets.symmetric(horizontal: 16),
          color: context.pal.surface2,
          child: Row(children: [
            Expanded(flex: 4, child: Text('REP', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('ZONE', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('OPEN LEADS', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('REVENUE MTD', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('MAX DISC.', style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
            Expanded(flex: 2, child: Text('STATUS', textAlign: TextAlign.right, style: AppTheme.labelCaps.copyWith(fontSize: 9.5))),
          ]),
        ),
        ..._team.map((m) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.divider))),
          child: Row(children: [
            Expanded(flex: 4, child: Row(children: [
              AvatarWidget(initials: m.initials, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(m.email, style: AppTheme.bodySub.copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ])),
            Expanded(flex: 2, child: Text(m.zone ?? '—', style: AppTheme.bodySub.copyWith(fontSize: 12))),
            Expanded(flex: 2, child: Text('${m.openLeads}', style: AppTheme.monoSm.copyWith(fontSize: 12))),
            Expanded(flex: 2, child: Text(tshFromDouble(m.revenueMtd), style: AppTheme.monoSm.copyWith(fontSize: 12))),
            Expanded(flex: 2, child: Text(m.maxDiscountPercent != null ? '${m.maxDiscountPercent!.toStringAsFixed(0)}%' : '—', style: AppTheme.monoSm.copyWith(fontSize: 12))),
            Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.teal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(m.availStatus.toUpperCase(), style: AppTheme.monoXs.copyWith(fontSize: 9, color: AppColors.teal)),
            ))),
          ]),
        )),
      ]),
    );
  }

  Widget _activityPanel(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: context.pal.surface1, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pal.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Symbols.bolt, size: 14, color: AppColors.amber),
        const SizedBox(width: 7),
        Text('RECENT TEAM ACTIVITY', style: AppTheme.labelCaps.copyWith(fontSize: 9.5)),
      ]),
      const SizedBox(height: 10),
      if (_activity.isEmpty)
        Text('No recent quotations or orders from your team yet.', style: AppTheme.bodySub.copyWith(fontSize: 12))
      else
        ..._activity.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: AppTheme.bodySm.copyWith(fontSize: 12)),
            const SizedBox(height: 2),
            Text(a.note, style: AppTheme.bodySub.copyWith(fontSize: 11)),
          ]),
        )),
    ]),
  );
}

class _AddSubordinateDialog extends StatefulWidget {
  const _AddSubordinateDialog({required this.onClose, required this.onSaved});
  final VoidCallback onClose;
  final VoidCallback onSaved;

  @override
  State<_AddSubordinateDialog> createState() => _AddSubordinateDialogState();
}

class _AddSubordinateDialogState extends State<_AddSubordinateDialog> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name and email are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      // role/manager_id are forced server-side to 'sales'/self regardless
      // of what's sent — see StaffController::store()'s
      // hasSalesCreateSubordinateAuthority() branch.
      await StaffService.instance.create({
        'name':  _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'role':  'sales',
      });
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
                Icon(Symbols.person_add, size: 18, color: AppColors.violet),
                const SizedBox(width: 10),
                Expanded(child: Text('Add Subordinate', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.coralSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)),
                  ),
                ],
                Text('New reps join with the role Sales Rep, reporting to you.', style: AppTheme.bodySub.copyWith(fontSize: 12)),
                const SizedBox(height: 14),
                LabeledTextField(label: 'Full name', controller: _nameCtrl),
                const SizedBox(height: 12),
                LabeledTextField(label: 'Email address', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                LabeledTextField(label: 'Phone (optional)', controller: _phoneCtrl, keyboardType: TextInputType.phone),
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
                      : Text('Add', style: AppTheme.bodyStrong.copyWith(color: const Color(0xFF06120F), fontSize: 13)))))),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );
}

// Claims an existing real account that has role='sales' but no manager at
// all — e.g. one created directly via Staff rather than through this
// screen. Narrow by design (server-enforced): only unmanaged reps show up
// here, so a manager can never see or grab someone already reporting
// elsewhere.
class _AssignExistingDialog extends StatefulWidget {
  const _AssignExistingDialog({required this.onClose, required this.onAssigned});
  final VoidCallback onClose;
  final VoidCallback onAssigned;

  @override
  State<_AssignExistingDialog> createState() => _AssignExistingDialogState();
}

class _AssignExistingDialogState extends State<_AssignExistingDialog> {
  List<UnassignedRep> _reps = [];
  bool _loading = true;
  int? _assigning;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final reps = await SalesTeamService.instance.unassigned();
      if (mounted) setState(() { _reps = reps; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _assign(UnassignedRep r) async {
    setState(() => _assigning = r.id);
    try {
      await SalesTeamService.instance.assign(r.id);
      widget.onAssigned();
    } catch (e) {
      if (mounted) { setState(() { _assigning = null; _error = friendlyError(e); }); }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onClose,
    child: Container(
      color: const Color(0xAA06070A),
      alignment: Alignment.center,
      child: PhoneModalBox(scroll: false, child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 460,
          constraints: const BoxConstraints(maxHeight: 480),
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
                Icon(Symbols.link, size: 18, color: AppColors.violet),
                const SizedBox(width: 10),
                Expanded(child: Text('Assign Existing Rep', style: AppTheme.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: widget.onClose, child: Icon(Symbols.close, size: 18, color: context.pal.textDim)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Sales reps that exist but report to nobody yet.', style: AppTheme.bodySub.copyWith(fontSize: 12)),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  : _error != null
                      ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: TextStyle(color: AppColors.coral, fontSize: 12)))
                      : _reps.isEmpty
                          ? Padding(padding: const EdgeInsets.all(24), child: Text('No unmanaged reps found.', style: AppTheme.bodySub))
                          : ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              children: _reps.map((r) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: context.pal.surface2, borderRadius: BorderRadius.circular(8)),
                                child: Row(children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r.name, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
                                    Text(r.email, style: AppTheme.bodySub.copyWith(fontSize: 11)),
                                  ])),
                                  GestureDetector(
                                    onTap: _assigning == r.id ? null : () => _assign(r),
                                    child: Container(
                                      height: 30, padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(7)),
                                      child: Center(child: _assigning == r.id
                                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                          : Text('Assign', style: AppTheme.bodySm.copyWith(color: const Color(0xFF06120F), fontWeight: FontWeight.w700, fontSize: 12))),
                                    ),
                                  ),
                                ]),
                              )).toList(),
                            ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      )),
    ),
  );
}
