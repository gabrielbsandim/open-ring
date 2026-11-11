import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/features/ring/application/protocol_lab_controller.dart';
import 'package:open_ring/features/ring/application/protocol_lab_state.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/presentation/lab_device_tile.dart';
import 'package:open_ring/features/ring/presentation/lab_labels.dart';
import 'package:open_ring/features/ring/presentation/lab_log_tile.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

class ProtocolLabScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const noticeKey = Key('lab_notice');
  static const linkKey = Key('lab_link');
  static const scanKey = Key('lab_scan');
  static const stopScanKey = Key('lab_stop_scan');
  static const disconnectKey = Key('lab_disconnect');
  static const batteryKey = Key('lab_battery');
  static const findDeviceKey = Key('lab_find_device');
  static const setTimeKey = Key('lab_set_time');
  static const todayTotalsKey = Key('lab_today_totals');
  static const stopProbeKey = Key('lab_stop_probe');
  static const stopProbeStatusKey = Key('lab_stop_probe_status');
  static const rawFieldKey = Key('lab_raw_field');
  static const sendRawKey = Key('lab_send_raw');
  static const exportKey = Key('lab_export');
  static const clearKey = Key('lab_clear');

  static Key checksumKey(ChecksumRule rule) => Key('lab_checksum_${rule.name}');

  static Key autoMonitorKey(AutoMonitor monitor) =>
      Key('lab_auto_${monitor.name}');

  @override
  ConsumerState<ProtocolLabScreen> createState() => _ProtocolLabScreenState();
}

class _ProtocolLabScreenState extends ConsumerState<ProtocolLabScreen> {
  final _raw = TextEditingController();

  ProtocolLabController get _lab => ref.read(protocolLabProvider.notifier);

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lab = ref.watch(protocolLabProvider);
    return AppPage(
      title: l10n.labTitle,
      children: [
        if (lab.notice case final notice?) ...[
          _NoticeBanner(message: notice.describe(l10n)),
          const SizedBox(height: 16),
        ],
        _Section(
          title: l10n.labDeviceSection,
          children: _deviceSection(context, l10n, lab),
        ),
        _Section(
          title: l10n.labCommandsSection,
          children: _commandSection(context, l10n, lab),
        ),
        _Section(
          title: l10n.labLogSection,
          children: _logSection(context, l10n, lab),
        ),
      ],
    );
  }

  List<Widget> _deviceSection(
    BuildContext context,
    AppLocalizations l10n,
    ProtocolLabState lab,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final linked = lab.link != TransportState.disconnected;
    return [
      Text(
        lab.linkLabel(l10n),
        key: ProtocolLabScreen.linkKey,
        style: theme.textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (lab.scanning)
            OutlinedButton(
              key: ProtocolLabScreen.stopScanKey,
              onPressed: () => unawaited(_lab.stopScan()),
              child: Text(l10n.labStopScan),
            )
          else
            FilledButton(
              key: ProtocolLabScreen.scanKey,
              onPressed: linked ? null : () => unawaited(_lab.startScan()),
              child: Text(l10n.labScan),
            ),
          if (linked)
            OutlinedButton(
              key: ProtocolLabScreen.disconnectKey,
              onPressed: () => unawaited(_lab.disconnect()),
              child: Text(l10n.labDisconnect),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (lab.scanning)
        Text(
          l10n.labScanning,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
        ),
      if (lab.devices.isEmpty && !lab.scanning)
        Text(
          l10n.labNoDevices,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
        ),
      for (final device in lab.devices)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LabDeviceTile(
            key: LabDeviceTile.keyFor(device.id),
            device: device,
            onConnect: linked ? null : () => unawaited(_lab.connect(device)),
          ),
        ),
    ];
  }

  List<Widget> _commandSection(
    BuildContext context,
    AppLocalizations l10n,
    ProtocolLabState lab,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final ready = lab.connected;
    return [
      Text(l10n.labChecksumTitle, style: theme.textTheme.titleSmall),
      RadioGroup<ChecksumRule>(
        groupValue: lab.checksum,
        onChanged: _selectChecksum,
        child: Column(
          children: [
            for (final rule in ChecksumRule.values)
              RadioListTile<ChecksumRule>(
                key: ProtocolLabScreen.checksumKey(rule),
                value: rule,
                contentPadding: EdgeInsets.zero,
                title: Text(rule.label(l10n)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonal(
            key: ProtocolLabScreen.batteryKey,
            onPressed: ready ? () => unawaited(_lab.readBattery()) : null,
            child: Text(l10n.labReadBattery),
          ),
          FilledButton.tonal(
            key: ProtocolLabScreen.findDeviceKey,
            onPressed: ready ? () => unawaited(_lab.findDevice()) : null,
            child: Text(l10n.labFindDevice),
          ),
          FilledButton.tonal(
            key: ProtocolLabScreen.setTimeKey,
            onPressed: ready ? () => unawaited(_lab.setTime()) : null,
            child: Text(l10n.labSetTime),
          ),
          for (final monitor in AutoMonitor.values)
            FilledButton.tonal(
              key: ProtocolLabScreen.autoMonitorKey(monitor),
              onPressed: ready
                  ? () => unawaited(_lab.readAutoMonitor(monitor))
                  : null,
              child: Text(l10n.labReadSetting(monitor.label(l10n))),
            ),
          FilledButton.tonal(
            key: ProtocolLabScreen.todayTotalsKey,
            onPressed: ready ? () => unawaited(_lab.readTodayTotals()) : null,
            child: Text(l10n.labTodayTotals),
          ),
          FilledButton.tonal(
            key: ProtocolLabScreen.stopProbeKey,
            onPressed: ready ? () => unawaited(_lab.startStopProbe()) : null,
            child: Text(l10n.labStopProbe),
          ),
        ],
      ),
      if (lab.stopProbe case final probe?) ...[
        const SizedBox(height: 8),
        Text(
          probe.label(l10n),
          key: ProtocolLabScreen.stopProbeStatusKey,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        l10n.labNotifyHint,
        style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
      ),
      const SizedBox(height: 16),
      TextField(
        key: ProtocolLabScreen.rawFieldKey,
        controller: _raw,
        maxLines: null,
        autocorrect: false,
        enableSuggestions: false,
        style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: l10n.labRawLabel,
          helperText: l10n.labRawHelper,
          helperMaxLines: 6,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(
        key: ProtocolLabScreen.sendRawKey,
        onPressed: ready ? () => unawaited(_lab.sendRaw(_raw.text)) : null,
        child: Text(l10n.labSendRaw),
      ),
    ];
  }

  List<Widget> _logSection(
    BuildContext context,
    AppLocalizations l10n,
    ProtocolLabState lab,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final hasFrames = lab.log.isNotEmpty;
    return [
      if (hasFrames)
        Text(
          l10n.labLogCount(lab.log.length),
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: ProtocolLabScreen.exportKey,
            onPressed: hasFrames ? () => unawaited(_lab.exportLog()) : null,
            child: Text(l10n.labExport),
          ),
          OutlinedButton(
            key: ProtocolLabScreen.clearKey,
            onPressed: hasFrames ? _lab.clearLog : null,
            child: Text(l10n.labClear),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (!hasFrames)
        Text(
          l10n.labLogEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textLabel),
        ),
      for (final entry in lab.log.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LabLogTile(entry: entry),
        ),
    ];
  }

  void _selectChecksum(ChecksumRule? rule) {
    if (rule == null) return;
    _lab.selectChecksum(rule);
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        key: ProtocolLabScreen.noticeKey,
        decoration: BoxDecoration(
          color: colors.surfaceInner,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.heart),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: colors.heart),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
