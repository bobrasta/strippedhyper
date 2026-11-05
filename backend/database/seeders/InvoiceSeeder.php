<?php

namespace Database\Seeders;

use App\Models\Hospital;
use App\Models\Invoice;
use Illuminate\Database\Seeder;

class InvoiceSeeder extends Seeder
{
    public function run(): void
    {
        // hospital_id used to be hardcoded 1-11, but those belonged to the
        // original demo hospitals RemoveDemoDataSeeder deletes in favor of
        // the real facility import. Pick real client hospitals instead
        // (machine_count is the stored legacy installed-base count).
        $hospitals = Hospital::where('machine_count', '>', 0)->orderBy('id')->limit(6)->get();
        $h = fn (int $i) => $hospitals[$i % max($hospitals->count(), 1)] ?? null;

        $invoices = [
            ['invoice_number' => 'INV-1001', 'hospital_id' => $h(0)?->id, 'issue_date' => '2026-03-01', 'due_date' => '2026-03-31', 'subtotal' => 3200000, 'tax_rate' => 18, 'tax_amount' => 576000,  'total' => 3776000,  'amount_paid' => 3776000,  'status' => 'paid',     'currency' => 'TZS', 'notes' => 'Q1 maintenance contract'],
            ['invoice_number' => 'INV-1002', 'hospital_id' => $h(1)?->id, 'issue_date' => '2026-03-05', 'due_date' => '2026-04-04', 'subtotal' => 5800000, 'tax_rate' => 18, 'tax_amount' => 1044000, 'total' => 6844000,  'amount_paid' => 3422000,  'status' => 'partial',  'currency' => 'TZS', 'notes' => 'MRI monthly service fee'],
            ['invoice_number' => 'INV-1003', 'hospital_id' => $h(2)?->id, 'issue_date' => '2026-02-14', 'due_date' => '2026-03-14', 'subtotal' => 1900000, 'tax_rate' => 18, 'tax_amount' => 342000,  'total' => 2242000,  'amount_paid' => 0,        'status' => 'overdue',  'currency' => 'TZS', 'notes' => 'Biochem analyser parts replacement'],
            ['invoice_number' => 'INV-1004', 'hospital_id' => $h(3)?->id, 'issue_date' => '2026-04-01', 'due_date' => '2026-04-30', 'subtotal' => 2400000, 'tax_rate' => 18, 'tax_amount' => 432000,  'total' => 2832000,  'amount_paid' => 0,        'status' => 'pending',  'currency' => 'TZS', 'notes' => 'Annual service contract Q2'],
            ['invoice_number' => 'INV-1005', 'hospital_id' => $h(0)?->id, 'issue_date' => '2026-04-10', 'due_date' => '2026-05-10', 'subtotal' => 2800000, 'tax_rate' => 18, 'tax_amount' => 504000,  'total' => 3304000,  'amount_paid' => 3304000,  'status' => 'paid',     'currency' => 'TZS', 'notes' => 'X-Ray calibration + parts'],
            ['invoice_number' => 'INV-1006', 'hospital_id' => $h(4)?->id, 'issue_date' => '2026-01-20', 'due_date' => '2026-02-19', 'subtotal' => 1600000, 'tax_rate' => 18, 'tax_amount' => 288000,  'total' => 1888000,  'amount_paid' => 0,        'status' => 'overdue',  'currency' => 'TZS', 'notes' => 'Ventilator repair parts'],
        ];

        foreach ($invoices as $inv) {
            $invoice = Invoice::create($inv);
            $invoice->lineItems()->create([
                'description' => 'Service fee',
                'quantity'    => 1.0,
                'unit_price'  => $inv['subtotal'],
                'total'       => $inv['subtotal'],
            ]);
        }
    }
}
