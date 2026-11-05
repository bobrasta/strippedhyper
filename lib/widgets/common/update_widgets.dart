import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../main.dart' show userRoleNotifier, hasDirectorAuthority;
import '../../services/update_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import 'app_button.dart';

UpdateService get _svc => UpdateService.instance;

/// Thin strip under the top bar: "update available" (mode off), download
/// progress, "Restart to update", or immediate mode's countdown.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!UpdateService.supported) return const SizedBox.shrink();
    return ValueListenableBuilder<UpdateState>(
      valueListenable: _svc.state,
      builder: (context, s, _) {
        final v = s.manifest?.version;
        final (IconData icon, String text, Widget? action) = switch (s.phase) {
          UpdatePhase.available when _svc.effectiveMode == UpdateMode.off => (
            Symbols.system_update,
            'Hypermed $v is available.',
            AppButton(label: 'Update now', small: true, variant: BtnVariant.primary, onPressed: _svc.download),
          ),
          UpdatePhase.downloading when s.required || _svc.effectiveMode == UpdateMode.off => (
            Symbols.downloading,
            'Downloading Hypermed $v… ${((s.progress ?? 0) * 100).round()}%',
            null,
          ),
          UpdatePhase.ready when s.installAt != null => (
            Symbols.restart_alt,
            'Hypermed $v will install shortly — save your work.',
            _CountdownActions(at: s.installAt!),
          ),
          UpdatePhase.ready => (
            Symbols.restart_alt,
            'Hypermed $v is ready. It installs next time you open the app.',
            AppButton(label: 'Restart to update', small: true, variant: BtnVariant.primary, onPressed: _svc.installNow),
          ),
          UpdatePhase.installing => (Symbols.install_desktop, 'Installing Hypermed $v…', null),
          _ => (Symbols.check, '', null),
        };
        if (text.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            border: Border(bottom: BorderSide(color: AppColors.teal.withValues(alpha: 0.3))),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.teal),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTheme.bodySm.copyWith(color: context.pal.text))),
            if (action != null) action,
          ]),
        );
      },
    );
  }
}

class _CountdownActions extends StatefulWidget {
  const _CountdownActions({required this.at});
  final DateTime at;
  @override
  State<_CountdownActions> createState() => _CountdownActionsState();
}

class _CountdownActionsState extends State<_CountdownActions> {
  late final Timer _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.at.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${left}s', style: AppTheme.monoSm.copyWith(color: AppColors.teal)),
      const SizedBox(width: 10),
      AppButton(label: 'Later', small: true, variant: BtnVariant.ghost, onPressed: _svc.postpone),
      const SizedBox(width: 6),
      AppButton(label: 'Install now', small: true, variant: BtnVariant.primary, onPressed: _svc.installNow),
    ]);
  }
}

