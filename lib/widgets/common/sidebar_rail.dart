import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../main.dart' show userRoleNotifier, allowedScreenKeys;
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import 'current_user_avatar.dart';
import 'email_badge.dart';
import 'sidebar.dart'; // NavDestination

// Flat list of all nav destinations (no section grouping — icon rail doesn't label sections).
const _railItems = [
  NavDestination(icon: Symbols.space_dashboard,         label: 'Dashboard',  key: 'dashboard'),
  NavDestination(icon: Symbols.inventory_2,             label: 'Inventory',  key: 'inventory'),
  NavDestination(icon: Symbols.badge,                   label: 'Staff',      key: 'staff'),
  NavDestination(icon: Symbols.payments,                label: 'Revenue',    key: 'revenue'),
  NavDestination(icon: Symbols.account_balance,         label: 'Finance',    key: 'finance'),
  NavDestination(icon: Symbols.trending_up,             label: 'Sales',      key: 'sales'),
  NavDestination(icon: Symbols.groups,                  label: 'Customers',  key: 'customers'),
  NavDestination(icon: Symbols.mail,                    label: 'Email',      key: 'email'),
  NavDestination(icon: Symbols.assessment,              label: 'Reports',    key: 'reports'),
  NavDestination(icon: Symbols.settings,                label: 'Settings',   key: 'settings'),
];

/// 64 px icon-only navigation rail — used on tablet (820–1099 px).
///
/// Active item: [context.pal.surface2] background + [AppColors.teal] icon
/// + left accent bar. Hovering shows a [Tooltip] with the destination label.
class SidebarRail extends StatelessWidget {
  const SidebarRail({
    super.key,
    required this.activeKey,
    required this.onSelect,
  });

  final String activeKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: context.pal.sidebarBg,
        border: Border(right: BorderSide(color: context.pal.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: () {
                    final allowed = allowedScreenKeys(userRoleNotifier.value);
                    final items   = allowed == null
                        ? _railItems
                        : _railItems.where((d) => allowed.contains(d.key)).toList();
                    return items.map((dest) => _RailItem(
                      dest: dest,
                      active: dest.key == activeKey,
                      onTap: () => onSelect(dest.key),
                    )).toList();
                  }(),
              ),
            ),
          ),
          // Footer separator + avatar
          Container(width: 32, height: 1, color: context.pal.border),
          const SizedBox(height: 10),
          Tooltip(message: 'My profile', child: InkWell(
            onTap: () => onSelect('settings'),
            customBorder: const CircleBorder(),
            child: const CurrentUserAvatar(size: 26),
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.dest,
    required this.active,
    required this.onTap,
  });

  final NavDestination dest;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: dest.label,
      preferBelow: false,
      verticalOffset: 6,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Active left accent bar
              if (active)
                Positioned(
                  left: 0, top: 6, bottom: 6,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                      boxShadow: [BoxShadow(color: AppColors.tealGlow, blurRadius: 8)],
                    ),
                  ),
                ),
              // Icon button (40×40 inside 64 wide rail — centred)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? context.pal.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  dest.icon,
                  size: 20,
                  color: active ? AppColors.teal : context.pal.textMute,
                ),
              ),
              // Unread / failed-send counts on the Email icon.
              if (dest.key == 'email')
                const Positioned(top: 0, right: 4, child: EmailNavBadge(compact: true)),
            ],
          ),
        ),
      ),
    );
  }
}
