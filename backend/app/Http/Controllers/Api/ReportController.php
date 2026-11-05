<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Invoice;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;

class ReportController extends Controller
{
    public function index()
    {
        $cacheKey = 'reports:summary:' . now()->format('Y-m-d-H');

        $data = Cache::remember($cacheKey, 300, function () {
            // Single GROUP BY query instead of 6 individual month queries
            $start = Carbon::now()->subMonths(5)->startOfMonth()->toDateString();

            $rows = Invoice::whereIn('status', ['paid', 'partial'])
                ->where('issue_date', '>=', $start)
                ->selectRaw("TO_CHAR(issue_date, 'YYYY-MM') AS month_key, SUM(amount_paid) AS total")
                ->groupByRaw("TO_CHAR(issue_date, 'YYYY-MM')")
                ->pluck('total', 'month_key');

            $revenueByMonth = collect(range(5, 0))->map(function ($offset) use ($rows) {
                $month = Carbon::now()->subMonths($offset);
                $key   = $month->format('Y-m');

                return [
                    'month'  => $key,
                    'label'  => $month->format('M Y'),
                    'amount' => (int) ($rows[$key] ?? 0),
                ];
            })->values();

            return [
                'revenue_last_6_months'  => $revenueByMonth,
            ];
        });

        return response()->json(['data' => $data]);
    }
}
