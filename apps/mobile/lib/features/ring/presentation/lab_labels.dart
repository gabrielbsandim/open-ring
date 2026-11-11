import 'package:open_ring/features/ring/application/protocol_lab_state.dart';
import 'package:open_ring/features/ring/domain/checksum_rule.dart';
import 'package:open_ring/features/ring/domain/frame_insight.dart';
import 'package:open_ring/features/ring/domain/frame_log_entry.dart';
import 'package:open_ring/features/ring/domain/hex_bytes.dart';
import 'package:open_ring/features/ring/domain/raw_frame.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';
import 'package:ring_driver/ring_driver.dart';
import 'package:ring_protocol/ring_protocol.dart';

extension LabNoticeLabel on LabNotice {
  String describe(AppLocalizations l10n) => switch (this) {
    TransportFailure(:final message) => l10n.labErrorTransport(message),
    ExportFailure(:final message) => l10n.labErrorExport(message),
    RawFrameRejected(:final error, :final byteCount) => error.describe(
      l10n,
      byteCount,
    ),
  };
}

extension on RawFrameError {
  String describe(AppLocalizations l10n, int byteCount) => switch (this) {
    RawFrameError.empty => l10n.labRawEmpty,
    RawFrameError.notHex => l10n.labRawNotHex,
    RawFrameError.wrongLength => l10n.labRawWrongLength(byteCount),
    RawFrameError.blockedCommand => l10n.labRawBlocked,
  };
}

extension LabLinkLabel on ProtocolLabState {
  String linkLabel(AppLocalizations l10n) {
    final name = deviceName(l10n);
    return switch (link) {
      TransportState.disconnected => l10n.labLinkDisconnected,
      TransportState.connecting => l10n.labLinkConnecting(name),
      TransportState.connected => l10n.labLinkConnected(name),
    };
  }

  String deviceName(AppLocalizations l10n) {
    final current = device;
    if (current == null) return l10n.labUnnamedDevice;
    if (current.name.isEmpty) return current.id;
    return current.name;
  }
}

extension ChecksumRuleLabel on ChecksumRule {
  String label(AppLocalizations l10n) => switch (this) {
    ChecksumRule.masked => l10n.labChecksumMasked,
    ChecksumRule.modulo255 => l10n.labChecksumModulo,
  };
}

extension FrameDirectionLabel on FrameDirection {
  String label(AppLocalizations l10n) => switch (this) {
    FrameDirection.tx => l10n.labDirectionTx,
    FrameDirection.rx => l10n.labDirectionRx,
  };
}

extension FrameInsightLabel on FrameInsight {
  List<String> lines(AppLocalizations l10n) => [
    ...?reading?.lines(l10n),
    if (checksums.isEmpty)
      l10n.labChecksumNoMatch
    else
      l10n.labChecksumMatches(
        ChecksumRule.values
            .where(checksums.contains)
            .map((rule) => rule.label(l10n))
            .join(' / '),
      ),
  ];
}

extension FrameReadingLabel on FrameReading {
  List<String> lines(AppLocalizations l10n) => switch (this) {
    BatteryFrame(:final reading) => [
      _battery(l10n, reading.percent, charging: reading.charging),
    ],
    CapabilitiesFrame(:final capabilities) => capabilities.lines(l10n),
    AutoMonitorFrame(:final monitor, enabled: true, :final rawValue) => [
      l10n.labAutoMonitorOn(monitor.label(l10n), HexBytes.id(rawValue)),
    ],
    AutoMonitorFrame(:final monitor, enabled: false, :final rawValue) => [
      l10n.labAutoMonitorOff(monitor.label(l10n), HexBytes.id(rawValue)),
    ],
    TodayTotalsFrame(:final bigEndian, :final littleEndian) => [
      bigEndian.describe(l10n.labTotalsBigEndian),
      littleEndian.describe(l10n.labTotalsLittleEndian),
    ],
    RealTimeFrame(:final reading) => [reading.label(l10n)],
    RealTimeStopFrame() => [l10n.labStopAck],
    NotifyFrame(:final notification) => notification.lines(l10n),
    FlaggedReplyFrame(:final command) => [
      l10n.labReplyFlagged(HexBytes.id(command)),
    ],
    UnexpectedByteFrame(:final command, :final index, :final value) => [
      l10n.labUnexpectedByte(HexBytes.id(command), index, HexBytes.id(value)),
    ],
  };
}

