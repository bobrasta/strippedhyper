import 'package:flutter/material.dart';
import 'app_dropdown.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import '../../utils/format.dart';

/// Height of a single-line text field at standard density (14px text +
/// 12px vertical padding + border). Desktop's compact density makes the
/// text field 8px shorter, so boxes size with [fieldHeightOf], not this.
const double kFieldHeight = 45;

/// Shorter single-line fields (28px) for everything
/// under it — used for a page's filter row. The look is otherwise the same.
class DenseFields extends InheritedWidget {
  const DenseFields({super.key, required super.child});
  static const double height = 28;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DenseFields>() != null;

  @override
  bool updateShouldNotify(DenseFields old) => false;
}

/// The height a LabeledTextField actually draws at here — [kFieldHeight]
/// adjusted for the theme's visual density (37px on desktop), or the
/// [DenseFields] height inside one. Dropdown/date/static boxes use it so
/// they line up with text fields in the same row.
double fieldHeightOf(BuildContext context) => DenseFields.of(context)
    ? DenseFields.height
    : kFieldHeight + Theme.of(context).visualDensity.baseSizeAdjustment.dy;

/// The shared focus-reactive box every text-entry field sits in: a
/// recessed (`bg`-filled) rounded box with a `borderStrong` outline at rest
/// that turns the theme accent while focused, plus a solid translucent
/// accent "halo" ring around the outside (a zero-blur spread shadow, not a
/// soft glow). One place owns the FocusNode + listener so every field call
/// site just does `FieldFocusBox(builder: (focusNode) =>
/// TextField(focusNode: focusNode, ...))` instead of re-implementing focus
/// tracking per screen — a call site that doesn't pass the focusNode
/// through never gets the focused look.
class FieldFocusBox extends StatefulWidget {
  const FieldFocusBox({
    super.key,
    required this.builder,
    this.minHeight = 0,
    this.enabled = true,
    this.alignment,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.hasError = false,
    this.radius = 10,
    this.height,
    this.focusNode,
  });

  final Widget Function(BuildContext context, FocusNode focusNode) builder;
  // Optional caller-owned node, for fields whose focus something else also
  // drives (keyboard navigation, overlays). Otherwise the box owns one.
  final FocusNode? focusNode;
  final double minHeight;
  final bool enabled;
  final Alignment? alignment;
  final EdgeInsetsGeometry padding;
  // A validation error always wins the border color, focused or not — the
  // user needs to see what's wrong before the field looks "fine" again.
  final bool hasError;
  final double radius;
  // Fixed height — for multi-line fields using `expands: true`, which
  // need a bounded height from their parent.
  final double? height;

  @override
  State<FieldFocusBox> createState() => _FieldFocusBoxState();
}

class _FieldFocusBoxState extends State<FieldFocusBox> {
  FocusNode? _ownNode;
  FocusNode get _focusNode => widget.focusNode ?? (_ownNode ??= FocusNode());
  bool _focused = false;

  void _onFocus() {
    if (mounted && _focused != _focusNode.hasFocus) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
    _focused = _focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(FieldFocusBox old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    height: widget.height,
    constraints: widget.height == null ? BoxConstraints(minHeight: widget.minHeight) : null,
    decoration: fieldBoxDecoration(context, focused: _focused, hasError: widget.hasError, enabled: widget.enabled, radius: widget.radius),
    padding: widget.padding,
    alignment: widget.alignment,
    child: widget.builder(context, _focusNode),
  );
}

/// The Settings field box — recessed bg fill, borderStrong outline that
/// turns teal (coral on error) with a solid 20% halo while focused/open.
/// The ONE definition of the look: FieldFocusBox, DropdownFieldBox,
/// LabeledDateField and the combobox triggers all draw with this.
BoxDecoration fieldBoxDecoration(BuildContext context, {bool focused = false, bool hasError = false, bool enabled = true, bool active = false, double radius = 10}) {
  final pal = context.pal;
  final accent = hasError ? AppColors.coral : AppColors.teal;
  final lit = focused || active || hasError;
  return BoxDecoration(
    color: enabled ? pal.bg : pal.surface3,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: lit ? accent : pal.borderStrong, width: focused ? 1.6 : 1.2),
    boxShadow: [BoxShadow(
      color: focused ? accent.withValues(alpha: 0.20) : Colors.transparent,
      spreadRadius: focused ? 3 : 0,
      blurRadius: 0,
    )],
  );
}

