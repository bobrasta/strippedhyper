import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/models/nest_tender.dart';
import 'package:bienhypermed/screens/procurement/nest_tender_detail_screen.dart';
import 'package:bienhypermed/screens/procurement/nest_tenders_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/services/nest_service.dart';
import 'package:bienhypermed/theme/app_colors.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:bienhypermed/widgets/procurement/nest_widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// NeST tender tracker: the tender row, the list filters (which query they
// send), and every tab + the detail page laid out with realistic data at
// phone and desktop widths. The data below is made up in NeST's shape.

String _eat(DateTime d) {
  final e = d.toUtc().add(const Duration(hours: 3));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${e.year}-${two(e.month)}-${two(e.day)}T${two(e.hour)}:${two(e.minute)}:00+03:00';
}

Map<String, dynamic> _tender(int id, {int days = 10, List<String> tags = const ['DEVICES'], bool addendum = false,
    String pipeline = 'new', String relevance = 'relevant', bool detail = false}) => {
  'id': id,
  'entity_uuid': '00000000-0000-0000-0000-00000000000$id',
  'entity_number': 'TR129/2026/2027/G/$id',
  'reference_number': 'TR129/2026/2027/G/$id-S001',
  'entity_type': 'TENDER',
  'description': 'Procurement of Ophthalmology Medical Equipment and Laboratory Analysers for the New Wing, Lot $id',
  'sub_category_acronym': 'HEALTH_SECTOR_GOODS',
  'sub_category_name': 'Health Sector Goods',
  'procurement_category': 'G',
  'procurement_category_name': 'Goods',
  'procuring_entity_name': 'MUHIMBILI NATIONAL HOSPITAL - MLOGANZILA CAMPUS',
  'procuring_entity_uuid': '11111111-1111-1111-1111-111111111111',
  'financial_year': '2026/2027',
  'lot_count': 6,
  'has_addendum': addendum,
  'invitation_at': _eat(DateTime.now().subtract(const Duration(days: 5))),
  'closing_at': _eat(DateTime.now().add(Duration(days: days, hours: 2))),
  'closing_in_days': days,
  'is_open': days >= 0,
  'is_closing_soon': days >= 0 && days <= 3,
  'relevance_score': 27,
  'is_relevant': relevance == 'relevant',
  'relevance': relevance,
  'tags': tags,
  'triage_status': pipeline == 'bidding' ? 'reviewing' : pipeline,
  'pipeline_status': pipeline,
  'assigned_to': {'id': 7, 'name': 'Patrick Umbe'},
  'tender': pipeline == 'bidding' ? {'id': 3, 'status': 'preparing_bid', 'tender_number': 'TR129'} : null,
  'first_seen_at': _eat(DateTime.now().subtract(const Duration(days: 4))),
  'nest_url': 'https://nest.go.tz',
  if (detail) ...{
    'eligible_types': ['COMPANY_LOCAL', 'COMPANY_FOREIGN', 'MANUFACTURER_LOCAL'],
    'matched_keywords': [
      {'term': 'medical equipment', 'type': 'keyword', 'tag': 'DEVICES', 'weight': 10, 'counted': true},
      {'term': 'ophthalmology', 'type': 'keyword', 'tag': 'DEVICES', 'weight': 10, 'counted': true},
      {'term': 'HEALTH_SECTOR', 'type': 'health_subcategory', 'weight': 5, 'counted': true},
      {'term': 'HOSPITAL', 'type': 'entity_hint', 'weight': 2, 'counted': true},
      {'term': 'medicines', 'type': 'exclude', 'weight': -20, 'counted': false, 'note': 'ignored: tender also has devices or reagents'},
    ],
    'notes': 'Lots 2 and 5 match our Zeiss range.',
    'changes': [
      {'field': 'closing_at', 'old_value': _eat(DateTime.now()), 'new_value': _eat(DateTime.now().add(const Duration(days: 7))), 'detected_at': _eat(DateTime.now())},
      {'field': 'has_addendum', 'old_value': 'no', 'new_value': 'yes', 'detected_at': _eat(DateTime.now())},
    ],
  },
};

final _rows = [
  _tender(1, days: 2, tags: ['DEVICES', 'REAGENTS'], addendum: true),
  _tender(2, days: 6, tags: ['REAGENTS'], pipeline: 'reviewing'),
  _tender(3, days: 12, tags: ['DEVICES', 'SERVICE'], pipeline: 'bidding'),
  _tender(4, days: 20, tags: ['CONSUMABLES'], relevance: 'maybe'),
];

