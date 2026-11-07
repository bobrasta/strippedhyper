<?php

// Only overrides attribute names; every other validation message comes from
// the framework's own lang files (Laravel merges this over them).
// The `hospitals` table is the customer record, so its keys read as
// "client" in validation errors ("The client field is required.").
return [
    'attributes' => [
        'hospital_id'             => 'client',
        'hospital_name_raw'       => 'client name',
        'destination_hospital_id' => 'destination client',
    ],
];
