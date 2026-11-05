<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Expense;
use App\Models\LeaveRequest;
use App\Models\PerDiemRequest;
use App\Models\PurchaseOrder;
use App\Models\Quotation;
use App\Models\StockOutRequest;
use Illuminate\Http\Request;

/**
 * Admin/Director-only "Command Centre" — a fixed bespoke layout
 * (cross-department exception feed + compact per-department mini-panels), not the permission-list-driven section
 * approach UnifiedDashboardController uses for every other role. Reuses
 * that controller's builders wherever the data overlaps rather than
 * re-querying.
 */
class AdminOverviewController extends Controller
{
    private const PENDING_PO_STATUSES = [
        'pending_sales_manager', 'pending_director_review',
        'pending_payment_initiation', 'pending_director_final',
    ];

    private const PENDING_PER_DIEM_STATUSES = [
        'pending_team_lead', 'pending_cto', 'pending_payment', 'pending_director',
    ];

    public function __construct(
        private DashboardController $dashboard,
        private FinanceReportController $financeReports,
        private HrReportController $hrReports,
    ) {
    }

    public function index(Request $request)
    {
        abort_if(! $request->user()->hasDirectorAuthority(), 403, 'Access Denied: admin/director only.');

        $sales = $this->dashboard->buildSales();
        $inventory = $this->dashboard->buildInventory();
        $trend = $this->financeReports->buildMonthlyTrend();
        $hr = $this->hrReports->buildHeadcountBreakdown();

        $netProfitThisMonth = (int) (collect($trend)->last()['net_profit'] ?? 0);

        return response()->json(['data' => [
            'greeting' => [
                'name' => $request->user()->name,
                'date' => now()->format('d M Y'),
            ],
            'kpis' => [
                'cash_position'  => $netProfitThisMonth,
                'pipeline_value' => $sales['kpi']['pipeline_value'] ?? 0,
            ],
            'attention' => $this->attentionFeed($inventory),
            'sales'     => $sales,
            'finance'   => ['months' => $trend],
            'inventory' => $inventory,
            'people'    => $this->peopleSummary($hr),
        ]]);
    }

    // Newest/most-severe first, capped at 6 — deliberately a rollup for
    // low-stock/approvals (one summary row each), not one row per request,
    // matching the reference design's own "N more in the approvals queue"
    // footer pattern rather than trying to enumerate every pending item
    // from every module here.
    private function attentionFeed(array $inventory): array
    {
        $items = [];

        $staleQuotation = Quotation::where('status', 'sent')->oldest('updated_at')->first();
        if ($staleQuotation) {
            $items[] = [
                'title' => "Quotation awaiting client — {$staleQuotation->client_name}",
                'meta'  => "{$staleQuotation->quotation_number} · TSh {$staleQuotation->total_amount}",
                'age'   => $staleQuotation->updated_at?->diffForHumans(null, true),
                'severity' => 'warning',
            ];
        }

        if (($inventory['low_stock_count'] ?? 0) > 0) {
            $items[] = [
                'title' => "{$inventory['low_stock_count']} items below reorder level",
                'meta'  => 'Inventory · ' . ($inventory['open_purchase_orders'] ?? 0) . ' purchase orders raised',
                'age'   => null,
                'severity' => 'warning',
            ];
        }

        $pendingApprovals = StockOutRequest::where('status', 'pending')->count()
            + PerDiemRequest::whereIn('status', self::PENDING_PER_DIEM_STATUSES)->count()
            + Expense::whereIn('status', ['pending_manager', 'pending_cto', 'pending_director'])->count()
            + PurchaseOrder::whereIn('status', self::PENDING_PO_STATUSES)->count()
            + LeaveRequest::where('status', 'pending')->count();

        if ($pendingApprovals > 0) {
            $items[] = [
                'title' => "{$pendingApprovals} request(s) pending your approval",
                'meta'  => 'Across stock-out, per-diem, expenses, purchase orders, leave',
                'age'   => null,
                'severity' => 'info',
            ];
        }

        return array_slice($items, 0, 6);
    }

    private function peopleSummary(array $hr): array
    {
        $today = now()->toDateString();

        return [
            'active_staff' => $hr['total'] ?? 0,
            'on_leave_today' => LeaveRequest::where('status', 'approved')
                ->whereDate('start_date', '<=', $today)
                ->whereDate('end_date', '>=', $today)
                ->count(),
            'pending_approvals' => LeaveRequest::where('status', 'pending')->count(),
        ];
    }
}