final _sync = {'last_run': {'status': 'ok', 'records': 241}, 'last_ok_at': _eat(DateTime.now()), 'runs_today': 1, 'max_runs_per_day': 3, 'total_stored': 235};

dynamic _respond(RequestOptions o) {
  final p = o.path;
  if (p.endsWith('/nest/dashboard')) {
    return {'data': {
      'open_relevant': 34, 'open_maybe': 3, 'closing_3_days': 4, 'closing_7_days': 11, 'new_since_last_visit': 6, 'my_open': 2,
      'by_tag': {'DEVICES': 25, 'REAGENTS': 6, 'CONSUMABLES': 1, 'SERVICE': 5},
      'by_pipeline': {'new': 28, 'reviewing': 4, 'bidding': 2, 'submitted': 1, 'won': 0, 'lost': 1, 'skipped': 3},
      'top_entities': [
        {'procuring_entity_uuid': '11111111-1111-1111-1111-111111111111', 'procuring_entity_name': 'MUHIMBILI NATIONAL HOSPITAL - MLOGANZILA CAMPUS', 'relevant_count': 9},
        {'procuring_entity_uuid': '22222222-2222-2222-2222-222222222222', 'procuring_entity_name': 'BANK OF TANZANIA - DODOMA HEAD OFFICE', 'relevant_count': 3},
      ],
      'sync': _sync, 'can_manage': true,
    }};
  }
  if (p.endsWith('/documents')) {
    return {'data': {
      'documents': [
        {'id': 'faa09cdf-cd5f-47e6-9337-61160728b7a9', 'title': 'Tender document', 'kind': 'tender_document',
         'note': 'NeST re-issues this after an addendum — re-fetch to get the latest'},
        {'id': 'faa09cdf-cd5f-47e6-9337-61160728b7a8', 'title': 'Clarification: MRI compatible suction — reply attachment', 'kind': 'clarification'},
        {'id': 'faa09cdf-cd5f-47e6-9337-61160728b7a7', 'title': 'Technical specifications and drawings for the new theatre wing (Lots 1–6)', 'kind': 'requisition'},
      ],
      'clarifications': [
        {'title': 'MRI COMPATIBLE SUCTION', 'question': 'Is a wall-mounted MRI-conditional suction unit acceptable for Lot 3, or must it be mobile?', 'from': 'tenderer',
         'at': _eat(DateTime.now()), 'replies': [{'from': 'procuring_entity', 'text': 'Wall-mounted is acceptable. See the attached drawing.', 'at': _eat(DateTime.now())}]},
        {'title': 'Delivery period', 'question': 'Can delivery be split?', 'from': 'tenderer', 'at': null, 'replies': []},
      ],
      'addendum': {'status': 'APPROVED', 'changes': [{'area': 'Update Tender Submission Deadline', 'reason': 'Extension requested by several tenderers to complete technical compliance sheets.'}]},
      'pre_bid': null, 'errors': [], 'fetched_at': _eat(DateTime.now()),
    }};
  }
  if (RegExp(r'/nest/tenders/\d+$').hasMatch(p)) {
    return {'data': _tender(1, days: 2, tags: ['DEVICES', 'REAGENTS'], addendum: true, detail: true), 'can_manage': true,
        'document': {'available': true, 'cached': false}};
  }
  if (p.endsWith('/nest/tenders')) {
    return {'data': _rows, 'meta': {'current_page': 1, 'last_page': 1, 'total': _rows.length}, 'can_manage': true};
  }
  if (p.endsWith('/nest/procuring-entities')) {
    return {'data': [
      {'uuid': '11111111-1111-1111-1111-111111111111', 'name': 'MUHIMBILI NATIONAL HOSPITAL - MLOGANZILA CAMPUS', 'total_count': 14, 'relevant_count': 9, 'last_tender_at': _eat(DateTime.now())},
      {'uuid': '33333333-3333-3333-3333-333333333333', 'name': 'TANROADS - TANGA REGIONAL OFFICE', 'total_count': 7, 'relevant_count': 0, 'last_tender_at': _eat(DateTime.now())},
    ]};
  }
  if (p.endsWith('/nest/settings')) {
    return {'data': {
      'notifications': {'new_relevant': true, 'changes': true, 'digest': false}, 'threshold': 10, 'maybe_min': 5,
      'nest_login': {'username': 'tenders@hypermed.co.tz', 'has_password': true, 'server_ready': true, 'last_ok_at': null, 'last_error': 'NeST rejected the login: Bad credentials'},
      'sync': _sync, 'can_manage': true,
    }};
  }
  if (p.endsWith('/nest/relevance-rules')) {
    var id = 0;
    Map<String, dynamic> r(String type, String? tag, String term, int w, [bool active = true]) =>
        {'id': ++id, 'type': type, 'tag': tag, 'term': term, 'weight': w, 'active': active};
    return {'data': {'rules': [
      r('keyword', 'DEVICES', 'medical equipment', 10), r('keyword', 'DEVICES', 'maintenance of medical equipment', 10),
      r('keyword', 'DEVICES', 'ultrasound', 10), r('keyword', 'REAGENTS', 'haematology reagents', 10),
      r('keyword', 'CONSUMABLES', 'gloves', 6), r('keyword', 'SERVICE', 'calibration', 6, false),
      r('exclude', null, 'building materials', -20), r('health_subcategory', null, 'HEALTH_SECTOR', 5),
      r('entity_hint', null, 'BLOOD TRANSFUSION', 2),
    ], 'threshold': 10, 'maybe_min': 5, 'can_manage': true}};
  }
  return {'data': <dynamic>[]};
}

