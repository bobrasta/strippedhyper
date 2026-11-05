<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\InventoryItemResource;
use App\Models\InventoryItem;
use App\Models\Location;
use App\Models\SerialNumber;
use App\Services\StockService;
use Illuminate\Http\Request;

class InventoryController extends Controller
{
    public function index(Request $request)
    {
        $query = InventoryItem::with(['category', 'stockLevels.location'])
            ->where('is_active', true);

        if ($request->filled('category_id')) {
            $query->where('category_id', $request->category_id);
        }
        if ($request->boolean('low_stock')) {
            $query->whereColumn('stock_qty', '<=', 'reorder_level');
        }
        if ($request->filled('supplier')) {
            $query->where('supplier', $request->supplier);
        }
        if ($request->filled('search')) {
            $query->where(function ($q) use ($request) {
                $q->where('name', 'ilike', '%' . $request->search . '%')
                  ->orWhere('sku', 'ilike', '%' . $request->search . '%');
            });
        }

        // Default stays small for anything hitting this without an explicit per_page
        // (e.g. a future paginated table), but every current caller — Inventory Items,
        // POS catalog/scan, Add Part, Quotations/Sales Orders line-item pickers,
        // Requisitions, Stock Movements — loads the FULL catalog once client-side and
        // paginates/filters locally, so cap high rather than silently truncating a
        // 300+ item real catalog to 20.
        $perPage = min($request->integer('per_page', 20), 1000);

        return InventoryItemResource::collection($query->orderBy('name')->paginate($perPage));
    }

    public function store(Request $request)
    {
        abort_if(! $request->user()->hasInventoryManageAuthority(), 403, 'You are not authorised to manage the inventory catalog.');

        $data = $request->validate([
            'sku'                 => ['required', 'string', 'unique:inventory_items'],
            'name'                => ['required', 'string'],
            'description'         => ['nullable', 'string'],
            'category_id'         => ['nullable', 'exists:categories,id'],
            'unit_of_measure'     => ['nullable', 'in:piece,box,litre,set,kg,roll,pair,bottle'],
            'unit_cost'           => ['required', 'integer', 'min:0'],
            'currency'            => ['nullable', 'string', 'max:10'],
            'cost_currency'       => ['nullable', 'string', 'size:3'],
            'stock_qty'           => ['required', 'integer', 'min:0'],
            'reorder_level'       => ['required', 'integer', 'min:0'],
            'supplier'            => ['nullable', 'string'],
            'warranty_months'     => ['nullable', 'integer', 'min:0'],
        ]);

        // The unit cost's currency (TZS unless given). 'currency' was never
        // stored (not fillable); older apps sending it mean the cost's.
        $data['cost_currency'] = strtoupper($data['cost_currency'] ?? $data['currency'] ?? 'TZS');
        unset($data['currency']);

        $item = InventoryItem::create($data);

        return response()->json(['data' => new InventoryItemResource($item->load(['category']))], 201);
    }

    // Minimal-friction creation for a part that isn't catalogued yet — auto-fills everything store() otherwise requires and
    // flags the item for inventory admin to properly fill in later.
    public function quickCreate(Request $request)
    {
        $data = $request->validate([
            'name'          => ['required', 'string'],
            'cost_currency' => ['nullable', 'string', 'size:3'],
        ]);

        $item = InventoryItem::create([
            'sku'           => 'QR-' . strtoupper(uniqid()),
            'name'          => $data['name'],
            'category_id'   => null,
            'unit_cost'     => 0,
            'cost_currency' => strtoupper($data['cost_currency'] ?? 'TZS'),
            'stock_qty'     => 0,
            'reorder_level' => 0,
            'needs_review'  => true,
        ]);

        return response()->json(['data' => new InventoryItemResource($item->fresh())], 201);
    }

    // Route param is {inventory} — variable name must match
    public function show(InventoryItem $inventory)
    {
        $inventory->load(['category', 'stockLevels.location']);

        return response()->json(['data' => new InventoryItemResource($inventory)]);
    }

