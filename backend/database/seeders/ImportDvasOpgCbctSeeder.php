<?php

namespace Database\Seeders;

use App\Models\Hospital;
use Illuminate\Database\Seeder;

/**
 * Real DVAS-C dental X-ray, OPG and CBCT client hospitals, sourced from the
 * user's own asset register. Only the hospital (customer) rows not already
 * created by RealFacilityImportSeeder are added; the machine records and
 * derived service-ticket history this seeder used to create went with the
 * machines and service modules. Idempotent (firstOrCreate by short_code).
 */
class ImportDvasOpgCbctSeeder extends Seeder
{
    public function run(): void
    {
        $newHospitals = [
            [
                'name' => 'Kaliua DH', 'short_code' => 'KADH7', 'type' => 'public',
                'region' => 'Tabora', 'district' => null, 'zone' => 'central',
                'latitude' => -5.059465, 'longitude' => 31.792861,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Dr. Jakaya Hosp. Kishapu', 'short_code' => 'DRJAH', 'type' => 'public',
                'region' => 'Shinyanga', 'district' => 'Kishapu', 'zone' => 'lake',
                'latitude' => -3.6827822, 'longitude' => 33.8177131,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Shinyanga RRH', 'short_code' => 'SHRR', 'type' => 'public',
                'region' => 'Shinyanga', 'district' => null, 'zone' => 'lake',
                'latitude' => -3.7622225, 'longitude' => 33.2320361,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Makongoro HC', 'short_code' => 'MAHC8', 'type' => 'public',
                'region' => 'Mwanza', 'district' => null, 'zone' => 'lake',
                'latitude' => -2.5099567, 'longitude' => 32.9002508,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Sokoine HC', 'short_code' => 'SOHC3', 'type' => 'public',
                'region' => 'Singida', 'district' => null, 'zone' => 'central',
                'latitude' => -5.2902148, 'longitude' => 34.6367444,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Shinyanga MC', 'short_code' => 'SHMC', 'type' => 'public',
                'region' => 'Shinyanga', 'district' => null, 'zone' => 'lake',
                'latitude' => -3.7622225, 'longitude' => 33.2320361,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Amana RRH', 'short_code' => 'AMRR', 'type' => 'public',
                'region' => 'Dar Es Salaam', 'district' => null, 'zone' => 'coastal',
                'latitude' => -6.8160837, 'longitude' => 39.2803583,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Nshambya DH', 'short_code' => 'NSDH2', 'type' => 'public',
                'region' => 'Kagera', 'district' => 'Bukoba', 'zone' => 'lake',
                'latitude' => -1.3071541, 'longitude' => 31.8099237,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Mugana Hosp.', 'short_code' => 'MUHO', 'type' => 'public',
                'region' => 'Kagera', 'district' => 'Bukoba', 'zone' => 'lake',
                'latitude' => -1.3311508, 'longitude' => 31.8125605,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Lindi RRH', 'short_code' => 'LIRR', 'type' => 'public',
                'region' => 'Lindi', 'district' => null, 'zone' => 'southern',
                'latitude' => -9.3985098, 'longitude' => 37.8997467,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Bumbuli DH', 'short_code' => 'BUDH8', 'type' => 'public',
                'region' => 'Tanga', 'district' => 'Lushoto', 'zone' => 'coastal',
                'latitude' => -4.4952844, 'longitude' => 38.4480235,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Mafia DH', 'short_code' => 'MADH6', 'type' => 'public',
                'region' => 'Pwani', 'district' => 'Mafia', 'zone' => 'coastal',
                'latitude' => -7.8166985, 'longitude' => 39.8080259,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Kaloleni HC', 'short_code' => 'KAHC8', 'type' => 'public',
                'region' => 'Arusha', 'district' => null, 'zone' => 'northern',
                'latitude' => -3.3665057, 'longitude' => 36.6890925,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Mkomaindo DH', 'short_code' => 'MKDH4', 'type' => 'public',
                'region' => 'Mtwara', 'district' => null, 'zone' => 'southern',
                'latitude' => -10.7310331, 'longitude' => 38.7962486,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Mbuba DH', 'short_code' => 'MBDH4', 'type' => 'public',
                'region' => 'Kagera', 'district' => 'Ngara', 'zone' => 'lake',
                'latitude' => -2.7252664, 'longitude' => 30.5935542,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Kilosa DH', 'short_code' => 'KIDH10', 'type' => 'public',
                'region' => 'Morogoro', 'district' => null, 'zone' => 'coastal',
                'latitude' => -6.8363175, 'longitude' => 36.985732,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Ludewa DH', 'short_code' => 'LUDH', 'type' => 'public',
                'region' => 'Njombe', 'district' => null, 'zone' => 'shighland',
                'latitude' => -10.1066532, 'longitude' => 34.6923137,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Makuyuni DH', 'short_code' => 'MADH7', 'type' => 'public',
                'region' => 'Tanga', 'district' => 'Korogwe', 'zone' => 'coastal',
                'latitude' => -5.0168812, 'longitude' => 38.3285107,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Muhimbili National Hosp.', 'short_code' => 'MUNAH', 'type' => 'public',
                'region' => 'Dar Es Salaam', 'district' => null, 'zone' => 'coastal',
                'latitude' => -6.8056066, 'longitude' => 39.2729341,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Mt.Meru RRH', 'short_code' => 'MTRR', 'type' => 'public',
                'region' => 'Arusha', 'district' => null, 'zone' => 'northern',
                'latitude' => -3.3696827, 'longitude' => 36.6880794,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Mawenzi RRH', 'short_code' => 'MARR2', 'type' => 'public',
                'region' => 'Kilimanjaro', 'district' => null, 'zone' => 'northern',
                'latitude' => -3.0786534, 'longitude' => 37.4198556,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Lugalo Millitary Hosp', 'short_code' => 'LUMIH', 'type' => 'public',
                'region' => 'Dar Es Salaam', 'district' => null, 'zone' => 'coastal',
                'latitude' => -6.8160837, 'longitude' => 39.2803583,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Dodoma General/RRH', 'short_code' => 'DOGE', 'type' => 'public',
                'region' => 'Dodoma', 'district' => null, 'zone' => 'central',
                'latitude' => -6.1791181, 'longitude' => 35.7468174,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Singida RRH', 'short_code' => 'SIRR', 'type' => 'public',
                'region' => 'Singida', 'district' => null, 'zone' => 'central',
                'latitude' => -5.2902148, 'longitude' => 34.6367444,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Temeke RRH', 'short_code' => 'TERR', 'type' => 'public',
                'region' => 'Dar Es Salaam', 'district' => null, 'zone' => 'coastal',
                'latitude' => -6.8160837, 'longitude' => 39.2803583,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Chato RRH', 'short_code' => 'CHRR', 'type' => 'public',
                'region' => 'Geita', 'district' => null, 'zone' => 'lake',
                'latitude' => -3.1865265, 'longitude' => 32.0855702,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Iringa RRH', 'short_code' => 'IRRR', 'type' => 'public',
                'region' => 'Iringa', 'district' => null, 'zone' => 'shighland',
                'latitude' => -7.7742718, 'longitude' => 35.4826339,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
            [
                'name' => 'Kitete RRH', 'short_code' => 'KIRR', 'type' => 'public',
                'region' => 'Tabora', 'district' => null, 'zone' => 'central',
                'latitude' => -5.1913822, 'longitude' => 32.5080629,
                'machine_count' => 0, 'machines_operational' => 0,
            ],
        ];
        foreach ($newHospitals as $h) {
            Hospital::firstOrCreate(['short_code' => $h['short_code']], $h);
        }
    }
}