Future<List<String>> _layoutErrors(WidgetTester tester, Widget app, {Future<void> Function()? then}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (e) {
    final at = RegExp(r'lib/[A-Za-z0-9_/]+\.dart:\d+').firstMatch(e.toString())?.group(0) ?? '';
    errors.add('${e.exceptionAsString().split('\n').first} $at');
  };
  try {
    await tester.pumpWidget(app);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    if (then != null) await then();
  } finally {
    FlutterError.onError = previous;
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  return errors;
}

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: Scaffold(body: child));

void main() {
  setUpAll(() {
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200, data: _respond(o)));
    }));
  });

  group('NestTenderRow', () {
    for (final wide in [false, true]) {
      testWidgets('shows the tender (${wide ? 'table row' : 'phone card'})', (tester) async {
        tester.view.physicalSize = Size(wide ? 1440 : 390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var tapped = false;
        final t = NestTender.fromJson(_rows[0]);
        await tester.pumpWidget(_wrap(SingleChildScrollView(child: NestTenderRow(tender: t, wide: wide, onTap: () => tapped = true))));

        expect(find.textContaining('Ophthalmology Medical Equipment'), findsOneWidget);
        expect(find.textContaining('TR129/2026/2027/G/1-S001'), findsOneWidget);
        expect(find.textContaining('6 lots'), findsOneWidget);
        expect(find.text('Devices'), findsOneWidget);
        expect(find.text('Reagents'), findsOneWidget);
        expect(find.text('Addendum'), findsOneWidget);
        expect(find.text('New'), findsOneWidget);
        expect(find.text('closes in 2 days'), findsOneWidget);
        // Red within 3 days.
        final countdown = tester.widget<Text>(find.byKey(const ValueKey('countdown')));
        expect(countdown.style?.color, AppColors.coral);

        await tester.tap(find.textContaining('Ophthalmology Medical Equipment'));
        expect(tapped, isTrue);
      });
    }

    testWidgets('a far closing date is not red', (tester) async {
      final t = NestTender.fromJson(_rows[2]);
      await tester.pumpWidget(_wrap(NestTenderRow(tender: t, onTap: () {})));
      final countdown = tester.widget<Text>(find.byKey(const ValueKey('countdown')));
      expect(countdown.style?.color, isNot(AppColors.coral));
      expect(find.text('Bidding'), findsOneWidget);
    });
  });

  group('NestTenderList filters', () {
    Future<List<Map<String, dynamic>>> pumpList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final queries = <Map<String, dynamic>>[];
      await tester.pumpWidget(_wrap(_Harness(onQuery: queries.add)));
      await tester.pump();
      return queries;
    }

    testWidgets('defaults to open relevant tenders, soonest closing first', (tester) async {
      final q = await pumpList(tester);
      expect(q.last['open'], 1);
      expect(q.last['relevance'], 'relevant');
      expect(q.last['sort'], 'closing');
      expect(q.last.containsKey('tags[]'), isFalse);
      expect(find.text('4 tenders'), findsOneWidget);
    });

    testWidgets('chips change the query', (tester) async {
      final q = await pumpList(tester);

      await tester.tap(find.widgetWithText(NestToggleChip, 'Devices'));
      await tester.pump();
      expect(q.last['tags[]'], ['DEVICES']);

      await tester.tap(find.widgetWithText(NestToggleChip, 'Reagents'));
      await tester.pump();
      expect((q.last['tags[]'] as List).toSet(), {'DEVICES', 'REAGENTS'});

      await tester.tap(find.widgetWithText(NestToggleChip, 'Closing soon'));
      await tester.pump();
      expect(q.last['closing_within'], 3);

      await tester.tap(find.widgetWithText(NestToggleChip, 'My tenders'));
      await tester.pump();
      expect(q.last['assigned_to'], 'me');

      await tester.tap(find.widgetWithText(NestToggleChip, 'Open'));
      await tester.pump();
      expect(q.last.containsKey('open'), isFalse);

      await tester.tap(find.text('Maybe').first); // the segment, above the rows
      await tester.pump();
      expect(q.last['relevance'], 'maybe');
    });

    testWidgets('search is debounced into q', (tester) async {
      final q = await pumpList(tester);
      await tester.enterText(find.byType(EditableText).first, 'muhimbili');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(q.last['q'], 'muhimbili');
    });
  });

  group('layout with realistic data', () {
    for (final width in [390.0, 1440.0]) {
      testWidgets('every tab fits at ${width.toInt()} px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        userIdNotifier.value = 7;
        final errors = await _layoutErrors(tester, _wrap(const NestTendersScreen()), then: () async {
          for (final tab in ['Tenders', 'Buyers', 'Settings']) {
            await tester.tap(find.text(tab).first);
            for (var i = 0; i < 3; i++) {
              await tester.pump(const Duration(milliseconds: 300));
            }
          }
        });
        expect(errors, isEmpty);
      });

      testWidgets('detail fits at ${width.toInt()} px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        userIdNotifier.value = 7;
        final errors = await _layoutErrors(tester,
            MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: const NestTenderDetailScreen(tenderId: 1)),
            then: () async {
              expect(find.text('closes in 2 days'), findsWidgets);
              expect(find.text('Start bid'), findsOneWidget);
              // Scroll to the end so every panel is built (and laid out).
              var sawRules = false, sawHistory = false, sawDocs = false, sawClar = false, sawAddendum = false;
              for (var i = 0; i < 10; i++) {
                sawRules |= find.textContaining('medical equipment +10').evaluate().isNotEmpty;
                sawHistory |= find.textContaining('Closing date moved').evaluate().isNotEmpty;
                sawDocs |= find.textContaining('DOCUMENTS · 3').evaluate().isNotEmpty && find.text('Tender document').evaluate().isNotEmpty;
                sawClar |= find.text('Wall-mounted is acceptable. See the attached drawing.').evaluate().isNotEmpty;
                sawAddendum |= find.text('Update Tender Submission Deadline').evaluate().isNotEmpty;
                await tester.drag(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first, const Offset(0, -400));
                await tester.pump(const Duration(milliseconds: 200));
              }
              expect(sawRules, isTrue, reason: 'matched rules shown');
              expect(sawHistory, isTrue, reason: 'change history shown');
              expect(sawDocs, isTrue, reason: 'documents listed');
              expect(sawClar, isTrue, reason: 'clarification answer shown');
              expect(sawAddendum, isTrue, reason: 'addendum shown');
            });
        expect(errors, isEmpty);
      });
    }
  });
}

/// Holds the filter like NestTendersScreen does and records each query.
class _Harness extends StatefulWidget {
  const _Harness({required this.onQuery});
  final ValueChanged<Map<String, dynamic>> onQuery;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  NestFilter _f = const NestFilter();
  @override
  Widget build(BuildContext context) => NestTenderList(
    filter: _f,
    onFilterChanged: (f) => setState(() => _f = f),
    onOpen: (_) {},
    service: (f, page) async {
      widget.onQuery(f.toQuery(page: page));
      return NestPage(rows: [for (final r in _rows) NestTender.fromJson(r)], page: 1, lastPage: 1, total: _rows.length, canManage: true);
    },
  );
}