extension AutoMonitorLabel on AutoMonitor {
  String label(AppLocalizations l10n) => switch (this) {
    AutoMonitor.spo2 => l10n.labAutoSpo2,
    AutoMonitor.stress => l10n.labAutoStress,
    AutoMonitor.hrv => l10n.labAutoHrv,
  };
}

extension StopProbeLabel on StopProbe {
  String label(AppLocalizations l10n) {
    if (stopSent) return l10n.labStopProbeCounts(before, after);
    return l10n.labStopProbeWaiting(before);
  }
}

String _battery(AppLocalizations l10n, int percent, {required bool charging}) {
  if (charging) return l10n.labBatteryCharging(percent);
  return l10n.labBatteryNotCharging(percent);
}

extension on DeviceCapabilities {
  List<String> lines(AppLocalizations l10n) {
    final flags = [
      (l10n.labCapTemperature, supportsTemperature),
      (l10n.labCapBloodOxygen, supportsBloodOxygen),
      (l10n.labCapBloodPressure, supportsBloodPressure),
      (l10n.labCapNewSleep, newSleepProtocol),
      (l10n.labCapManualHeartRate, supportsManualHeartRate),
      (l10n.labCapBloodSugar, supportsBloodSugar),
      (l10n.labCapStress, supportsPressure),
      (l10n.labCapHrv, supportsHrv),
    ];
    String names({required bool supported}) {
      final matching = [
        for (final (name, value) in flags)
          if (value == supported) name,
      ];
      if (matching.isEmpty) return l10n.labNone;
      return matching.join(', ');
    }

    return [
      l10n.labCapabilitiesOn(names(supported: true)),
      l10n.labCapabilitiesOff(names(supported: false)),
    ];
  }
}

extension on TodayTotals {
  String describe(
    String Function(
      int steps,
      int running,
      int calories,
      int distance,
      int minutes,
    )
    message,
  ) => message(
    totalSteps,
    runningSteps,
    calories,
    walkingDistanceMeters,
    activeMinutes,
  );
}

extension on RealTimeReading {
  String label(AppLocalizations l10n) {
    final id = HexBytes.id(type.id);
    if (isError) return l10n.labRealTimeError(id, errorCode);
    return switch (type) {
      RealTimeType.heartRate ||
      RealTimeType.realTimeHeartRate => l10n.labRealTimeHeartRate(value),
      _ => l10n.labRealTimeValue(id, value),
    };
  }
}

extension on DeviceNotification {
  List<String> lines(AppLocalizations l10n) => [
    l10n.labNotify(HexBytes.id(type), _notifyKind(l10n, type)),
    ...switch (this) {
      NewDataAvailable() => [l10n.labNotifyNewData],
      BatteryNotification(:final percent, :final charging) => [
        _battery(l10n, percent, charging: charging),
      ],
      LiveActivityNotification(
        :final steps,
        :final calories,
        :final distanceMeters,
      ) =>
        [l10n.labLiveActivity(steps, calories, distanceMeters)],
      final TemperatureNotification temperature => [
        if (temperature.provisionalCelsius case final celsius?)
          l10n.labNotifyTemperatureValue(celsius.toStringAsFixed(1)),
        l10n.labPayload(HexBytes.spaced(temperature.raw)),
      ],
      UnknownNotification(:final raw) => [
        l10n.labPayload(HexBytes.spaced(raw)),
      ],
    },
  ];
}

String _notifyKind(AppLocalizations l10n, int type) => switch (type) {
  NotifyType.heartRate => l10n.labNotifyHeartRate,
  NotifyType.spo2 => l10n.labNotifySpo2,
  NotifyType.steps => l10n.labNotifySteps,
  NotifyType.temperature => l10n.labNotifyTemperature,
  NotifyType.battery => l10n.labNotifyBattery,
  NotifyType.liveActivity => l10n.labNotifyLiveActivity,
  _ => l10n.labNotifyUnknown,
};
