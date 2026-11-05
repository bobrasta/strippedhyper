import 'package:bienhypermed/models/per_diem_request.dart';
import 'package:bienhypermed/screens/self_service/travel_plan_viewer.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Section 15.4 travel-plan viewer: lays out a realistic 6-day plan at phone
// and desktop widths without overflow, in the template's order.
final _json = <String, dynamic>{
  'id': 41, 'user_id': 7, 'user_name': 'Yonah Leonard',
  'staff_name_snapshot': 'Yonah Leonard', 'staff_designation_snapshot': 'Biomedical Engineer',
  'payment_snapshot': {'provider': 'CRDB Bank', 'account_number': '********4821', 'account_name': 'YONAH LEONARD', 'masked': true},
  'service_ticket_id': 1574,
  'destination': 'Kagera & Kigoma', 'start_date': '2026-09-21', 'end_date': '2026-09-26', 'days_count': 6,
  'amount': 735000, 'purpose': 'Preventive maintenance of X-ray and ultrasound machines at regional hospitals',
  'status': 'pending_director',
  'team_lead_reviewer_name': 'Asha Mollel', 'team_lead_reviewed_at': '2026-09-18T07:12:00Z',
  'reviewer_name': 'Neville Temu', 'reviewed_at': '2026-09-18T10:40:00Z',
  'payment_initiated_by_name': 'Modester Kimaro', 'payment_initiated_at': '2026-09-19T08:00:00Z',
  'payment_method': 'bank_transfer', 'payment_reference': 'TRF-99812',
  'created_at': '2026-09-17T15:30:00Z',
  'lines': [
    for (var i = 0; i < 6; i++)
      {
        'seq_no': i + 1, 'date': '2026-09-${21 + i}', 'region': i < 3 ? 'Kagera' : 'Kigoma',
        'district': i < 3 ? 'Bukoba Municipal' : 'Kigoma Ujiji', 'site_name': i.isEven ? 'Bukoba Regional Referral Hospital' : 'Travel',
        'activity': i.isEven ? 'PM on Siemens Multix X-ray and GE Logiq ultrasound, user training' : 'Travel between sites',
        'labor_cost': 0, 'per_diem_cost': 80000, 'transport_fare': i.isEven ? 0 : 85000,
      },
  ],
  'revisions': [
    {'id': 1, 'edited_by_name': 'Neville Temu', 'editor_role': 'cto', 'status': 'applied', 'reason': 'Day 4 moved to Kigoma', 'created_at': '2026-09-18T10:30:00Z'},
  ],
  'adjustments': [
    {'id': 1, 'amount': -40000, 'reason': 'Returned one day of per diem', 'created_by_name': 'Modester Kimaro', 'created_at': '2026-09-27T09:00:00Z'},
  ],
  'was_edited': true,
  'summary': {
    'total_labor': 0, 'total_per_diem': 480000, 'total_transport': 255000, 'grand_total': 735000,
    'days_spent': 6, 'sites_visited': 3, 'avg_days_per_site': 2.0, 'avg_cost_per_site': 245000.0,
  },
  'signature_block': [
    {'stage': 'prepared', 'role_label': 'Prepared by', 'person_name': 'Yonah Leonard', 'acted_at_display': '17 Sep 2026', 'pending': false},
    {'stage': 'team_lead', 'role_label': 'Technical supervisor', 'person_name': 'Asha Mollel', 'acted_at_display': '18 Sep 2026', 'pending': false},
    {'stage': 'cto', 'role_label': 'CTO', 'person_name': 'Neville Temu', 'acted_at_display': '18 Sep 2026', 'pending': false},
    {'stage': 'director', 'role_label': 'Managing director', 'person_name': null, 'acted_at_display': null, 'pending': true},
  ],
};

void main() {
  setUpAll(() {
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': _json}));
    }));
  });

  for (final (label, size) in [('desktop', const Size(1440, 2400)), ('phone', const Size(390, 4200))]) {
    testWidgets('lays out without overflow on $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: TravelPlanViewerScreen(plan: PerDiemRequest.fromJson(_json)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Work Plan'), findsOneWidget);
      expect(find.text('Description of the Trip'), findsOneWidget);
      expect(find.textContaining('Monday, September 21, 2026'), findsOneWidget);
      expect(find.text('Grand total'), findsOneWidget);
      expect(find.text('TSh 735,000.00'), findsOneWidget);
      expect(find.textContaining('ACCOUNT NAME: YONAH LEONARD'), findsOneWidget);
      expect(find.textContaining('Managing director'), findsOneWidget);
      expect(find.text('Money is out — waiting'), findsOneWidget);
      expect(find.text('Payment initiated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
