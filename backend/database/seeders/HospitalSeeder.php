<?php

namespace Database\Seeders;

use App\Models\Hospital;
use Illuminate\Database\Seeder;

// Demo clients. The `hospitals` table is the customer record (invoices,
// contacts, sales orders and leads carry hospital_id); the table name is
// historical.
class HospitalSeeder extends Seeder
{
    public function run(): void
    {
        $clients = [
            ['name' => 'Kariakoo Traders Ltd',        'short_code' => 'KTL', 'type' => 'private', 'region' => 'Dar es Salaam', 'district' => 'Ilala',     'contact_name' => 'Hamisi Salim',    'contact_phone' => '+255 22 215 0610'],
            ['name' => 'Upanga Office Solutions',     'short_code' => 'UOS', 'type' => 'private', 'region' => 'Dar es Salaam', 'district' => 'Upanga',    'contact_name' => 'Rehema Ally',     'contact_phone' => '+255 22 211 4096'],
            ['name' => 'Moshi Supplies Co.',          'short_code' => 'MSC', 'type' => 'private', 'region' => 'Kilimanjaro',   'district' => 'Moshi',     'contact_name' => 'Angela Mrema',    'contact_phone' => '+255 27 275 4377'],
            ['name' => 'Lake Zone Distributors',      'short_code' => 'LZD', 'type' => 'private', 'region' => 'Mwanza',        'district' => 'Nyamagana', 'contact_name' => 'Francis Magesa',  'contact_phone' => '+255 28 250 0611'],
            ['name' => 'Dodoma Municipal Council',    'short_code' => 'DMC', 'type' => 'public',  'region' => 'Dodoma',        'district' => 'Dodoma',    'contact_name' => 'Consolata Mwita', 'contact_phone' => '+255 26 232 1180'],
            ['name' => 'Mbeya Agro Processors',       'short_code' => 'MAP', 'type' => 'private', 'region' => 'Mbeya',         'district' => 'Mbeya',     'contact_name' => 'Joseph Mwambela', 'contact_phone' => '+255 25 250 2329'],
            ['name' => 'Arusha Safari Lodges',        'short_code' => 'AHG', 'type' => 'private', 'region' => 'Arusha',        'district' => 'Arusha',    'contact_name' => 'Veronica Laizer', 'contact_phone' => '+255 27 254 8282'],
            ['name' => 'Kinondoni Schools Trust',     'short_code' => 'KST', 'type' => 'mission', 'region' => 'Dar es Salaam', 'district' => 'Kinondoni', 'contact_name' => 'Pius Nkya',       'contact_phone' => '+255 22 277 0006'],
        ];

        foreach ($clients as $c) {
            Hospital::create($c);
        }
    }
}
