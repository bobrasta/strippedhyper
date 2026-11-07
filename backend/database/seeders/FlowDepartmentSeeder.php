<?php

namespace Database\Seeders;

use App\Models\FlowDepartment;
use Illuminate\Database\Seeder;

// Seeds the department flow diagrams from the original flowchart TD.mmd
// (bienhypermed repo root) for the shareable research/sampling editor.
// firstOrCreate on key so re-running never duplicates or wipes edits real
// staff have since made — it only fills in a department that has no row yet.
// Stripped build: the SERVICE (service ticket) diagram is no longer seeded;
// an existing row is kept but hidden by FlowController::RETIRED.
class FlowDepartmentSeeder extends Seeder
{
    public function run(): void
    {
        $path = __DIR__.'/data/flow_departments.json';
        $departments = json_decode(file_get_contents($path), true);

        foreach ($departments as $key => $d) {
            FlowDepartment::firstOrCreate(
                ['key' => $key],
                ['title' => $d['title'], 'nodes' => $d['nodes'], 'edges' => $d['edges']]
            );
        }

        // Old title referred to service tickets; only renamed if untouched.
        FlowDepartment::where('key', 'TASKS')->where('title', '📋 Task Board (non-ticket)')
            ->update(['title' => '📋 Task Board']);
    }
}
