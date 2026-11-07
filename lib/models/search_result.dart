import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class SearchResult {
  final String type;
  final int id;
  final String title;
  final String? subtitle;
  /// type 'page': the menu screen to open.
  final String? pageKey;
  /// type 'page': the menu icon.
  final IconData? icon;

  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.pageKey,
    this.icon,
  });

  /// A menu screen, matched in the app from the menu labels.
  const SearchResult.page({required String key, required this.title, this.subtitle, this.icon})
      : type = 'page', id = 0, pageKey = key;

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
    type:     j['type'] as String,
    id:       (j['id'] as num).toInt(),
    title:    j['title'] as String? ?? '',
    subtitle: j['subtitle'] as String?,
  );
}

extension SearchResultTypeX on String {
  String get searchCategoryLabel => switch (this) {
    'page'                => 'Pages',
    'hospital'            => 'Hospitals & customers',
    'inventory_item'      => 'Inventory',
    'supplier'            => 'Suppliers',
    'purchase_order'      => 'Purchase orders',
    'requisition'         => 'Requisitions',
    'location'            => 'Locations',
    'staff'               => 'People',
    'sales_lead'          => 'Sales leads',
    'quotation'           => 'Quotations',
    'sales_order'         => 'Sales orders',
    'invoice'             => 'Invoices',
    'contact'             => 'Contacts',
    'vendor_bill'         => 'Vendor bills',
    'expense'             => 'Expenses',
    'shipment'            => 'Shipments',
    'tender'              => 'Tenders',
    'nest_tender'         => 'NeST tenders',
    'device_registration' => 'Device registrations',
    'meeting'             => 'Meetings',
    'letter'              => 'Letters',
    _                     => 'Other',
  };

  IconData get searchIcon => switch (this) {
    'page'                => Symbols.arrow_forward,
    'hospital'            => Symbols.local_hospital,
    'inventory_item'      => Symbols.inventory_2,
    'supplier'            => Symbols.local_shipping,
    'purchase_order'      => Symbols.shopping_bag,
    'requisition'         => Symbols.playlist_add_check,
    'location'            => Symbols.warehouse,
    'staff'               => Symbols.person,
    'sales_lead'          => Symbols.trending_up,
    'quotation'           => Symbols.request_quote,
    'sales_order'         => Symbols.shopping_cart,
    'invoice'             => Symbols.receipt_long,
    'contact'             => Symbols.contacts,
    'vendor_bill'         => Symbols.receipt,
    'expense'             => Symbols.payments,
    'shipment'            => Symbols.flight_land,
    'tender'              => Symbols.gavel,
    'nest_tender'         => Symbols.travel_explore,
    'device_registration' => Symbols.verified,
    'meeting'             => Symbols.groups,
    'letter'              => Symbols.mail,
    _                     => Symbols.search,
  };
}
