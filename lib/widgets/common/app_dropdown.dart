import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import 'package:material_symbols_icons/symbols.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_palette.dart';
import 'labeled_field.dart';

// Case/whitespace/hyphen/punctuation-insensitive match key — "xray",
// "x-ray" and "X Ray" all normalize the same way. Used as the default
// client-side filter and by the model-name combobox specifically (see
// hypermed_claude_code_prompt.md Section 4). Deliberately not fuzzy.
String normalizeForSearch(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// One option in an [AppSelectField], [AppMultiSelectField] or
/// [AppSearchableSelectField].
class AppSelectItem<T> {
  const AppSelectItem({required this.value, required this.label, this.leading, this.trailing, this.subtitle});
  final T value;
  final String label;
  /// A second, smaller line under the label (e.g. price and lot) —
  /// [AppSearchableSelectField] only; typing matches it too.
  final String? subtitle;
  final Widget? leading;
  /// Extra info shown at the row's end (e.g. a stock-count badge) —
  /// [AppSearchableSelectField] only; ignored elsewhere.
  final Widget? trailing;
}

// Every select in the app is typeable: the field is the Settings text input
// (LabeledTextField); clicking it opens the list, typing narrows the list,
// arrows/Enter or a click pick. The pieces below are shared by the single-,
// multi- and searchable variants so they read as one component family.

// The floating list under the field — or above it when there's no room
// below (a field low in a dialog, or the phone keyboard is up). Placement is
// worked out on every build, so it re-flips when the keyboard opens.
Widget _floatingPanel({
  required BuildContext ctx,
  required BuildContext fieldContext,
  required LayerLink link,
  required GlobalKey fieldKey,
  required VoidCallback onDismiss,
  required Widget child,
}) {
  final field = fieldKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(fieldContext)?.context.findRenderObject() as RenderBox?;
  var width = 220.0, below = 320.0, above = 0.0;
  if (field != null && field.hasSize && overlay != null && overlay.hasSize) {
    width = field.size.width;
    final top = field.localToGlobal(Offset.zero, ancestor: overlay).dy;
    final overlayTop = overlay.localToGlobal(Offset.zero).dy;
    final visibleBottom = math.min(overlay.size.height,
        MediaQuery.sizeOf(ctx).height - MediaQuery.viewInsetsOf(ctx).bottom - overlayTop);
    below = visibleBottom - top - field.size.height - 12;
    above = top - 12;
  }
  final up = below < 220 && above > below;
  final maxHeight = (up ? above : below).clamp(96.0, 320.0);
  return Stack(children: [
    // Full-screen tap-catcher so tapping outside the panel closes it.
    Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onDismiss)),
    CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: up ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: up ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(0, up ? -6 : 6),
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: ctx.pal.surface1,
              border: Border.all(color: ctx.pal.borderStrong),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    ),
  ]);
}

Widget _panelRow(BuildContext context, {required Widget leading, required Widget label, required bool selected, required VoidCallback onTap, Widget? trailing, Key? key}) {
  return _HoverRow(key: key, onTap: onTap, selected: selected, child: Row(children: [
    leading,
    const SizedBox(width: 9),
    Expanded(child: label),
    if (trailing != null) ...[const SizedBox(width: 8), trailing],
  ]));
}

Widget _panelMessage(BuildContext ctx, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
  child: Text(text, style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: ctx.pal.textDim)),
);

Widget _chevron(BuildContext context, bool open) => AnimatedRotation(
  turns: open ? 0.5 : 0,
  duration: const Duration(milliseconds: 140),
  child: Icon(Symbols.expand_more, size: 17, color: context.pal.textDim),
);

class _HoverRow extends StatefulWidget {
  const _HoverRow({super.key, required this.child, required this.selected, required this.onTap});
  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        color: widget.selected
            ? AppColors.blue.withValues(alpha: 0.10)
            : (_hovered ? context.pal.surface2 : Colors.transparent),
        child: widget.child,
      ),
    ),
  );
}

