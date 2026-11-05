import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../screens/finance/connections_screen.dart';

/// Opens the web of records connected to this one (ConnectionsScreen).
class ConnectionsButton extends StatelessWidget {
  const ConnectionsButton({super.key, required this.type, required this.id, this.compact = false});
  final String type;
  final int id;
  final bool compact;

  void _open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConnectionsScreen(type: type, id: id)));

  @override
  Widget build(BuildContext context) => compact
      ? IconButton(
          tooltip: 'Connections — everything linked to this',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Symbols.hub),
          onPressed: () => _open(context),
        )
      : OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Symbols.hub, size: 15),
          label: const Text('Connections'),
        );
}
