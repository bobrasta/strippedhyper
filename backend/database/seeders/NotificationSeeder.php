<?php

namespace Database\Seeders;

use App\Models\AppNotification;
use Illuminate\Database\Seeder;

class NotificationSeeder extends Seeder
{
    public function run(): void
    {
        $notifications = [
            ['user_id' => 1, 'type' => 'payment_overdue',   'title' => 'Invoice overdue',                'body' => 'Invoice INV-1003 for Moshi Supplies Co. is overdue. Amount: TZS 2,242,000.',                'entity_type' => 'invoice', 'entity_id' => 3,  'is_read' => false],
            ['user_id' => 5, 'type' => 'deal_updated',      'title' => 'Lead moved to Demo Scheduled',  'body' => 'Lead for Kariakoo Traders office furniture has been moved to Demo Scheduled stage.',                    'entity_type' => 'deal',    'entity_id' => 2,  'is_read' => false],
            ['user_id' => 1, 'type' => 'payment_overdue',   'title' => 'Invoice overdue',                'body' => 'Invoice INV-1006 for Dodoma Municipal Council is 30 days overdue.',           'entity_type' => 'invoice', 'entity_id' => 6,  'is_read' => true],
        ];

        foreach ($notifications as $n) {
            AppNotification::create($n);
        }
    }
}