/// Single-select — the field shows the picked option; click it and the
/// whole list opens, type and the list narrows, pick to close. Same
/// component as [DropdownFieldBox]; this one takes [AppSelectItem]s.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key, this.label, required this.value, required this.items,
    required this.onChanged, this.hint = 'Select…', this.width,
  });
  final String? label;
  final T? value;
  final List<AppSelectItem<T>> items;
  final ValueChanged<T> onChanged;
  final String hint;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((i) => i.value == value);
    return AppSearchableSelectField<T>(
      dropdown: true,
      label: label,
      width: width,
      hint: hint,
      selectedLabel: selected.isNotEmpty ? selected.first.label : null,
      items: items,
      isSelected: (v) => v == value,
      onSelected: (i) { if (i != null) onChanged(i.value); },
    );
  }
}

/// Multi-select — the field shows "N selected" (+ a count badge); click it
/// and a checklist opens that stays open while toggling, typing narrows it.
class AppMultiSelectField<T> extends StatefulWidget {
  const AppMultiSelectField({
    super.key, this.label, required this.values, required this.items,
    required this.onChanged, this.hint = 'Select…', this.width,
  });
  final String? label;
  final Set<T> values;
  final List<AppSelectItem<T>> items;
  final ValueChanged<Set<T>> onChanged;
  final String hint;
  final double? width;

  @override
  State<AppMultiSelectField<T>> createState() => _AppMultiSelectFieldState<T>();
}

class _AppMultiSelectFieldState<T> extends State<AppMultiSelectField<T>> {
  final _link = LayerLink();
  final _fieldKey = GlobalKey();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _entry;
  String _query = '';
  // Local copy, so the open checklist reflects a toggle straight away
  // instead of waiting for the parent's rebuild.
  late Set<T> _values = widget.values;

  String get _summary => _values.isEmpty
      ? ''
      : _values.length == 1
          ? widget.items.firstWhere((i) => _values.contains(i.value), orElse: () => widget.items.first).label.trim()
          : '${_values.length} selected';

  @override
  void initState() {
    super.initState();
    _controller.text = _summary;
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppMultiSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _values = widget.values;
    if (!_focusNode.hasFocus) _controller.text = _summary;
  }

  @override
  void dispose() {
    _entry?.remove();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.clear();
      _query = '';
      _entry ??= OverlayEntry(builder: (ctx) => _floatingPanel(
        ctx: ctx, fieldContext: context, link: _link, fieldKey: _fieldKey,
        onDismiss: () => _focusNode.unfocus(),
        child: _panel(ctx),
      ));
      Overlay.of(context).insert(_entry!);
    } else {
      _controller.text = _summary;
      _entry?.remove();
      _entry = null;
    }
    if (mounted) setState(() {});
  }

  void _toggle(T value) {
    final next = Set<T>.from(_values);
    next.contains(value) ? next.remove(value) : next.add(value);
    _values = next;
    widget.onChanged(next);
    _entry?.markNeedsBuild();
    setState(() {});
  }

  Widget _panel(BuildContext ctx) {
    final key = normalizeForSearch(_query);
    final shown = key.isEmpty ? widget.items : widget.items.where((i) => normalizeForSearch(i.label).contains(key)).toList();
    if (shown.isEmpty) return _panelMessage(ctx, 'No results');
    return ListView(
      shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final i in shown)
          _panelRow(
            ctx,
            leading: SizedBox(width: 18, height: 18, child: Checkbox(
              value: _values.contains(i.value),
              onChanged: (_) => _toggle(i.value),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: ctx.pal.textDim),
              activeColor: AppColors.blue,
            )),
            label: Text(i.label, style: AppTheme.bodySm.copyWith(fontSize: 12.5)),
            selected: false,
            onTap: () => _toggle(i.value),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) ...[
        Text(widget.label!, style: AppTheme.fieldLabel),
        const SizedBox(height: 6),
      ],
      CompositedTransformTarget(link: _link, child: SizedBox(key: _fieldKey, width: widget.width, child: Focus(
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            _focusNode.unfocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LabeledTextField(
          label: '',
          controller: _controller,
          focusNode: _focusNode,
          hint: focused ? 'Type to filter…' : widget.hint,
          active: _values.isNotEmpty,
          onChanged: (t) { _query = t; _entry?.markNeedsBuild(); },
          // The checklist lives in a separate Overlay — see the note on
          // AppSearchableSelectField's onTapOutside below.
          onTapOutside: (_) {},
          suffix: GestureDetector(
            onTap: () => focused ? _focusNode.unfocus() : _focusNode.requestFocus(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_values.length > 1) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(999)),
                  child: Text('${_values.length}', style: AppTheme.monoXs.copyWith(fontSize: 10, color: Colors.white, height: 1.4)),
                ),
                const SizedBox(width: 6),
              ],
              _chevron(context, focused),
            ]),
          ),
        ),
      ))),
    ]);
  }
}

