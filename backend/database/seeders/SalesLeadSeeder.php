<?php

namespace Database\Seeders;

use App\Models\Hospital;
use App\Models\SalesLead;
use Illuminate\Database\Seeder;

class SalesLeadSeeder extends Seeder
{
    public function run(): void
    {
        // First three clients (hospitals table = customer records); the
        // others are prospects typed by name. machine_type is the product
        // of interest (column name is historical).
        $hospitals = Hospital::orderBy('id')->limit(3)->pluck('id')->values();

        $leads = [
            ['hospital_id' => null, 'hospital_name_raw' => 'Singida Traders Ltd',       'contact_name_raw' => 'Amani Kibona',      'machine_type' => 'Office supplies', 'deal_value' => 42000000, 'stage' => 'qualified',       'assigned_to' => 5],
            ['hospital_id' => $hospitals[0] ?? null,   'hospital_name_raw' => null,                         'contact_name_raw' => 'Paul Njau',         'machine_type' => 'Office furniture', 'deal_value' => 95000000, 'stage' => 'demo_scheduled',  'demo_date' => '2026-06-15', 'assigned_to' => 5],
            ['hospital_id' => null, 'hospital_name_raw' => 'Iringa Bookshop & Stationers', 'contact_name_raw' => 'Magdalena Mgaya', 'machine_type' => 'Stationery', 'deal_value' => 28000000, 'stage' => 'proposal_sent',   'assigned_to' => 5],
            ['hospital_id' => $hospitals[1] ?? null,   'hospital_name_raw' => null,                         'contact_name_raw' => 'John Masanja',      'machine_type' => 'Printers & toners', 'deal_value' => 35000000, 'stage' => 'negotiation',     'assigned_to' => 5],
            ['hospital_id' => null, 'hospital_name_raw' => 'Tabora Cooperative Union', 'contact_name_raw' => 'Baraka Said',     'machine_type' => 'Cleaning supplies', 'deal_value' => 68000000, 'stage' => 'lead',            'assigned_to' => 5],
            ['hospital_id' => $hospitals[2] ?? null,   'hospital_name_raw' => null,                         'contact_name_raw' => 'Mr. Mwambe',        'machine_type' => 'Computers', 'deal_value' => 22000000, 'stage' => 'won',        'assigned_to' => 5],
            ['hospital_id' => null, 'hospital_name_raw' => 'Dodoma Business Centre',    'contact_name_raw' => 'Sarah Mollel',      'machine_type' => 'Office chairs', 'deal_value' => 15000000, 'stage' => 'lost',            'assigned_to' => 5],
        ];

        foreach ($leads as $lead) {
            SalesLead::create($lead);
        }
    }
}
