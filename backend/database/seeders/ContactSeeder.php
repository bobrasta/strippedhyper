<?php

namespace Database\Seeders;

use App\Models\Contact;
use App\Models\Hospital;
use Illuminate\Database\Seeder;

class ContactSeeder extends Seeder
{
    public function run(): void
    {
        // First five clients (hospitals table = customer records).
        $hospitalIds = Hospital::orderBy('id')->limit(5)->pluck('id')->values();

        $contacts = [
            ['first_name' => 'Hamisi',   'last_name' => 'Salim',    'job_title' => 'Managing Director',     'department' => 'Administration', 'email' => 'h.salim@kariakoo.co.tz',       'phone' => '+255 22 215 0610', 'hospital_id' => $hospitalIds[0] ?? null, 'tags' => ['decision-maker', 'key-contact']],
            ['first_name' => 'Rehema',   'last_name' => 'Ally',     'job_title' => 'Office Manager',        'department' => 'Operations',     'email' => 'r.ally@upangaoffice.co.tz',    'phone' => '+255 22 211 4096', 'hospital_id' => $hospitalIds[1] ?? null, 'tags' => ['procurement', 'key-contact']],
            ['first_name' => 'Angela',   'last_name' => 'Mrema',    'job_title' => 'Operations Manager',    'department' => 'Operations',     'email' => 'a.mrema@moshisupplies.co.tz',      'phone' => '+255 27 275 4377', 'hospital_id' => $hospitalIds[2] ?? null, 'tags' => ['operations', 'key-contact']],
            ['first_name' => 'Francis',  'last_name' => 'Magesa',   'job_title' => 'Procurement Officer',   'department' => 'Procurement',    'email' => 'f.magesa@lakezone.co.tz',  'phone' => '+255 28 250 0611', 'hospital_id' => $hospitalIds[3] ?? null, 'tags' => ['procurement']],
            ['first_name' => 'Consolata','last_name' => 'Mwita',    'job_title' => 'Head of Supplies',      'department' => 'Administration', 'email' => 'c.mwita@dodomamc.go.tz',    'phone' => '+255 26 232 1180', 'hospital_id' => $hospitalIds[4] ?? null, 'tags' => ['decision-maker']],
        ];

        foreach ($contacts as $c) {
            $tags = $c['tags'];
            unset($c['tags']);
            $contact = Contact::create($c);
            foreach ($tags as $tag) {
                $contact->tags()->create(['tag' => $tag]);
            }
            $contact->interactions()->create([
                'type'    => 'call',
                'summary' => 'Initial follow-up call regarding a supply contract.',
                'outcome' => 'Positive. Interested in an annual supply agreement.',
                'next_action' => 'Send proposal document',
                'next_action_date' => now()->addDays(7)->toDateString(),
            ]);
        }
    }
}