/// Searchable select (combobox) — click and type, options filter live, pick
/// one; selected value shown with a clear (x) button. Two modes:
/// - Client-side: pass [items]; filtered locally by [normalizeForSearch].
/// - Server-side: pass [asyncSearch]; debounced, shows loading/"no results".
/// Never both empty — one of the two must be provided.
/// Per hypermed_claude_code_prompt.md Section 4: use this everywhere a user
/// picks from a long or growing list (clients, staff, products…).
///
/// [dropdown] is the plain-select variant every [DropdownFieldBox],
/// [LabeledDropdown] and [AppSelectField] draws: a chevron instead of the
/// search icon, no clear (x), the whole list on open with the current
/// option marked, and the top match pre-highlighted while typing so Enter
/// picks it.
class AppSearchableSelectField<T> extends StatefulWidget {
  const AppSearchableSelectField({
    super.key,
    this.label,
    this.selectedLabel,
    this.items,
    this.asyncSearch,
    required this.onSelected,
    this.hint = 'Type to search…',
    this.width,
    this.createNewLabel,
    this.onCreateNew,
    this.onTextChanged,
    this.dropdown = false,
    this.isSelected,
    this.enabled = true,
    this.active = false,
  }) : assert(items != null || asyncSearch != null, 'Provide items or asyncSearch');

  final String? label;
  /// Display text for the currently selected value (shown when the field
  /// isn't focused/being typed into). Null/empty shows [hint].
  final String? selectedLabel;
  /// Client-side candidate pool. Filtered locally as the user types.
  final List<AppSelectItem<T>>? items;
  /// Server-side search — called (debounced) with the typed query.
  final Future<List<AppSelectItem<T>>> Function(String query)? asyncSearch;
  /// Fires with the picked item, or null when the field is cleared via (x).
  final ValueChanged<AppSelectItem<T>?> onSelected;
  final String hint;
  final double? width;
  /// When set alongside [onCreateNew], an extra row offers creating a new
  /// entry from the typed text if nothing matches (e.g. product models).
  final String Function(String query)? createNewLabel;
  final ValueChanged<String>? onCreateNew;
  /// Fires on every keystroke with the raw typed text — for genuinely
  /// free-text fields (like a product model) where the caller wants to fall
  /// back to whatever's typed even if the user never explicitly picks a
  /// suggestion or the "Create new" row. Such a caller should setState
  /// with the text and pass it back as [selectedLabel], or the field
  /// reverts to the old label when it loses focus.
  final ValueChanged<String>? onTextChanged;
  final bool dropdown;
  /// Marks the current value's row when the list opens.
  final bool Function(T value)? isSelected;
  final bool enabled;
  /// Filter bars: teal border while a filter is applied.
  final bool active;

  @override
  State<AppSearchableSelectField<T>> createState() => _AppSearchableSelectFieldState<T>();
}

class _AppSearchableSelectFieldState<T> extends State<AppSearchableSelectField<T>> {
  final _link = LayerLink();
  final _triggerKey = GlobalKey();
  final _highlightKey = GlobalKey();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _entry;
  Timer? _debounce;
  bool _open = false;
  bool _loading = false;
  // Set just before unfocus() in _pick()/_createNew() so _onFocusChange's
  // revert-on-blur-without-a-pick branch doesn't stomp the text those two
  // just set — widget.selectedLabel is a prop from the parent's setState,
  // which hasn't rebuilt this widget yet when the focus listener fires
  // (unfocus() notifies synchronously), so it's still the pre-pick value.
  bool _suppressBlurRevert = false;
  String _query = '';
  List<AppSelectItem<T>> _results = const [];
  int _highlight = -1;