/// Blocks the whole app when the running version is below the feed's
/// `min_version` — shown regardless of update mode.
class UpdateRequiredGate extends StatelessWidget {
  const UpdateRequiredGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!UpdateService.supported) return child;
    return ValueListenableBuilder<UpdateState>(
      valueListenable: _svc.state,
      builder: (context, s, _) {
        if (!s.required || s.phase == UpdatePhase.upToDate) return child;
        final v = s.manifest?.version ?? '';
        final (String status, Widget? action) = switch (s.phase) {
          UpdatePhase.downloading => ('Downloading… ${((s.progress ?? 0) * 100).round()}%', null),
          UpdatePhase.ready => ('Ready to install.', AppButton(label: 'Install and restart', variant: BtnVariant.primary, onPressed: _svc.installNow)),
          UpdatePhase.installing => ('Installing…', null),
          UpdatePhase.error => (s.error ?? 'Something went wrong.', AppButton(label: 'Try again', variant: BtnVariant.primary, onPressed: () => _svc.check(userInitiated: true))),
          _ => ('Preparing the update…', AppButton(label: 'Download', variant: BtnVariant.primary, onPressed: _svc.download)),
        };
        return Scaffold(
          backgroundColor: context.pal.bg,
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: context.pal.surface1,
                borderRadius: BorderRadius.circular(AppColors.rLg),
                border: Border.all(color: context.pal.border),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Symbols.system_update, size: 36, color: AppColors.teal),
                const SizedBox(height: 14),
                Text('Update required', style: AppTheme.pageTitle.copyWith(fontSize: 20)),
                const SizedBox(height: 8),
                Text(
                  'This version (${_svc.currentVersion.value}) is no longer supported. '
                  'Hypermed $v is needed to keep working.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodySub,
                ),
                const SizedBox(height: 18),
                if (s.phase == UpdatePhase.downloading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(value: s.progress, color: AppColors.teal, backgroundColor: context.pal.surface3),
                  ),
                Text(status, style: AppTheme.bodySm.copyWith(color: context.pal.textMute)),
                if (action != null) ...[const SizedBox(height: 14), action],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Settings → Preferences card: version, mode, check-now, and (Director)
/// the company-wide policy.
class AppUpdatesCard extends StatelessWidget {
  const AppUpdatesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.pal.surface1,
        borderRadius: BorderRadius.circular(AppColors.rLg),
        border: Border.all(color: context.pal.border),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([_svc.state, _svc.localMode, _svc.policyMode, _svc.currentVersion, userRoleNotifier]),
        builder: (context, _) {
          final s = _svc.state.value;
          final locked = _svc.policyMode.value != null;
          final isDirector = hasDirectorAuthority(userRoleNotifier.value);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.system_update, size: 18, color: context.pal.textMute),
              const SizedBox(width: 8),
              Expanded(child: Text('App updates', style: AppTheme.bodyStrong.copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text('Version ${_svc.currentVersion.value}', style: AppTheme.monoSm),
            ]),
            const SizedBox(height: 16),
            if (!UpdateService.supported)
              Text('Automatic updates run in the installed Windows and Linux app.', style: AppTheme.bodySub)
            else ...[
              Text('When an update is available', style: AppTheme.fieldLabel),
              const SizedBox(height: 6),
              for (final m in UpdateMode.values)
                _ModeOption(
                  mode: m,
                  selected: _svc.effectiveMode == m,
                  enabled: !locked,
                  onTap: () => _svc.setLocalMode(m),
                ),
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Symbols.lock, size: 13, color: context.pal.textDim),
                    const SizedBox(width: 6),
                    Text('Set company-wide by a Director.', style: AppTheme.bodySub.copyWith(fontSize: 11.5)),
                  ]),
                ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(_statusText(s), style: AppTheme.bodySm.copyWith(color: context.pal.textMute))),
                if (s.phase == UpdatePhase.ready)
                  AppButton(label: 'Restart to update', small: true, variant: BtnVariant.primary, onPressed: _svc.installNow)
                else if (s.phase == UpdatePhase.available)
                  AppButton(label: 'Download update', small: true, variant: BtnVariant.primary, onPressed: _svc.download)
                else
                  AppButton(
                    label: 'Check for updates',
                    icon: Symbols.refresh,
                    small: true,
                    onPressed: s.phase == UpdatePhase.checking || s.phase == UpdatePhase.downloading
                        ? null
                        : () => _svc.check(userInitiated: true),
                  ),
              ]),
              if (s.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: s.progress, color: AppColors.teal, backgroundColor: context.pal.surface3),
              ],
              if (s.manifest?.notes.isNotEmpty == true &&
                  (s.phase == UpdatePhase.available || s.phase == UpdatePhase.ready || s.phase == UpdatePhase.downloading)) ...[
                const SizedBox(height: 12),
                Text("What's new in ${s.manifest!.version}", style: AppTheme.fieldLabel),
                const SizedBox(height: 4),
                Text(s.manifest!.notes, style: AppTheme.bodySm.copyWith(color: context.pal.textMute, height: 1.5)),
              ],
            ],
            if (isDirector) ...[
              const SizedBox(height: 18),
              Container(height: 1, color: context.pal.border),
              const SizedBox(height: 14),
              Text('Company-wide policy', style: AppTheme.fieldLabel),
              const SizedBox(height: 6),
              _PolicyPicker(current: _svc.policyMode.value),
            ],
          ]);
        },
      ),
    );
  }

  String _statusText(UpdateState s) => switch (s.phase) {
    UpdatePhase.idle => 'Not checked yet.',
    UpdatePhase.checking => 'Checking for updates…',
    UpdatePhase.upToDate => "You're up to date.",
    UpdatePhase.available => 'Version ${s.manifest?.version} is available.',
    UpdatePhase.downloading => 'Downloading ${s.manifest?.version}…',
    UpdatePhase.ready => 'Version ${s.manifest?.version} is downloaded and ready.',
    UpdatePhase.installing => 'Installing…',
    UpdatePhase.error => s.error ?? 'Update check failed.',
  };
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.selected, required this.enabled, required this.onTap});
  final UpdateMode mode;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.teal : context.pal.textDim;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled || selected ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            Icon(selected ? Symbols.radio_button_checked : Symbols.radio_button_unchecked, size: 18, color: color),
            const SizedBox(width: 10),
            Text(mode.label, style: AppTheme.bodySm.copyWith(color: context.pal.text)),
          ]),
        ),
      ),
    );
  }
}

class _PolicyPicker extends StatefulWidget {
  const _PolicyPicker({required this.current});
  final UpdateMode? current;
  @override
  State<_PolicyPicker> createState() => _PolicyPickerState();
}

class _PolicyPickerState extends State<_PolicyPicker> {
  bool _saving = false;

  Future<void> _set(UpdateMode? m) async {
    setState(() => _saving = true);
    try {
      await _svc.setPolicy(m);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the update policy.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <(UpdateMode?, String)>[
      (null, 'Each user chooses'),
      for (final m in UpdateMode.values) (m, m.label),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (m, label) in options)
        ChoiceChip(
          label: Text(label, style: AppTheme.bodySm.copyWith(fontSize: 12)),
          selected: widget.current == m,
          onSelected: _saving ? null : (_) => _set(m),
          selectedColor: AppColors.tealSoft,
          side: BorderSide(color: widget.current == m ? AppColors.teal : context.pal.border),
          showCheckmark: false,
        ),
    ]);
  }
}
