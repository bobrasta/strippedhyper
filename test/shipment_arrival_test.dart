import 'dart:convert';

import 'package:bienhypermed/main.dart';
import 'package:bienhypermed/screens/procurement/shipment_detail_screen.dart';
import 'package:bienhypermed/services/api_client.dart';
import 'package:bienhypermed/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-11-02: storage & handling (Swissport etc.) at "Arrived at HQ", owed
// to the clearing agent; the agent's receipt is attached there, not before.
// The shipment below is a real API response (test data, local database).
const _arrived = '{"id": 542, "reference": "SHP-2026-0004", "direction": "import", "freight_mode": "air", "description": "Liaison XL reagents", "supplier_name": null, "po_number": null, "outbound_reason": null, "department_id": null, "department_name": null, "step": 10, "last_step": 10, "status_label": "Arrived at HQ", "flag": "done", "flag_reason": null, "docs_uploaded": 3, "docs_required": 3, "expected_arrival": null, "location_notes": null, "fee_status": "paid", "coa_required": false, "goods_category": "medical", "cost_bearer": "hypermed", "paid_by": null, "cost_note": null, "clearing_cost": 500000, "carrier_vendor_id": null, "carrier_name": null, "tmda": {"application_ref": "TMDA/1", "applied_at": null, "issued_at": "2026-11-02", "permit_uploaded": false, "sent_at": null, "sent_vendor_id": null, "sent_vendor_name": null}, "control_number": "CN-1", "clearing_fee": {"id": 119, "vendor_id": 228, "vendor_name": "ZZ Rangel Test", "description": "Clearing", "billed": 500000, "receipts_total": 0, "receipt_uploaded": false, "finance_verified": false, "status": "paid", "paid": true, "block_reason": null, "status_label": "Paid · receipt to follow", "receipt_after_payment": true, "receipt_follow_up": "Receipt to follow — attach the clearing agent\'s receipt."}, "handling_fee": {"id": 120, "vendor_id": 228, "vendor_name": "ZZ Rangel Test", "description": "Storage & handling (Swissport etc., paid by the agent for us) — SHP-2026-0004", "billed": 190000, "receipts_total": 190000, "receipt_uploaded": true, "finance_verified": false, "status": "pending_receipt", "paid": false, "block_reason": null, "status_label": "Awaiting Finance (payment request)", "receipt_after_payment": true, "receipt_follow_up": null}, "updated_at": "2026-11-02T09:50:41+00:00", "labels": ["Shipped", "In transit", "Arrived at port/airport", "TMDA permit applied", "TMDA permit issued", "Documents to clearing agent", "Assessment received", "Payment made", "Released by customs", "Arrived at HQ"], "port": null, "tender": null, "supplier_id": null, "purchase_order_id": null, "purchase_order": null, "department_manager": null, "notify_users": [], "documents": [{"type": "air_waybill", "label": "Air Waybill", "required": true, "for_records": false, "not_applicable": false, "file_name": "air_waybill.pdf", "uploaded_by": "Test sh-officer", "uploaded_at": "2026-11-02T09:50:41+00:00"}, {"type": "packing_list", "label": "Packing list", "required": true, "for_records": false, "not_applicable": false, "file_name": "packing_list.pdf", "uploaded_by": "Test sh-officer", "uploaded_at": "2026-11-02T09:50:41+00:00"}, {"type": "commercial_invoice", "label": "Commercial invoice", "required": true, "for_records": false, "not_applicable": false, "file_name": "commercial_invoice.pdf", "uploaded_by": "Test sh-officer", "uploaded_at": "2026-11-02T09:50:41+00:00"}, {"type": "coa", "label": "Certificate of Analysis", "required": false, "for_records": false, "not_applicable": true, "file_name": null, "uploaded_by": null, "uploaded_at": null}, {"type": "tmda_permit", "label": "TMDA permit", "required": false, "for_records": false, "not_applicable": false, "file_name": null, "uploaded_by": null, "uploaded_at": null}, {"type": "assessment_notice", "label": "Assessment notice", "required": false, "for_records": true, "not_applicable": false, "file_name": null, "uploaded_by": null, "uploaded_at": null}, {"type": "customs_release", "label": "Customs release order", "required": false, "for_records": true, "not_applicable": false, "file_name": null, "uploaded_by": null, "uploaded_at": null}, {"type": "clearing_other", "label": "Other clearing documents", "required": false, "for_records": true, "not_applicable": false, "file_name": null, "uploaded_by": null, "uploaded_at": null}, {"type": "storage_handling", "label": "Storage & handling (Swissport etc.)", "required": false, "for_records": true, "not_applicable": false, "file_name": "swissport.pdf", "uploaded_by": "Test sh-officer", "uploaded_at": "2026-11-02T09:50:41+00:00"}, {"type": "arrival_other", "label": "Other arrival documents", "required": false, "for_records": true, "not_applicable": false, "file_name": null, "uploaded_by": null, "uploaded_at": null}], "machines": [], "events": [{"from_step": null, "to_step": 1, "label": "Shipped", "note": null, "reason": null, "backward": false, "by": "Test sh-officer", "at": "2026-11-02T09:50:41+00:00"}, {"from_step": 10, "to_step": 10, "label": "Arrived at HQ", "note": "Storage & handling charges: TZS 185,000 owed to the clearing agent.", "reason": null, "backward": false, "by": "Test sh-officer", "at": "2026-11-02T09:50:41+00:00"}, {"from_step": 9, "to_step": 10, "label": "Arrived at HQ", "note": null, "reason": null, "backward": false, "by": "Test sh-officer", "at": "2026-11-02T09:50:41+00:00"}], "next_block_reason": null, "created_by_name": "Test sh-officer", "created_at": "2026-11-02T09:50:41+00:00", "can_manage": true, "can_approve_fee": false, "recipients": [{"name": "Admin User", "role": "admin"}, {"name": "Test CTO", "role": "cto"}]}';

