<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * LEGACY STUB — not used by the application.
 *
 * The service module (tickets, technicians, service reports) was removed
 * from this stripped build. This bare model only exists because two
 * historical migrations (2026_09_21_110000_create_service_ticket_machines_table
 * and 2026_09_21_120000_backfill_orphaned_service_ticket_machines) import
 * App\Models\ServiceTicket, and migrations must stay untouched so both an
 * existing database and a fresh one keep migrating. Do not build features
 * on it; the service_tickets table is left in place unused.
 */
class ServiceTicket extends Model
{
    protected $table = 'service_tickets';

    protected $guarded = ['*'];

    public function machinePivots()
    {
        return $this->hasMany(ServiceTicketMachine::class, 'service_ticket_id');
    }
}