/// The established boxed-field look used throughout the app (see
/// `_SettingsField` in settings_screen.dart, the inline fields in
/// `_RequestLeaveDialog`/`_PaymentModal`): sentence-case label above, a
/// `surface2` box with a `border` outline (teal + glow while focused), no
/// Material floating label. Extracted here as a shared, public widget so
/// every dialog looks and behaves the same instead of re-implementing it
/// (or drifting from it — see feedback_dont_relabel_reuse_screens for why
/// that matters).
class LabeledTextField extends StatefulWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.obscure = false,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.hasError = false,
    this.active = false,
    this.prefixIcon,
    this.suffix,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
    this.onTapOutside,
    this.textInputAction,
    this.textAlign = TextAlign.start,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  // Coral border (+ coral halo while focused) — wins over the focus accent.
  final bool hasError;
  // Filter-bar selects: teal outline while a filter is applied. Off by
  // default, so the field's own look is unchanged.
  final bool active;
  // Search boxes and similar: leading icon / trailing widget inside the field.
  final IconData? prefixIcon;
  final Widget? suffix;
  // Caller-owned node for fields whose focus also drives something else
  // (search overlays, combobox keyboard navigation).
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;
  final TapRegionCallback? onTapOutside;
  final TextInputAction? textInputAction;
  // Numeric columns (qty/price) right-align; the default look is unchanged.
  final TextAlign textAlign;

  @override
  State<LabeledTextField> createState() => _LabeledTextFieldState();
}

// The Settings text input — the user's own design (textfieldtest/main.dart,
// adapted to the app theme as Settings' _SettingsField): the TextField draws
// its own rounded outline (borderStrong, teal 1.6 when focused, coral on
// error) on a recessed bg fill, with a solid 20% accent halo ring around it
// while focused. Every text input in the app is this widget.
class _LabeledTextFieldState extends State<LabeledTextField> {
  FocusNode? _ownNode;
  FocusNode get _focusNode => widget.focusNode ?? (_ownNode ??= FocusNode());
  bool _focused = false;
  static const _radius = 10.0;

  void _onFocus() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
    _focused = _focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(LabeledTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color, [double width = 1.2]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.label.isNotEmpty) ...[
        Text(
          widget.label,
          style: AppTheme.bodySm.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: context.pal.textMute,
          ),
        ),
        const SizedBox(height: 6),
      ],
      AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              // Theme accent (the same token every other focus/active
              // state uses) at 20% — a solid ring, not a soft glow.
              color: _focused
                  ? (widget.hasError ? AppColors.coral : AppColors.teal).withValues(alpha: 0.20)
                  : Colors.transparent,
              spreadRadius: _focused ? 3 : 0,
              blurRadius: 0,
            ),
          ],
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          obscureText: widget.obscure,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textAlign: widget.textAlign,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
          onTapOutside: widget.onTapOutside,
          cursorColor: context.pal.text,
          cursorWidth: 1.5,
          style: AppTheme.bodySm.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: widget.enabled ? null : context.pal.textDim,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppTheme.bodySm.copyWith(
              fontSize: 14,
              color: context.pal.textDim,
            ),
            filled: true,
            // Recessed: the page background, a step darker than the card
            // the field sits on (lighter on light themes, same idea).
            fillColor: widget.enabled ? context.pal.bg : context.pal.surface3,
            isDense: true,
            // Inside DenseFields: 28px on every platform (desktop is
            // already compact), the same as the boxes.
            visualDensity: DenseFields.of(context) ? VisualDensity.compact : null,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: DenseFields.of(context) ? 7.5 : 12,
            ),
            prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 16, color: context.pal.textDim),
            prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
            suffixIcon: widget.suffix == null ? null : Padding(padding: const EdgeInsets.only(right: 12), child: widget.suffix),
            suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            border: _border(context.pal.borderStrong),
            enabledBorder: _border(widget.hasError ? AppColors.coral : widget.active ? AppColors.teal : context.pal.borderStrong),
            disabledBorder: _border(context.pal.borderStrong),
            focusedBorder: _border(widget.hasError ? AppColors.coral : AppColors.teal, 1.6),
          ),
        ),
      ),
    ],
  );
}

