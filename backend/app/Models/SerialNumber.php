<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SerialNumber extends Model
{
    protected $fillable = [
        'inventory_item_id', 'serial_number', 'status', 'has_missing_parts',
        'location_id',
        'purchase_date', 'warranty_expires_at', 'notes',
        'consumed_reference_type', 'consumed_reference_id', 'consumed_at',
    ];

    protected $casts = [
        'purchase_date'      => 'date',
        'warranty_expires_at'=> 'date',
        'has_missing_parts'  => 'boolean',
        'consumed_at'        => 'datetime',
    ];

    public function inventoryItem(): BelongsTo
    {
        return $this->belongsTo(InventoryItem::class);
    }

    public function location(): BelongsTo
    {
        return $this->belongsTo(Location::class);
    }

    public function isWarrantyExpired(): bool
    {
        return $this->warranty_expires_at && $this->warranty_expires_at->isPast();
    }
}