    public function update(Request $request, InventoryItem $inventory)
    {
        abort_if(! $request->user()->hasInventoryManageAuthority(), 403, 'You are not authorised to manage the inventory catalog.');

        $data = $request->validate([
            'sku'             => ['sometimes', 'string', 'unique:inventory_items,sku,' . $inventory->id],
            'name'            => ['sometimes', 'string'],
            'description'     => ['nullable', 'string'],
            'category_id'     => ['nullable', 'exists:categories,id'],
            'unit_of_measure' => ['nullable', 'in:piece,box,litre,set,kg,roll,pair,bottle'],
            'unit_cost'       => ['sometimes', 'integer', 'min:0'],
            'cost_currency'   => ['sometimes', 'string', 'size:3'],
            'stock_qty'       => ['sometimes', 'integer', 'min:0'],
            'reorder_level'   => ['sometimes', 'integer', 'min:0'],
            'supplier'        => ['nullable', 'string'],
            'is_active'       => ['sometimes', 'boolean'],
            'warranty_months' => ['nullable', 'integer', 'min:0'],
            'needs_review'    => ['sometimes', 'boolean'],
        ]);

        if (isset($data['cost_currency'])) {
            $data['cost_currency'] = strtoupper($data['cost_currency']);
        }
        $inventory->update($data);

        return response()->json(['data' => new InventoryItemResource($inventory->load(['category']))]);
    }

    public function destroy(Request $request, InventoryItem $inventory)
    {
        abort_if(! $request->user()->hasInventoryManageAuthority(), 403, 'You are not authorised to manage the inventory catalog.');

        $inventory->update(['is_active' => false]);

        return response()->json(['message' => 'Item deactivated.']);
    }

    public function adjust(Request $request, InventoryItem $inventoryItem, StockService $stockService)
    {
        abort_if(! $request->user()->hasStockAdjustAuthority(), 403, 'You are not authorised to adjust stock quantities.');

        $data = $request->validate([
            'location_id'  => ['required', 'exists:locations,id'],
            'new_quantity' => ['required', 'integer', 'min:0'],
            'reason'       => ['nullable', 'string'],
        ]);

        $location = Location::findOrFail($data['location_id']);

        $stockService->adjust($inventoryItem, $location, $data['new_quantity'], $data['reason'] ?? 'Manual adjustment');

        return response()->json(['data' => new InventoryItemResource(
            $inventoryItem->fresh()->load(['category', 'stockLevels.location'])
        )]);
    }

    // One row per individually tracked unit, oldest-received first —
    // received (SerialNumber) plus sold/issued from the serial's own
    // consumed_reference_* columns. installed/signed_off are always null
    // and is_equipment false now that the machines module is removed; the
    // keys stay so existing clients keep parsing the same shape.
    public function history(InventoryItem $inventoryItem)
    {
        $serials = $inventoryItem->serialNumbers()->orderBy('id')->get();

        $history = $serials->map(fn (SerialNumber $serial) => [
            'serial_number'  => $serial->serial_number,
            'status'         => $serial->status,
            'received_at'    => ($serial->purchase_date ?? $serial->created_at)?->toDateString(),
            'sold'           => $this->genericConsumption($serial),
            'installed'      => null,
            'signed_off'     => null,
            'is_equipment'   => false,
            'machine_status' => null,
        ]);

        return response()->json(['data' => $history]);
    }

    // A lightweight "sold/issued" entry from SerialNumber's own consumed_reference_*
    // columns (see StockService::consumeSerials()) — resolves a couple of
    // known reference types for a readable label, falls back to a generic
    // one for anything else so a new reference type never breaks History.
    private function genericConsumption(SerialNumber $serial): ?array
    {
        if (! $serial->consumed_reference_type) {
            return null;
        }

        $label = match ($serial->consumed_reference_type) {
            \App\Models\SalesOrder::class => optional(
                \App\Models\SalesOrder::find($serial->consumed_reference_id)
            )->order_number,
            default => class_basename($serial->consumed_reference_type) . ' #' . $serial->consumed_reference_id,
        };

        return [
            'sales_order_id'     => null,
            'sales_order_number' => $label,
            'hospital_name'      => null,
            'delivered_at'       => $serial->consumed_at?->toDateString(),
        ];
    }
}
