class ItemStockLevel {
  final int    locationId;
  final String locationName;
  final double quantityOnHand;
  final double quantityReserved;
  final double quantityAvailable;

  const ItemStockLevel({
    required this.locationId,
    required this.locationName,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.quantityAvailable,
  });

  factory ItemStockLevel.fromJson(Map<String, dynamic> j) => ItemStockLevel(
    locationId:        (j['location_id'] as num).toInt(),
    locationName:      j['location_name'] as String? ?? '—',
    quantityOnHand:    (j['quantity_on_hand']   as num? ?? 0).toDouble(),
    quantityReserved:  (j['quantity_reserved']  as num? ?? 0).toDouble(),
    quantityAvailable: (j['quantity_available'] as num? ?? 0).toDouble(),
  );
}

class InventoryItem {
  final int    id;
  final String sku;
  final String name;
  final String? description;
  final int?   categoryId;
  final String category; // display name — 'Uncategorized' if none assigned
  final String unitOfMeasure;
  final double unitCost;
  /// The unit cost's currency (TZS unless set).
  final String costCurrency;
  final String currency;
  final int    stockQty;
  final int    reorderLevel;
  final bool   isLowStock;
  final String supplier;
  final bool   isActive;
  final List<ItemStockLevel> stockLevels;
  // v2 enriched fields
  final String? manufacturer;
  final String? barcode;
  final bool    hasCe;
  final bool    hasFda;
  final bool    hasTbs;
  final Map<String, dynamic> specifications;
  final int?    preferredSupplierId;
  final List<String> compatibleModels;
  final bool    createsMachineRecord;
  final int?    warrantyMonths;
  final bool    needsReview;

  /// Price to quote/invoice at: the selling price carried over from
  /// Clickhuduma (specifications "Selling price (TZS)") when present,
  /// otherwise the unit cost.
  double get sellingPrice {
    final v = specifications['Selling price (TZS)'];
    final parsed = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', ''));
    return (parsed != null && parsed > 0) ? parsed : unitCost;
  }

  const InventoryItem({
    required this.id,
    required this.sku,
    required this.name,
    this.description,
    this.categoryId,
    required this.category,
    required this.unitOfMeasure,
    required this.unitCost,
    this.costCurrency = 'TZS',
    this.currency = 'TZS',
    required this.stockQty,
    required this.reorderLevel,
    required this.isLowStock,
    this.supplier = '',
    this.isActive = true,
    this.stockLevels = const [],
    this.manufacturer,
    this.barcode,
    this.hasCe  = false,
    this.hasFda = false,
    this.hasTbs = false,
    this.specifications = const {},
    this.preferredSupplierId,
    this.compatibleModels = const [],
    this.createsMachineRecord = false,
    this.warrantyMonths,
    this.needsReview = false,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> j) {
    final categoryObj = j['category'];
    final categoryName = categoryObj is Map
        ? (categoryObj['name'] as String? ?? 'Uncategorized')
        : (categoryObj as String? ?? 'Uncategorized');

    return InventoryItem(
      id:            (j['id'] as num).toInt(),
      sku:           j['sku']             as String? ?? j['part_number'] as String? ?? '—',
      name:          j['name']            as String? ?? '—',
      description:   j['description']     as String?,
      categoryId:    j['category_id'] != null ? (j['category_id'] as num).toInt() : null,
      category:      categoryName,
      unitOfMeasure: j['unit_of_measure'] as String? ?? 'piece',
      unitCost:      (j['unit_cost']      as num? ?? 0).toDouble(),
      costCurrency:  (j['cost_currency']  as String? ?? 'TZS').toUpperCase(),
      currency:      j['currency']        as String? ?? 'TZS',
      stockQty:      (j['stock_qty']      as num? ?? 0).toInt(),
      reorderLevel:  (j['reorder_level']  as num? ?? 0).toInt(),
      isLowStock:    j['is_low_stock']    as bool? ?? false,
      supplier:      j['supplier']        as String? ?? '',
      isActive:      j['is_active']       as bool? ?? true,
      stockLevels: (j['stock_levels'] as List? ?? [])
          .map((e) => ItemStockLevel.fromJson(e as Map<String, dynamic>))
          .toList(),
      manufacturer:  j['manufacturer']    as String?,
      barcode:       j['barcode']         as String?,
      hasCe:         j['has_ce']          as bool? ?? false,
      hasFda:        j['has_fda']         as bool? ?? false,
      hasTbs:        j['has_tbs']         as bool? ?? false,
      specifications: j['specifications'] is Map
          ? Map<String, dynamic>.from(j['specifications'] as Map)
          : <String, dynamic>{},
      preferredSupplierId: j['preferred_supplier_id'] != null
          ? (j['preferred_supplier_id'] as num).toInt()
          : null,
      compatibleModels: (j['compatible_models'] as List? ?? [])
          .map((e) => e.toString()).toList(),
      createsMachineRecord: j['creates_machine_record'] as bool? ?? false,
      warrantyMonths: (j['warranty_months'] as num?)?.toInt(),
      needsReview: j['needs_review'] as bool? ?? false,
    );
  }

  bool get isOutOfStock => stockQty == 0;

  // Backward-compat aliases used by service ticket screen
  String get partNumber => sku;
}
