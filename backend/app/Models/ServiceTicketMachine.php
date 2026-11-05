<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * LEGACY STUB — not used by the application. Exists only for
 * ServiceTicket::machinePivots(), which the historical migration
 * 2026_09_21_120000_backfill_orphaned_service_ticket_machines queries.
 * See App\Models\ServiceTicket.
 */
class ServiceTicketMachine extends Model
{
    protected $table = 'service_ticket_machines';

    protected $guarded = ['*'];
}