/// Search box — the Settings text input (LabeledTextField) with a search
/// icon. Use for every list/table filter. [width] null = fill the parent
/// (wrap it in Expanded inside a Row).
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.width,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? width;
  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  TextEditingController? _own;
  TextEditingController get _ctrl => widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = LabeledTextField(
      label: '',
      controller: _ctrl,
      hint: widget.hint,
      prefixIcon: Symbols.search,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

/// Compact Settings-look box for inline table/grid editors (qty, price and
/// similar cells) — same focus behaviour as every other field, sized down.
class CellField extends StatelessWidget {
  const CellField({
    super.key,
    required this.controller,
    this.hint,
    this.textAlign = TextAlign.center,
    this.keyboardType,
    this.onChanged,
    this.mono = false,
    this.suffixText,
  });

  final TextEditingController controller;
  final String? hint;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool mono;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    final base = mono ? AppTheme.monoSm.copyWith(fontSize: 12.5) : AppTheme.fieldText.copyWith(fontSize: 13);
    return FieldFocusBox(
      radius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      builder: (context, focusNode) => TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: textAlign,
        keyboardType: keyboardType,
        onChanged: onChanged,
        cursorColor: context.pal.text,
        cursorWidth: 1.5,
        style: base.copyWith(color: context.pal.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.fieldHint.copyWith(fontSize: 13),
          suffixText: suffixText,
          suffixStyle: AppTheme.bodySub.copyWith(fontSize: 11.5),
          filled: false, border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// The established boxed-dropdown look (see `_HDropdown` in
/// settings_screen.dart). Generic over [T] — the app's original per-file
/// copies were String-only, which is why new dialogs kept reaching for
/// Material's default `DropdownButtonFormField` instead (it needed int
/// keys) and drifted off-style. `isExpanded: true` here also closes off
/// the overflow class of bug that caused (a dropdown with unconstrained
/// intrinsic width inside a Row/Expanded).
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.displayBuilder,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) displayBuilder;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    DropdownFieldBox<T>(
      value: value,
      enabled: enabled,
      items: items.map((v) => DropdownMenuItem(value: v, child: Text(displayBuilder(v), overflow: TextOverflow.ellipsis))).toList(),
      // DropdownButton only passes null when the picked item's value IS
      // null, so forward it as-is — dropping it made a nullable option
      // like "None" impossible to re-select.
      onChanged: (v) => onChanged?.call(v as T),
    ),
  ]);
}

/// The Settings dropdown box on its own (no label) — the single place the
/// app's dropdown field is drawn. LabeledDropdown uses it; use it directly
/// for filter bars or wherever items are already DropdownMenuItems.
///
/// Every select is typeable (user, 2026-10-15): it's the Settings text
/// input showing the picked option; click it and the whole list opens,
/// type and the list narrows, then pick (click, or Enter for the top
/// match). Each item's label is its Text child.
class DropdownFieldBox<T> extends StatelessWidget {
  const DropdownFieldBox({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.enabled = true,
    this.active = false,
    this.width,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool enabled;
  // Filter dropdowns: teal border while a filter is applied.
  final bool active;
  final double? width;

  static String _labelOf(DropdownMenuItem item) {
    final c = item.child;
    if (c is Text) return c.data ?? c.textSpan?.toPlainText() ?? '';
    if (c is RichText) return c.text.toPlainText();
    return item.value?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final usable = [for (final i in items) if (i.enabled) i];
    final options = [for (final i in usable) AppSelectItem<T?>(value: i.value, label: _labelOf(i))];
    final current = options.where((o) => o.value == value);
    return AppSearchableSelectField<T?>(
      dropdown: true,
      width: width,
      hint: hint ?? 'Select…',
      selectedLabel: current.isEmpty ? null : current.first.label,
      items: options,
      isSelected: (v) => v == value,
      enabled: enabled && onChanged != null,
      active: active,
      onSelected: (o) {
        if (o == null) return;
        usable.firstWhere((i) => i.value == o.value).onTap?.call();
        onChanged?.call(o.value);
      },
    );
  }
}

/// The established boxed date-picker field (see `_DateField` in
/// my_leave_screen.dart).
class LabeledDateField extends StatelessWidget {
  const LabeledDateField({super.key, required this.label, required this.date, required this.onTap, this.placeholder = 'Select date', this.onClear});
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final String placeholder;
  // Optional — shows a clear (×) button while a date is set, for fields
  // where "no date" is a valid answer.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    GestureDetector(
      onTap: onTap,
      child: Container(
        height: fieldHeightOf(context),
        decoration: fieldBoxDecoration(context),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Expanded(child: Text(date != null ? formatDate(date!) : placeholder,
              style: AppTheme.fieldText.copyWith(color: date != null ? context.pal.text : context.pal.textDim))),
          if (date != null && onClear != null) ...[
            GestureDetector(onTap: onClear, child: Icon(Symbols.close, size: 14, color: context.pal.textDim)),
            const SizedBox(width: 8),
          ],
          Icon(Symbols.calendar_month, size: 15, color: context.pal.textDim),
        ]),
      ),
    ),
  ]);
}

/// A disabled-looking read-only row, for fields shown but not editable by
/// the current user (e.g. Position, gated to Director/Admin).
class LabeledStaticField extends StatelessWidget {
  const LabeledStaticField({super.key, required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTheme.fieldLabel),
    const SizedBox(height: 6),
    Container(
      height: fieldHeightOf(context),
      alignment: Alignment.centerLeft,
      decoration: fieldBoxDecoration(context, enabled: false),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Expanded(child: Text(value, style: AppTheme.fieldText.copyWith(color: context.pal.textDim), overflow: TextOverflow.ellipsis)),
        if (hint != null) Icon(Symbols.lock, size: 13, color: context.pal.textDim),
      ]),
    ),
    if (hint != null) Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(hint!, style: AppTheme.bodySub.copyWith(fontSize: 10.5)),
    ),
  ]);
}
