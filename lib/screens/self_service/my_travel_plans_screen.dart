import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../models/per_diem_request.dart';
import '../../services/per_diem_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/api_error.dart';
import '../../utils/pdf_download.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/phone_layout.dart';
import '../approvals/per_diem_revise_dialog.dart';
import 'travel_plan_dialog.dart';
import 'travel_plan_viewer.dart';

// "My travel plans" — the caller's own per-diem requests (scoped
// server-side by PerDiemController::index()), plus "New travel plan".
class MyTravelPlansScreen extends StatefulWidget {
  const MyTravelPlansScreen({super.key});

  @override
  State<MyTravelPlansScreen> createState() => _MyTravelPlansScreenState();
}

class _MyTravelPlansScreenState extends State<MyTravelPlansScreen> {
  List<PerDiemRequest> _plans = [];
  bool    _loading = true;
  bool    _showNewPlan = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Stale-while-revalidate: show the last-known default (unfiltered)
    // plan list instantly if cached, then quietly refresh.
    final cached = PerDiemService.cachedDefaultList;
    if (cached != null) { _plans = cached; _loading = false; }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      if (_plans.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final results = await PerDiemService.instance.list();
      if (mounted) setState(() { _plans = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _downloadPdf(PerDiemRequest p) => downloadPdf(
    context, () => PerDiemService.instance.pdfBytes(p.id), 'travel-plan-${p.id}.pdf',
  );

  // Section 15.5: reproduces the approved WORKPLAN template cell-for-cell.
  Future<void> _downloadXlsx(PerDiemRequest p) => downloadPdf(
    context, () => PerDiemService.instance.xlsxBytes(p.id), 'travel-plan-${p.id}.xlsx',
  );

  // Section 8: "the CTO grants edit permission on a specific plan... while
  // granted, the technician can edit only what was unlocked." Reuses the
  // same day-by-day editor the CTO uses, in propose mode — the edit is
  // stored for CTO review, not applied immediately.
  void _showProposeEditDialog(PerDiemRequest p) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => PerDiemReviseDialog(
        request: p,
        isProposal: true,
        onClose: () => Navigator.of(dialogCtx).pop(),
        onSaved: () {
          Navigator.of(dialogCtx).pop();
          if (mounted) { showSuccessToast(context, 'Edit submitted — awaiting CTO approval.'); _load(); }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      LayoutBuilder(builder: (ctx, cst) {
      final pad = cst.maxWidth < 560 ? 16.0 : 28.0;
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TitleWithActions(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('My Travel Plans', style: AppTheme.pageTitle),
                const SizedBox(height: 4),
                Text('Status of per-diem requests you\'ve submitted', style: AppTheme.bodySub),
              ]),
              actions: [
                AppButton(label: 'New travel plan', icon: Symbols.add, variant: BtnVariant.primary, onPressed: () => setState(() => _showNewPlan = true)),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 48), child: CircularProgressIndicator(strokeWidth: 2)))
            // A background refresh failing while stale-but-valid cached
            // data is already showing shouldn't blow that away.
            else if (_error != null && _plans.isEmpty)
              ErrorView(message: _error!, onRetry: _load)
            else if (_plans.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('No travel plans submitted yet', style: TextStyle(color: context.pal.textMute))))
            else
              Column(children: _plans.map((p) => _PlanCard(
                plan: p,
                onView: () => openTravelPlanViewer(context, p),
                onDownload: () => _downloadPdf(p),
                onDownloadXlsx: () => _downloadXlsx(p),
                onProposeEdit: p.hasActiveEditGrant ? () => _showProposeEditDialog(p) : null,
              )).toList()),
          ]),
        ),
      );
    }),
      if (_showNewPlan)
        TravelPlanDialog(
          onClose: () => setState(() => _showNewPlan = false),
          onSaved: () {
            setState(() => _showNewPlan = false);
            _load();
            showSuccessToast(context, 'Travel plan submitted for approval.');
          },
        ),
    ]);
  }
}