Map<String, dynamic> _shipment({int? step}) {
  final s = Map<String, dynamic>.from(jsonDecode(_arrived) as Map);
  if (step != null) {
    s['step'] = step;
    s['flag'] = 'none';
    s['handling_fee'] = null;
    s['clearing_fee'] = {...(s['clearing_fee'] as Map), 'status': 'pending_receipt', 'paid': false, 'status_label': 'Awaiting Finance (payment request)'};
  }
  return s;
}

Map<String, dynamic>? _serving;

Future<List<String>> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (e) {
    if (e.exceptionAsString().contains('overflowed')) overflows.add(e.exceptionAsString().split('\n').first);
  };
  try {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.of(AppThemeMode.dark), home: const ShipmentDetailScreen(shipmentId: 1)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

void main() {
  setUpAll(() {
    try {
      authTokenNotifier = ValueNotifier<String?>('t');
    } catch (_) {/* set by another test */}
    ApiClient.instance.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      final data = o.path.endsWith('/options') ? {'vendors': <dynamic>[], 'doc_types': <String, dynamic>{}} : _serving;
      h.resolve(Response(requestOptions: o, statusCode: 200, data: {'data': data}));
    }));
  });

  testWidgets('arrived: storage & handling panel and the receipt button, no overflow', (tester) async {
    _serving = _shipment();
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      final overflows = await _pump(tester, size);
      expect(overflows, isEmpty, reason: '$size');
      expect(find.text('STORAGE & HANDLING · SWISSPORT ETC.', skipOffstage: false), findsOneWidget, reason: '$size');
      expect(find.text('TSh 190,000', skipOffstage: false), findsWidgets, reason: '$size');
      // The clearing fee is paid with its receipt to follow: attach it here.
      expect(find.text('Attach receipt', skipOffstage: false), findsWidgets, reason: '$size');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('before arrival: no receipt button, says where it goes', (tester) async {
    _serving = _shipment(step: 7);
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      final overflows = await _pump(tester, size);
      expect(overflows, isEmpty, reason: '$size');
      expect(find.text('Attached at "Arrived at HQ"', skipOffstage: false), findsOneWidget, reason: '$size');
      expect(find.text('Attach receipt', skipOffstage: false), findsNothing, reason: '$size');
      expect(find.text('STORAGE & HANDLING · SWISSPORT ETC.', skipOffstage: false), findsNothing, reason: '$size');
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('status dialog at Arrived at HQ asks for the charges and the Swissport papers', (tester) async {
    _serving = _shipment(step: 9);
    _serving!['clearing_fee'] = {...(_serving!['clearing_fee'] as Map), 'status': 'paid', 'paid': true};
    await _pump(tester, const Size(1440, 900));
    await tester.tap(find.text('Update status'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('STORAGE & HANDLING · SWISSPORT ETC.'), findsOneWidget);
    expect(find.text('Storage & handling (Swissport etc.)'), findsOneWidget);
    expect(find.text('ARRIVAL DOCUMENTS · FOR THE RECORD (OPTIONAL)'), findsOneWidget);
    expect(find.textContaining('receipt is attached here'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