  bool get _isAsync => widget.asyncSearch != null;
  // The panel builds every row, so a long pool (e.g. ~1,700 inventory
  // items) is capped to the first matches — typing narrows it. A plain
  // dropdown's list is short and must show every option.
  int get _maxLocalResults => widget.dropdown ? 1000 : 50;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.selectedLabel ?? '';
    _focusNode.addListener(_onFocusChange);
    if (!_isAsync) _results = widget.items ?? const [];
  }

  @override
  void didUpdateWidget(covariant AppSearchableSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.selectedLabel != oldWidget.selectedLabel) {
      _controller.text = widget.selectedLabel ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _entry?.remove();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      if (_isAsync) {
        _runQuery(_controller.text);
      } else {
        // Dropdowns open on the whole list; a search field opens on what
        // matches the text already in it (a product typed on a sale line).
        // The text is selected either way, so typing replaces it.
        _query = widget.dropdown ? '' : _controller.text;
        _filterLocal(_query);
        _highlight = widget.dropdown ? _results.indexWhere((i) => widget.isSelected?.call(i.value) ?? false) : -1;
      }
      _openPanel();
      _revealHighlight();
    } else {
      if (_suppressBlurRevert) {
        _suppressBlurRevert = false;
      } else {
        // Revert to the committed selection's label if the user clicked
        // away without picking anything (mirrors a native combobox).
        _controller.text = widget.selectedLabel ?? '';
      }
      _closePanel();
    }
  }

  void _onChanged(String text) {
    widget.onTextChanged?.call(text);
    setState(() { _query = text; _highlight = -1; });
    if (_isAsync) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () => _runQuery(text));
    } else {
      _filterLocal(text);
    }
    _entry?.markNeedsBuild();
  }

  void _filterLocal(String query) {
    final key = normalizeForSearch(query);
    final all = widget.items ?? const [];
    final matches = key.isEmpty ? all : all.where((i) => normalizeForSearch('${i.label} ${i.subtitle ?? ''}').contains(key));
    setState(() {
      _results = matches.take(_maxLocalResults).toList();
      // Top match pre-highlighted so Enter picks it; with no match, the
      // "Add …" row if there is one.
      if (widget.dropdown && key.isNotEmpty) _highlight = _results.isNotEmpty || _showCreateNew ? 0 : -1;
    });
    _entry?.markNeedsBuild();
  }

  Future<void> _runQuery(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = const []; _loading = false; });
      _entry?.markNeedsBuild();
      return;
    }
    setState(() => _loading = true);
    _entry?.markNeedsBuild();
    final results = await widget.asyncSearch!(query.trim());
    if (!mounted) return;
    setState(() { _results = results; _loading = false; });
    _entry?.markNeedsBuild();
  }

  // Keeps the highlighted row in view — on open (the current option may
  // be far down the list) and while arrowing through it.
  void _revealHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Below the view → scroll it up to the bottom edge; above → down
      // to the top edge; already visible → both are no-ops.
      for (final policy in const [ScrollPositionAlignmentPolicy.keepVisibleAtEnd, ScrollPositionAlignmentPolicy.keepVisibleAtStart]) {
        final ctx = _highlightKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignmentPolicy: policy);
      }
    });
  }

  bool get _showCreateNew =>
      widget.onCreateNew != null &&
      _query.trim().isNotEmpty &&
      !_loading &&
      !_results.any((i) => normalizeForSearch(i.label) == normalizeForSearch(_query));

  int get _rowCount => _results.length + (_showCreateNew ? 1 : 0);

  void _selectIndex(int index) {
    if (index < 0 || index >= _rowCount) return;
    if (index < _results.length) {
      _pick(_results[index]);
    } else {
      _createNew();
    }
  }

  void _pick(AppSelectItem<T> item) {
    _suppressBlurRevert = true;
    widget.onSelected(item);
    _controller.text = item.label;
    _focusNode.unfocus();
  }

  void _createNew() {
    _suppressBlurRevert = true;
    widget.onCreateNew?.call(_query.trim());
    _focusNode.unfocus();
  }

  void _clear() {
    widget.onSelected(null);
    _controller.clear();
    setState(() { _query = ''; _highlight = -1; });
    _isAsync ? _runQuery('') : _filterLocal('');
  }

  void _moveHighlight(int delta) {
    if (_rowCount == 0) return;
    setState(() => _highlight = _highlight < 0 && delta < 0
        ? _rowCount - 1
        : (_highlight + delta + _rowCount) % _rowCount);
    _entry?.markNeedsBuild();
    _revealHighlight();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_highlight >= 0) {
        _selectIndex(_highlight);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openPanel() {
    if (_open) { _entry?.markNeedsBuild(); return; }
    _entry = OverlayEntry(builder: (ctx) => _floatingPanel(
      ctx: ctx, fieldContext: context, link: _link, fieldKey: _triggerKey,
      onDismiss: () => _focusNode.unfocus(),
      child: _panelBody(ctx),
    ));
    Overlay.of(context).insert(_entry!);
    setState(() => _open = true);
  }

  void _closePanel() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  Widget _panelBody(BuildContext ctx) {
    if (_isAsync && _query.trim().isEmpty) {
      return _panelMessage(ctx, 'Type to search…');
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_results.isEmpty && !_showCreateNew) {
      return _panelMessage(ctx, 'No results');
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (var i = 0; i < _results.length; i++)
          _panelRow(ctx,
            key: i == _highlight ? _highlightKey : null,
            leading: _results[i].leading ?? const SizedBox(width: 16),
            label: _results[i].subtitle == null
                ? Text(_results[i].label, style: AppTheme.bodySm.copyWith(fontSize: 12.5), overflow: TextOverflow.ellipsis)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(_results[i].label, style: AppTheme.bodySm.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(_results[i].subtitle!, style: AppTheme.monoXs.copyWith(fontSize: 10.5, color: ctx.pal.textDim),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
            trailing: _results[i].trailing,
            selected: i == _highlight,
            onTap: () => _pick(_results[i]),
          ),
        if (_showCreateNew)
          _panelRow(ctx,
            key: _results.length == _highlight ? _highlightKey : null,
            leading: Icon(Symbols.add, size: 16, color: AppColors.blue),
            label: Text(
              widget.createNewLabel?.call(_query.trim()) ?? 'Create new: "${_query.trim()}"',
              style: AppTheme.bodySm.copyWith(fontSize: 12.5, color: AppColors.blue),
            ),
            selected: _results.length == _highlight,
            onTap: _createNew,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = (widget.selectedLabel ?? '').isNotEmpty;
    final focused = _focusNode.hasFocus;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.label != null) ...[
        Text(widget.label!, style: AppTheme.fieldLabel),
        const SizedBox(height: 6),
      ],
      // The Settings text input (LabeledTextField) with this combobox's
      // own FocusNode (keyboard navigation + panel open/close hang off it).
      // The panel anchors to the field itself, not the label above it.
      CompositedTransformTarget(link: _link, child: SizedBox(key: _triggerKey, width: widget.width, child: Focus(
        onKeyEvent: _handleKey,
        child: LabeledTextField(
          label: '',
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          active: widget.active,
          prefixIcon: widget.dropdown ? null : Symbols.search,
          hint: widget.dropdown && focused ? 'Type to filter…' : widget.hint,
          onChanged: _onChanged,
          onSubmitted: (_) { if (_highlight >= 0) _selectIndex(_highlight); },
          // Desktop platforms default onTapOutside to an immediate
          // unfocus() on raw pointer-down — the results panel lives in a
          // separate Overlay, so every tap on a row counted as "outside"
          // and closed the panel (via _onFocusChange) before the tap could
          // resolve into onTap, so _pick() never ran. The full-screen
          // GestureDetector in _floatingPanel() already handles "click
          // elsewhere closes it" correctly — so disable the built-in one.
          onTapOutside: (_) {},
          suffix: widget.dropdown
              ? GestureDetector(
                  onTap: widget.enabled ? () => focused ? _focusNode.unfocus() : _focusNode.requestFocus() : null,
                  child: _chevron(context, _open),
                )
              : hasValue && !focused
                  ? GestureDetector(onTap: _clear, child: Icon(Symbols.close, size: 15, color: context.pal.textDim))
                  : null,
        ),
      ))),
    ]);
  }
}