Color _stageColor(PerDiemRequest p) {
  if (p.status == PerDiemStatus.rejected) return AppColors.coral;
  if (p.status == PerDiemStatus.cancelled) return AppColors.textMute;
  if (p.isPaid) return AppColors.teal;
  if (p.isPendingTeamLead) return AppColors.amber;
  if (p.isPendingCto) return AppColors.blue;
  if (p.isPendingPayment) return AppColors.violet;
  if (p.isPendingDirector) return AppColors.teal;
  return AppColors.textMute;
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan, required this.onView,
    required this.onDownload, required this.onDownloadXlsx, this.onProposeEdit,
  });
  final PerDiemRequest plan;
  // Section 15.4: the full plan opens in the template-ordered viewer.
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onDownloadXlsx;
  // Non-null only when the CTO has granted this technician edit access on
  // this plan (Section 8: "a technician cannot edit by default").
  final VoidCallback? onProposeEdit;

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(plan);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: context.pal.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: onView,
          child: Row(children: [
            Icon(Symbols.flight_takeoff, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(plan.destination, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
            if (plan.wasEdited) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Text('Edited by CTO', style: AppTheme.bodySub.copyWith(color: AppColors.amber, fontSize: 10)),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(plan.status.label, style: AppTheme.bodySub.copyWith(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Icon(Symbols.chevron_right, size: 18, color: context.pal.textDim),
          ]),
        ),
        const SizedBox(height: 10),
        Text('${plan.startDate} → ${plan.endDate}  ·  ${plan.daysCount} day(s)  ·  TSh ${plan.amount}', style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
        if (plan.status == PerDiemStatus.rejected && plan.rejectionReason != null) ...[
          const SizedBox(height: 6),
          Text('Reason: ${plan.rejectionReason}', style: AppTheme.bodySub.copyWith(color: AppColors.coral, fontSize: 12)),
        ],
        if (plan.status == PerDiemStatus.cancelled && plan.cancellationReason != null) ...[
          const SizedBox(height: 6),
          Text('Reason: ${plan.cancellationReason}', style: AppTheme.bodySub.copyWith(color: context.pal.textMute, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        if (plan.hasActiveEditGrant) ...[
          Builder(builder: (context) {
            final pendingReview = plan.revisions.where((r) => r.isPendingReview).isNotEmpty;
            if (pendingReview) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Your proposed edit is awaiting CTO review.', style: AppTheme.bodySub.copyWith(fontSize: 12, color: AppColors.blue)),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('The CTO has given you edit access on this plan.', style: AppTheme.bodySub.copyWith(fontSize: 12, color: context.pal.textDim)),
            );
          }),
        ],
        Align(alignment: Alignment.centerRight, child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          GestureDetector(
            onTap: onView,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Symbols.description, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text('View plan', style: AppTheme.bodySub.copyWith(fontSize: 12, color: Colors.white)),
              ]),
            ),
          ),
          if (onProposeEdit != null && plan.revisions.where((r) => r.isPendingReview).isEmpty) ...[
            GestureDetector(
              onTap: onProposeEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Symbols.edit_calendar, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Propose Edit', style: AppTheme.bodySub.copyWith(fontSize: 12, color: Colors.white)),
                ]),
              ),
            ),
          ],
          GestureDetector(
            onTap: onDownload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.download, size: 14, color: AppColors.teal),
                const SizedBox(width: 6),
                Text('Download PDF', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ]),
            ),
          ),
          GestureDetector(
            onTap: onDownloadXlsx,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(border: Border.all(color: context.pal.border), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.table_chart, size: 14, color: AppColors.teal),
                const SizedBox(width: 6),
                Text('Download XLSX', style: AppTheme.bodySub.copyWith(fontSize: 12)),
              ]),
            ),
          ),
        ])),
      ]),
    );
  }
}
