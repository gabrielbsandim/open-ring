// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $RingDevicesTable extends RingDevices
    with TableInfo<$RingDevicesTable, RingDeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RingDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firmwareMeta = const VerificationMeta(
    'firmware',
  );
  @override
  late final GeneratedColumn<String> firmware = GeneratedColumn<String>(
    'firmware',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pairedAtUtcMsMeta = const VerificationMeta(
    'pairedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> pairedAtUtcMs = GeneratedColumn<int>(
    'paired_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSyncAtUtcMsMeta = const VerificationMeta(
    'lastSyncAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> lastSyncAtUtcMs = GeneratedColumn<int>(
    'last_sync_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batteryPercentMeta = const VerificationMeta(
    'batteryPercent',
  );
  @override
  late final GeneratedColumn<int> batteryPercent = GeneratedColumn<int>(
    'battery_percent',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batteryChargingMeta = const VerificationMeta(
    'batteryCharging',
  );
  @override
  late final GeneratedColumn<bool> batteryCharging = GeneratedColumn<bool>(
    'battery_charging',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("battery_charging" IN (0, 1))',
    ),
  );
  static const VerificationMeta _batteryAtUtcMsMeta = const VerificationMeta(
    'batteryAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> batteryAtUtcMs = GeneratedColumn<int>(
    'battery_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unpairedAtUtcMsMeta = const VerificationMeta(
    'unpairedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> unpairedAtUtcMs = GeneratedColumn<int>(
    'unpaired_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoHeartRateMeta = const VerificationMeta(
    'autoHeartRate',
  );
  @override
  late final GeneratedColumn<bool> autoHeartRate = GeneratedColumn<bool>(
    'auto_heart_rate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_heart_rate" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _autoSpo2Meta = const VerificationMeta(
    'autoSpo2',
  );
  @override
  late final GeneratedColumn<bool> autoSpo2 = GeneratedColumn<bool>(
    'auto_spo2',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_spo2" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _autoStressMeta = const VerificationMeta(
    'autoStress',
  );
  @override
  late final GeneratedColumn<bool> autoStress = GeneratedColumn<bool>(
    'auto_stress',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_stress" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _autoHrvMeta = const VerificationMeta(
    'autoHrv',
  );
  @override
  late final GeneratedColumn<bool> autoHrv = GeneratedColumn<bool>(
    'auto_hrv',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_hrv" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    name,
    model,
    firmware,
    pairedAtUtcMs,
    lastSyncAtUtcMs,
    batteryPercent,
    batteryCharging,
    batteryAtUtcMs,
    unpairedAtUtcMs,
    autoHeartRate,
    autoSpo2,
    autoStress,
    autoHrv,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ring_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<RingDeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('firmware')) {
      context.handle(
        _firmwareMeta,
        firmware.isAcceptableOrUnknown(data['firmware']!, _firmwareMeta),
      );
    }
    if (data.containsKey('paired_at_utc_ms')) {
      context.handle(
        _pairedAtUtcMsMeta,
        pairedAtUtcMs.isAcceptableOrUnknown(
          data['paired_at_utc_ms']!,
          _pairedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pairedAtUtcMsMeta);
    }
    if (data.containsKey('last_sync_at_utc_ms')) {
      context.handle(
        _lastSyncAtUtcMsMeta,
        lastSyncAtUtcMs.isAcceptableOrUnknown(
          data['last_sync_at_utc_ms']!,
          _lastSyncAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('battery_percent')) {
      context.handle(
        _batteryPercentMeta,
        batteryPercent.isAcceptableOrUnknown(
          data['battery_percent']!,
          _batteryPercentMeta,
        ),
      );
    }
    if (data.containsKey('battery_charging')) {
      context.handle(
        _batteryChargingMeta,
        batteryCharging.isAcceptableOrUnknown(
          data['battery_charging']!,
          _batteryChargingMeta,
        ),
      );
    }
    if (data.containsKey('battery_at_utc_ms')) {
      context.handle(
        _batteryAtUtcMsMeta,
        batteryAtUtcMs.isAcceptableOrUnknown(
          data['battery_at_utc_ms']!,
          _batteryAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('unpaired_at_utc_ms')) {
      context.handle(
        _unpairedAtUtcMsMeta,
        unpairedAtUtcMs.isAcceptableOrUnknown(
          data['unpaired_at_utc_ms']!,
          _unpairedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('auto_heart_rate')) {
      context.handle(
        _autoHeartRateMeta,
        autoHeartRate.isAcceptableOrUnknown(
          data['auto_heart_rate']!,
          _autoHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('auto_spo2')) {
      context.handle(
        _autoSpo2Meta,
        autoSpo2.isAcceptableOrUnknown(data['auto_spo2']!, _autoSpo2Meta),
      );
    }
    if (data.containsKey('auto_stress')) {
      context.handle(
        _autoStressMeta,
        autoStress.isAcceptableOrUnknown(data['auto_stress']!, _autoStressMeta),
      );
    }
    if (data.containsKey('auto_hrv')) {
      context.handle(
        _autoHrvMeta,
        autoHrv.isAcceptableOrUnknown(data['auto_hrv']!, _autoHrvMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  RingDeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RingDeviceRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      firmware: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}firmware'],
      ),
      pairedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paired_at_utc_ms'],
      )!,
      lastSyncAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sync_at_utc_ms'],
      ),
      batteryPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_percent'],
      ),
      batteryCharging: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}battery_charging'],
      ),
      batteryAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_at_utc_ms'],
      ),
      unpairedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unpaired_at_utc_ms'],
      ),
      autoHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_heart_rate'],
      )!,
      autoSpo2: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_spo2'],
      )!,
      autoStress: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_stress'],
      )!,
      autoHrv: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_hrv'],
      )!,
    );
  }

  @override
  $RingDevicesTable createAlias(String alias) {
    return $RingDevicesTable(attachedDatabase, alias);
  }
}

class RingDeviceRow extends DataClass implements Insertable<RingDeviceRow> {
  final String deviceId;
  final String name;
  final String? model;
  final String? firmware;
  final int pairedAtUtcMs;
  final int? lastSyncAtUtcMs;
  final int? batteryPercent;
  final bool? batteryCharging;
  final int? batteryAtUtcMs;
  final int? unpairedAtUtcMs;
  final bool autoHeartRate;
  final bool autoSpo2;
  final bool autoStress;
  final bool autoHrv;
  const RingDeviceRow({
    required this.deviceId,
    required this.name,
    this.model,
    this.firmware,
    required this.pairedAtUtcMs,
    this.lastSyncAtUtcMs,
    this.batteryPercent,
    this.batteryCharging,
    this.batteryAtUtcMs,
    this.unpairedAtUtcMs,
    required this.autoHeartRate,
    required this.autoSpo2,
    required this.autoStress,
    required this.autoHrv,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || firmware != null) {
      map['firmware'] = Variable<String>(firmware);
    }
    map['paired_at_utc_ms'] = Variable<int>(pairedAtUtcMs);
    if (!nullToAbsent || lastSyncAtUtcMs != null) {
      map['last_sync_at_utc_ms'] = Variable<int>(lastSyncAtUtcMs);
    }
    if (!nullToAbsent || batteryPercent != null) {
      map['battery_percent'] = Variable<int>(batteryPercent);
    }
    if (!nullToAbsent || batteryCharging != null) {
      map['battery_charging'] = Variable<bool>(batteryCharging);
    }
    if (!nullToAbsent || batteryAtUtcMs != null) {
      map['battery_at_utc_ms'] = Variable<int>(batteryAtUtcMs);
    }
    if (!nullToAbsent || unpairedAtUtcMs != null) {
      map['unpaired_at_utc_ms'] = Variable<int>(unpairedAtUtcMs);
    }
    map['auto_heart_rate'] = Variable<bool>(autoHeartRate);
    map['auto_spo2'] = Variable<bool>(autoSpo2);
    map['auto_stress'] = Variable<bool>(autoStress);
    map['auto_hrv'] = Variable<bool>(autoHrv);
    return map;
  }

  RingDevicesCompanion toCompanion(bool nullToAbsent) {
    return RingDevicesCompanion(
      deviceId: Value(deviceId),
      name: Value(name),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      firmware: firmware == null && nullToAbsent
          ? const Value.absent()
          : Value(firmware),
      pairedAtUtcMs: Value(pairedAtUtcMs),
      lastSyncAtUtcMs: lastSyncAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAtUtcMs),
      batteryPercent: batteryPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryPercent),
      batteryCharging: batteryCharging == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryCharging),
      batteryAtUtcMs: batteryAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryAtUtcMs),
      unpairedAtUtcMs: unpairedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(unpairedAtUtcMs),
      autoHeartRate: Value(autoHeartRate),
      autoSpo2: Value(autoSpo2),
      autoStress: Value(autoStress),
      autoHrv: Value(autoHrv),
    );
  }

  factory RingDeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RingDeviceRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      name: serializer.fromJson<String>(json['name']),
      model: serializer.fromJson<String?>(json['model']),
      firmware: serializer.fromJson<String?>(json['firmware']),
      pairedAtUtcMs: serializer.fromJson<int>(json['pairedAtUtcMs']),
      lastSyncAtUtcMs: serializer.fromJson<int?>(json['lastSyncAtUtcMs']),
      batteryPercent: serializer.fromJson<int?>(json['batteryPercent']),
      batteryCharging: serializer.fromJson<bool?>(json['batteryCharging']),
      batteryAtUtcMs: serializer.fromJson<int?>(json['batteryAtUtcMs']),
      unpairedAtUtcMs: serializer.fromJson<int?>(json['unpairedAtUtcMs']),
      autoHeartRate: serializer.fromJson<bool>(json['autoHeartRate']),
      autoSpo2: serializer.fromJson<bool>(json['autoSpo2']),
      autoStress: serializer.fromJson<bool>(json['autoStress']),
      autoHrv: serializer.fromJson<bool>(json['autoHrv']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'name': serializer.toJson<String>(name),
      'model': serializer.toJson<String?>(model),
      'firmware': serializer.toJson<String?>(firmware),
      'pairedAtUtcMs': serializer.toJson<int>(pairedAtUtcMs),
      'lastSyncAtUtcMs': serializer.toJson<int?>(lastSyncAtUtcMs),
      'batteryPercent': serializer.toJson<int?>(batteryPercent),
      'batteryCharging': serializer.toJson<bool?>(batteryCharging),
      'batteryAtUtcMs': serializer.toJson<int?>(batteryAtUtcMs),
      'unpairedAtUtcMs': serializer.toJson<int?>(unpairedAtUtcMs),
      'autoHeartRate': serializer.toJson<bool>(autoHeartRate),
      'autoSpo2': serializer.toJson<bool>(autoSpo2),
      'autoStress': serializer.toJson<bool>(autoStress),
      'autoHrv': serializer.toJson<bool>(autoHrv),
    };
  }

  RingDeviceRow copyWith({
    String? deviceId,
    String? name,
    Value<String?> model = const Value.absent(),
    Value<String?> firmware = const Value.absent(),
    int? pairedAtUtcMs,
    Value<int?> lastSyncAtUtcMs = const Value.absent(),
    Value<int?> batteryPercent = const Value.absent(),
    Value<bool?> batteryCharging = const Value.absent(),
    Value<int?> batteryAtUtcMs = const Value.absent(),
    Value<int?> unpairedAtUtcMs = const Value.absent(),
    bool? autoHeartRate,
    bool? autoSpo2,
    bool? autoStress,
    bool? autoHrv,
  }) => RingDeviceRow(
    deviceId: deviceId ?? this.deviceId,
    name: name ?? this.name,
    model: model.present ? model.value : this.model,
    firmware: firmware.present ? firmware.value : this.firmware,
    pairedAtUtcMs: pairedAtUtcMs ?? this.pairedAtUtcMs,
    lastSyncAtUtcMs: lastSyncAtUtcMs.present
        ? lastSyncAtUtcMs.value
        : this.lastSyncAtUtcMs,
    batteryPercent: batteryPercent.present
        ? batteryPercent.value
        : this.batteryPercent,
    batteryCharging: batteryCharging.present
        ? batteryCharging.value
        : this.batteryCharging,
    batteryAtUtcMs: batteryAtUtcMs.present
        ? batteryAtUtcMs.value
        : this.batteryAtUtcMs,
    unpairedAtUtcMs: unpairedAtUtcMs.present
        ? unpairedAtUtcMs.value
        : this.unpairedAtUtcMs,
    autoHeartRate: autoHeartRate ?? this.autoHeartRate,
    autoSpo2: autoSpo2 ?? this.autoSpo2,
    autoStress: autoStress ?? this.autoStress,
    autoHrv: autoHrv ?? this.autoHrv,
  );
  RingDeviceRow copyWithCompanion(RingDevicesCompanion data) {
    return RingDeviceRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      name: data.name.present ? data.name.value : this.name,
      model: data.model.present ? data.model.value : this.model,
      firmware: data.firmware.present ? data.firmware.value : this.firmware,
      pairedAtUtcMs: data.pairedAtUtcMs.present
          ? data.pairedAtUtcMs.value
          : this.pairedAtUtcMs,
      lastSyncAtUtcMs: data.lastSyncAtUtcMs.present
          ? data.lastSyncAtUtcMs.value
          : this.lastSyncAtUtcMs,
      batteryPercent: data.batteryPercent.present
          ? data.batteryPercent.value
          : this.batteryPercent,
      batteryCharging: data.batteryCharging.present
          ? data.batteryCharging.value
          : this.batteryCharging,
      batteryAtUtcMs: data.batteryAtUtcMs.present
          ? data.batteryAtUtcMs.value
          : this.batteryAtUtcMs,
      unpairedAtUtcMs: data.unpairedAtUtcMs.present
          ? data.unpairedAtUtcMs.value
          : this.unpairedAtUtcMs,
      autoHeartRate: data.autoHeartRate.present
          ? data.autoHeartRate.value
          : this.autoHeartRate,
      autoSpo2: data.autoSpo2.present ? data.autoSpo2.value : this.autoSpo2,
      autoStress: data.autoStress.present
          ? data.autoStress.value
          : this.autoStress,
      autoHrv: data.autoHrv.present ? data.autoHrv.value : this.autoHrv,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RingDeviceRow(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('model: $model, ')
          ..write('firmware: $firmware, ')
          ..write('pairedAtUtcMs: $pairedAtUtcMs, ')
          ..write('lastSyncAtUtcMs: $lastSyncAtUtcMs, ')
          ..write('batteryPercent: $batteryPercent, ')
          ..write('batteryCharging: $batteryCharging, ')
          ..write('batteryAtUtcMs: $batteryAtUtcMs, ')
          ..write('unpairedAtUtcMs: $unpairedAtUtcMs, ')
          ..write('autoHeartRate: $autoHeartRate, ')
          ..write('autoSpo2: $autoSpo2, ')
          ..write('autoStress: $autoStress, ')
          ..write('autoHrv: $autoHrv')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    name,
    model,
    firmware,
    pairedAtUtcMs,
    lastSyncAtUtcMs,
    batteryPercent,
    batteryCharging,
    batteryAtUtcMs,
    unpairedAtUtcMs,
    autoHeartRate,
    autoSpo2,
    autoStress,
    autoHrv,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RingDeviceRow &&
          other.deviceId == this.deviceId &&
          other.name == this.name &&
          other.model == this.model &&
          other.firmware == this.firmware &&
          other.pairedAtUtcMs == this.pairedAtUtcMs &&
          other.lastSyncAtUtcMs == this.lastSyncAtUtcMs &&
          other.batteryPercent == this.batteryPercent &&
          other.batteryCharging == this.batteryCharging &&
          other.batteryAtUtcMs == this.batteryAtUtcMs &&
          other.unpairedAtUtcMs == this.unpairedAtUtcMs &&
          other.autoHeartRate == this.autoHeartRate &&
          other.autoSpo2 == this.autoSpo2 &&
          other.autoStress == this.autoStress &&
          other.autoHrv == this.autoHrv);
}

class RingDevicesCompanion extends UpdateCompanion<RingDeviceRow> {
  final Value<String> deviceId;
  final Value<String> name;
  final Value<String?> model;
  final Value<String?> firmware;
  final Value<int> pairedAtUtcMs;
  final Value<int?> lastSyncAtUtcMs;
  final Value<int?> batteryPercent;
  final Value<bool?> batteryCharging;
  final Value<int?> batteryAtUtcMs;
  final Value<int?> unpairedAtUtcMs;
  final Value<bool> autoHeartRate;
  final Value<bool> autoSpo2;
  final Value<bool> autoStress;
  final Value<bool> autoHrv;
  final Value<int> rowid;
  const RingDevicesCompanion({
    this.deviceId = const Value.absent(),
    this.name = const Value.absent(),
    this.model = const Value.absent(),
    this.firmware = const Value.absent(),
    this.pairedAtUtcMs = const Value.absent(),
    this.lastSyncAtUtcMs = const Value.absent(),
    this.batteryPercent = const Value.absent(),
    this.batteryCharging = const Value.absent(),
    this.batteryAtUtcMs = const Value.absent(),
    this.unpairedAtUtcMs = const Value.absent(),
    this.autoHeartRate = const Value.absent(),
    this.autoSpo2 = const Value.absent(),
    this.autoStress = const Value.absent(),
    this.autoHrv = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RingDevicesCompanion.insert({
    required String deviceId,
    required String name,
    this.model = const Value.absent(),
    this.firmware = const Value.absent(),
    required int pairedAtUtcMs,
    this.lastSyncAtUtcMs = const Value.absent(),
    this.batteryPercent = const Value.absent(),
    this.batteryCharging = const Value.absent(),
    this.batteryAtUtcMs = const Value.absent(),
    this.unpairedAtUtcMs = const Value.absent(),
    this.autoHeartRate = const Value.absent(),
    this.autoSpo2 = const Value.absent(),
    this.autoStress = const Value.absent(),
    this.autoHrv = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       name = Value(name),
       pairedAtUtcMs = Value(pairedAtUtcMs);
  static Insertable<RingDeviceRow> custom({
    Expression<String>? deviceId,
    Expression<String>? name,
    Expression<String>? model,
    Expression<String>? firmware,
    Expression<int>? pairedAtUtcMs,
    Expression<int>? lastSyncAtUtcMs,
    Expression<int>? batteryPercent,
    Expression<bool>? batteryCharging,
    Expression<int>? batteryAtUtcMs,
    Expression<int>? unpairedAtUtcMs,
    Expression<bool>? autoHeartRate,
    Expression<bool>? autoSpo2,
    Expression<bool>? autoStress,
    Expression<bool>? autoHrv,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (name != null) 'name': name,
      if (model != null) 'model': model,
      if (firmware != null) 'firmware': firmware,
      if (pairedAtUtcMs != null) 'paired_at_utc_ms': pairedAtUtcMs,
      if (lastSyncAtUtcMs != null) 'last_sync_at_utc_ms': lastSyncAtUtcMs,
      if (batteryPercent != null) 'battery_percent': batteryPercent,
      if (batteryCharging != null) 'battery_charging': batteryCharging,
      if (batteryAtUtcMs != null) 'battery_at_utc_ms': batteryAtUtcMs,
      if (unpairedAtUtcMs != null) 'unpaired_at_utc_ms': unpairedAtUtcMs,
      if (autoHeartRate != null) 'auto_heart_rate': autoHeartRate,
      if (autoSpo2 != null) 'auto_spo2': autoSpo2,
      if (autoStress != null) 'auto_stress': autoStress,
      if (autoHrv != null) 'auto_hrv': autoHrv,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RingDevicesCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? name,
    Value<String?>? model,
    Value<String?>? firmware,
    Value<int>? pairedAtUtcMs,
    Value<int?>? lastSyncAtUtcMs,
    Value<int?>? batteryPercent,
    Value<bool?>? batteryCharging,
    Value<int?>? batteryAtUtcMs,
    Value<int?>? unpairedAtUtcMs,
    Value<bool>? autoHeartRate,
    Value<bool>? autoSpo2,
    Value<bool>? autoStress,
    Value<bool>? autoHrv,
    Value<int>? rowid,
  }) {
    return RingDevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      model: model ?? this.model,
      firmware: firmware ?? this.firmware,
      pairedAtUtcMs: pairedAtUtcMs ?? this.pairedAtUtcMs,
      lastSyncAtUtcMs: lastSyncAtUtcMs ?? this.lastSyncAtUtcMs,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryCharging: batteryCharging ?? this.batteryCharging,
      batteryAtUtcMs: batteryAtUtcMs ?? this.batteryAtUtcMs,
      unpairedAtUtcMs: unpairedAtUtcMs ?? this.unpairedAtUtcMs,
      autoHeartRate: autoHeartRate ?? this.autoHeartRate,
      autoSpo2: autoSpo2 ?? this.autoSpo2,
      autoStress: autoStress ?? this.autoStress,
      autoHrv: autoHrv ?? this.autoHrv,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (firmware.present) {
      map['firmware'] = Variable<String>(firmware.value);
    }
    if (pairedAtUtcMs.present) {
      map['paired_at_utc_ms'] = Variable<int>(pairedAtUtcMs.value);
    }
    if (lastSyncAtUtcMs.present) {
      map['last_sync_at_utc_ms'] = Variable<int>(lastSyncAtUtcMs.value);
    }
    if (batteryPercent.present) {
      map['battery_percent'] = Variable<int>(batteryPercent.value);
    }
    if (batteryCharging.present) {
      map['battery_charging'] = Variable<bool>(batteryCharging.value);
    }
    if (batteryAtUtcMs.present) {
      map['battery_at_utc_ms'] = Variable<int>(batteryAtUtcMs.value);
    }
    if (unpairedAtUtcMs.present) {
      map['unpaired_at_utc_ms'] = Variable<int>(unpairedAtUtcMs.value);
    }
    if (autoHeartRate.present) {
      map['auto_heart_rate'] = Variable<bool>(autoHeartRate.value);
    }
    if (autoSpo2.present) {
      map['auto_spo2'] = Variable<bool>(autoSpo2.value);
    }
    if (autoStress.present) {
      map['auto_stress'] = Variable<bool>(autoStress.value);
    }
    if (autoHrv.present) {
      map['auto_hrv'] = Variable<bool>(autoHrv.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RingDevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('model: $model, ')
          ..write('firmware: $firmware, ')
          ..write('pairedAtUtcMs: $pairedAtUtcMs, ')
          ..write('lastSyncAtUtcMs: $lastSyncAtUtcMs, ')
          ..write('batteryPercent: $batteryPercent, ')
          ..write('batteryCharging: $batteryCharging, ')
          ..write('batteryAtUtcMs: $batteryAtUtcMs, ')
          ..write('unpairedAtUtcMs: $unpairedAtUtcMs, ')
          ..write('autoHeartRate: $autoHeartRate, ')
          ..write('autoSpo2: $autoSpo2, ')
          ..write('autoStress: $autoStress, ')
          ..write('autoHrv: $autoHrv, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<RecordKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RecordKind>($SyncCursorsTable.$converterkind);
  static const VerificationMeta _cursorUtcMsMeta = const VerificationMeta(
    'cursorUtcMs',
  );
  @override
  late final GeneratedColumn<int> cursorUtcMs = GeneratedColumn<int>(
    'cursor_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    kind,
    cursorUtcMs,
    updatedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('cursor_utc_ms')) {
      context.handle(
        _cursorUtcMsMeta,
        cursorUtcMs.isAcceptableOrUnknown(
          data['cursor_utc_ms']!,
          _cursorUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cursorUtcMsMeta);
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, kind};
  @override
  SyncCursorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursorRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      kind: $SyncCursorsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      cursorUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_utc_ms'],
      )!,
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RecordKind, String, String> $converterkind =
      const EnumNameConverter<RecordKind>(RecordKind.values);
}

class SyncCursorRow extends DataClass implements Insertable<SyncCursorRow> {
  final String deviceId;
  final RecordKind kind;
  final int cursorUtcMs;
  final int updatedAtUtcMs;
  const SyncCursorRow({
    required this.deviceId,
    required this.kind,
    required this.cursorUtcMs,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    {
      map['kind'] = Variable<String>(
        $SyncCursorsTable.$converterkind.toSql(kind),
      );
    }
    map['cursor_utc_ms'] = Variable<int>(cursorUtcMs);
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      deviceId: Value(deviceId),
      kind: Value(kind),
      cursorUtcMs: Value(cursorUtcMs),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory SyncCursorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursorRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      kind: $SyncCursorsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      cursorUtcMs: serializer.fromJson<int>(json['cursorUtcMs']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'kind': serializer.toJson<String>(
        $SyncCursorsTable.$converterkind.toJson(kind),
      ),
      'cursorUtcMs': serializer.toJson<int>(cursorUtcMs),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
    };
  }

  SyncCursorRow copyWith({
    String? deviceId,
    RecordKind? kind,
    int? cursorUtcMs,
    int? updatedAtUtcMs,
  }) => SyncCursorRow(
    deviceId: deviceId ?? this.deviceId,
    kind: kind ?? this.kind,
    cursorUtcMs: cursorUtcMs ?? this.cursorUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
  SyncCursorRow copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursorRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      cursorUtcMs: data.cursorUtcMs.present
          ? data.cursorUtcMs.value
          : this.cursorUtcMs,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorRow(')
          ..write('deviceId: $deviceId, ')
          ..write('kind: $kind, ')
          ..write('cursorUtcMs: $cursorUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, kind, cursorUtcMs, updatedAtUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursorRow &&
          other.deviceId == this.deviceId &&
          other.kind == this.kind &&
          other.cursorUtcMs == this.cursorUtcMs &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursorRow> {
  final Value<String> deviceId;
  final Value<RecordKind> kind;
  final Value<int> cursorUtcMs;
  final Value<int> updatedAtUtcMs;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.deviceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.cursorUtcMs = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String deviceId,
    required RecordKind kind,
    required int cursorUtcMs,
    required int updatedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       kind = Value(kind),
       cursorUtcMs = Value(cursorUtcMs),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<SyncCursorRow> custom({
    Expression<String>? deviceId,
    Expression<String>? kind,
    Expression<int>? cursorUtcMs,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (kind != null) 'kind': kind,
      if (cursorUtcMs != null) 'cursor_utc_ms': cursorUtcMs,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? deviceId,
    Value<RecordKind>? kind,
    Value<int>? cursorUtcMs,
    Value<int>? updatedAtUtcMs,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      deviceId: deviceId ?? this.deviceId,
      kind: kind ?? this.kind,
      cursorUtcMs: cursorUtcMs ?? this.cursorUtcMs,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $SyncCursorsTable.$converterkind.toSql(kind.value),
      );
    }
    if (cursorUtcMs.present) {
      map['cursor_utc_ms'] = Variable<int>(cursorUtcMs.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('kind: $kind, ')
          ..write('cursorUtcMs: $cursorUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncLocksTable extends SyncLocks
    with TableInfo<$SyncLocksTable, SyncLockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acquiredAtUtcMsMeta = const VerificationMeta(
    'acquiredAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> acquiredAtUtcMs = GeneratedColumn<int>(
    'acquired_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtUtcMsMeta = const VerificationMeta(
    'expiresAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtUtcMs = GeneratedColumn<int>(
    'expires_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    name,
    owner,
    acquiredAtUtcMs,
    expiresAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_locks';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncLockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('acquired_at_utc_ms')) {
      context.handle(
        _acquiredAtUtcMsMeta,
        acquiredAtUtcMs.isAcceptableOrUnknown(
          data['acquired_at_utc_ms']!,
          _acquiredAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acquiredAtUtcMsMeta);
    }
    if (data.containsKey('expires_at_utc_ms')) {
      context.handle(
        _expiresAtUtcMsMeta,
        expiresAtUtcMs.isAcceptableOrUnknown(
          data['expires_at_utc_ms']!,
          _expiresAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expiresAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  SyncLockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncLockRow(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      acquiredAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acquired_at_utc_ms'],
      )!,
      expiresAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_utc_ms'],
      )!,
    );
  }

  @override
  $SyncLocksTable createAlias(String alias) {
    return $SyncLocksTable(attachedDatabase, alias);
  }
}

class SyncLockRow extends DataClass implements Insertable<SyncLockRow> {
  final String name;
  final String owner;
  final int acquiredAtUtcMs;
  final int expiresAtUtcMs;
  const SyncLockRow({
    required this.name,
    required this.owner,
    required this.acquiredAtUtcMs,
    required this.expiresAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['owner'] = Variable<String>(owner);
    map['acquired_at_utc_ms'] = Variable<int>(acquiredAtUtcMs);
    map['expires_at_utc_ms'] = Variable<int>(expiresAtUtcMs);
    return map;
  }

  SyncLocksCompanion toCompanion(bool nullToAbsent) {
    return SyncLocksCompanion(
      name: Value(name),
      owner: Value(owner),
      acquiredAtUtcMs: Value(acquiredAtUtcMs),
      expiresAtUtcMs: Value(expiresAtUtcMs),
    );
  }

  factory SyncLockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncLockRow(
      name: serializer.fromJson<String>(json['name']),
      owner: serializer.fromJson<String>(json['owner']),
      acquiredAtUtcMs: serializer.fromJson<int>(json['acquiredAtUtcMs']),
      expiresAtUtcMs: serializer.fromJson<int>(json['expiresAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'owner': serializer.toJson<String>(owner),
      'acquiredAtUtcMs': serializer.toJson<int>(acquiredAtUtcMs),
      'expiresAtUtcMs': serializer.toJson<int>(expiresAtUtcMs),
    };
  }

  SyncLockRow copyWith({
    String? name,
    String? owner,
    int? acquiredAtUtcMs,
    int? expiresAtUtcMs,
  }) => SyncLockRow(
    name: name ?? this.name,
    owner: owner ?? this.owner,
    acquiredAtUtcMs: acquiredAtUtcMs ?? this.acquiredAtUtcMs,
    expiresAtUtcMs: expiresAtUtcMs ?? this.expiresAtUtcMs,
  );
  SyncLockRow copyWithCompanion(SyncLocksCompanion data) {
    return SyncLockRow(
      name: data.name.present ? data.name.value : this.name,
      owner: data.owner.present ? data.owner.value : this.owner,
      acquiredAtUtcMs: data.acquiredAtUtcMs.present
          ? data.acquiredAtUtcMs.value
          : this.acquiredAtUtcMs,
      expiresAtUtcMs: data.expiresAtUtcMs.present
          ? data.expiresAtUtcMs.value
          : this.expiresAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncLockRow(')
          ..write('name: $name, ')
          ..write('owner: $owner, ')
          ..write('acquiredAtUtcMs: $acquiredAtUtcMs, ')
          ..write('expiresAtUtcMs: $expiresAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, owner, acquiredAtUtcMs, expiresAtUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncLockRow &&
          other.name == this.name &&
          other.owner == this.owner &&
          other.acquiredAtUtcMs == this.acquiredAtUtcMs &&
          other.expiresAtUtcMs == this.expiresAtUtcMs);
}

class SyncLocksCompanion extends UpdateCompanion<SyncLockRow> {
  final Value<String> name;
  final Value<String> owner;
  final Value<int> acquiredAtUtcMs;
  final Value<int> expiresAtUtcMs;
  final Value<int> rowid;
  const SyncLocksCompanion({
    this.name = const Value.absent(),
    this.owner = const Value.absent(),
    this.acquiredAtUtcMs = const Value.absent(),
    this.expiresAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncLocksCompanion.insert({
    required String name,
    required String owner,
    required int acquiredAtUtcMs,
    required int expiresAtUtcMs,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       owner = Value(owner),
       acquiredAtUtcMs = Value(acquiredAtUtcMs),
       expiresAtUtcMs = Value(expiresAtUtcMs);
  static Insertable<SyncLockRow> custom({
    Expression<String>? name,
    Expression<String>? owner,
    Expression<int>? acquiredAtUtcMs,
    Expression<int>? expiresAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (owner != null) 'owner': owner,
      if (acquiredAtUtcMs != null) 'acquired_at_utc_ms': acquiredAtUtcMs,
      if (expiresAtUtcMs != null) 'expires_at_utc_ms': expiresAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncLocksCompanion copyWith({
    Value<String>? name,
    Value<String>? owner,
    Value<int>? acquiredAtUtcMs,
    Value<int>? expiresAtUtcMs,
    Value<int>? rowid,
  }) {
    return SyncLocksCompanion(
      name: name ?? this.name,
      owner: owner ?? this.owner,
      acquiredAtUtcMs: acquiredAtUtcMs ?? this.acquiredAtUtcMs,
      expiresAtUtcMs: expiresAtUtcMs ?? this.expiresAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (acquiredAtUtcMs.present) {
      map['acquired_at_utc_ms'] = Variable<int>(acquiredAtUtcMs.value);
    }
    if (expiresAtUtcMs.present) {
      map['expires_at_utc_ms'] = Variable<int>(expiresAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncLocksCompanion(')
          ..write('name: $name, ')
          ..write('owner: $owner, ')
          ..write('acquiredAtUtcMs: $acquiredAtUtcMs, ')
          ..write('expiresAtUtcMs: $expiresAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncRunsTable extends SyncRuns
    with TableInfo<$SyncRunsTable, SyncRunRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindsMeta = const VerificationMeta('kinds');
  @override
  late final GeneratedColumn<String> kinds = GeneratedColumn<String>(
    'kinds',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _recordCountMeta = const VerificationMeta(
    'recordCount',
  );
  @override
  late final GeneratedColumn<int> recordCount = GeneratedColumn<int>(
    'record_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    atUtcMs,
    outcome,
    kinds,
    recordCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncRunRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('kinds')) {
      context.handle(
        _kindsMeta,
        kinds.isAcceptableOrUnknown(data['kinds']!, _kindsMeta),
      );
    }
    if (data.containsKey('record_count')) {
      context.handle(
        _recordCountMeta,
        recordCount.isAcceptableOrUnknown(
          data['record_count']!,
          _recordCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncRunRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncRunRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      kinds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kinds'],
      )!,
      recordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}record_count'],
      )!,
    );
  }

  @override
  $SyncRunsTable createAlias(String alias) {
    return $SyncRunsTable(attachedDatabase, alias);
  }
}

class SyncRunRow extends DataClass implements Insertable<SyncRunRow> {
  final int id;
  final String deviceId;
  final int atUtcMs;
  final String outcome;
  final String kinds;
  final int recordCount;
  const SyncRunRow({
    required this.id,
    required this.deviceId,
    required this.atUtcMs,
    required this.outcome,
    required this.kinds,
    required this.recordCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['outcome'] = Variable<String>(outcome);
    map['kinds'] = Variable<String>(kinds);
    map['record_count'] = Variable<int>(recordCount);
    return map;
  }

  SyncRunsCompanion toCompanion(bool nullToAbsent) {
    return SyncRunsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      atUtcMs: Value(atUtcMs),
      outcome: Value(outcome),
      kinds: Value(kinds),
      recordCount: Value(recordCount),
    );
  }

  factory SyncRunRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncRunRow(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      outcome: serializer.fromJson<String>(json['outcome']),
      kinds: serializer.fromJson<String>(json['kinds']),
      recordCount: serializer.fromJson<int>(json['recordCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'outcome': serializer.toJson<String>(outcome),
      'kinds': serializer.toJson<String>(kinds),
      'recordCount': serializer.toJson<int>(recordCount),
    };
  }

  SyncRunRow copyWith({
    int? id,
    String? deviceId,
    int? atUtcMs,
    String? outcome,
    String? kinds,
    int? recordCount,
  }) => SyncRunRow(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    outcome: outcome ?? this.outcome,
    kinds: kinds ?? this.kinds,
    recordCount: recordCount ?? this.recordCount,
  );
  SyncRunRow copyWithCompanion(SyncRunsCompanion data) {
    return SyncRunRow(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      kinds: data.kinds.present ? data.kinds.value : this.kinds,
      recordCount: data.recordCount.present
          ? data.recordCount.value
          : this.recordCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncRunRow(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('outcome: $outcome, ')
          ..write('kinds: $kinds, ')
          ..write('recordCount: $recordCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, deviceId, atUtcMs, outcome, kinds, recordCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncRunRow &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.atUtcMs == this.atUtcMs &&
          other.outcome == this.outcome &&
          other.kinds == this.kinds &&
          other.recordCount == this.recordCount);
}

class SyncRunsCompanion extends UpdateCompanion<SyncRunRow> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<int> atUtcMs;
  final Value<String> outcome;
  final Value<String> kinds;
  final Value<int> recordCount;
  const SyncRunsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.outcome = const Value.absent(),
    this.kinds = const Value.absent(),
    this.recordCount = const Value.absent(),
  });
  SyncRunsCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    required int atUtcMs,
    required String outcome,
    this.kinds = const Value.absent(),
    this.recordCount = const Value.absent(),
  }) : deviceId = Value(deviceId),
       atUtcMs = Value(atUtcMs),
       outcome = Value(outcome);
  static Insertable<SyncRunRow> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<int>? atUtcMs,
    Expression<String>? outcome,
    Expression<String>? kinds,
    Expression<int>? recordCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (outcome != null) 'outcome': outcome,
      if (kinds != null) 'kinds': kinds,
      if (recordCount != null) 'record_count': recordCount,
    });
  }

  SyncRunsCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceId,
    Value<int>? atUtcMs,
    Value<String>? outcome,
    Value<String>? kinds,
    Value<int>? recordCount,
  }) {
    return SyncRunsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      outcome: outcome ?? this.outcome,
      kinds: kinds ?? this.kinds,
      recordCount: recordCount ?? this.recordCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (kinds.present) {
      map['kinds'] = Variable<String>(kinds.value);
    }
    if (recordCount.present) {
      map['record_count'] = Variable<int>(recordCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncRunsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('outcome: $outcome, ')
          ..write('kinds: $kinds, ')
          ..write('recordCount: $recordCount')
          ..write(')'))
        .toString();
  }
}

class $ActivityBucketsTable extends ActivityBuckets
    with TableInfo<$ActivityBucketsTable, ActivityBucketRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityBucketsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<int> steps = GeneratedColumn<int>(
    'steps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<int> distanceMeters = GeneratedColumn<int>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeKilocaloriesMeta =
      const VerificationMeta('activeKilocalories');
  @override
  late final GeneratedColumn<double> activeKilocalories =
      GeneratedColumn<double>(
        'active_kilocalories',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    startUtcMs,
    offsetMinutes,
    durationSeconds,
    steps,
    distanceMeters,
    activeKilocalories,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_buckets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityBucketRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    } else if (isInserting) {
      context.missing(_stepsMeta);
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distanceMetersMeta);
    }
    if (data.containsKey('active_kilocalories')) {
      context.handle(
        _activeKilocaloriesMeta,
        activeKilocalories.isAcceptableOrUnknown(
          data['active_kilocalories']!,
          _activeKilocaloriesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activeKilocaloriesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, startUtcMs};
  @override
  ActivityBucketRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityBucketRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}steps'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_meters'],
      )!,
      activeKilocalories: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}active_kilocalories'],
      )!,
    );
  }

  @override
  $ActivityBucketsTable createAlias(String alias) {
    return $ActivityBucketsTable(attachedDatabase, alias);
  }
}

class ActivityBucketRow extends DataClass
    implements Insertable<ActivityBucketRow> {
  final String deviceId;
  final int startUtcMs;
  final int offsetMinutes;
  final int durationSeconds;
  final int steps;
  final int distanceMeters;
  final double activeKilocalories;
  const ActivityBucketRow({
    required this.deviceId,
    required this.startUtcMs,
    required this.offsetMinutes,
    required this.durationSeconds,
    required this.steps,
    required this.distanceMeters,
    required this.activeKilocalories,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['steps'] = Variable<int>(steps);
    map['distance_meters'] = Variable<int>(distanceMeters);
    map['active_kilocalories'] = Variable<double>(activeKilocalories);
    return map;
  }

  ActivityBucketsCompanion toCompanion(bool nullToAbsent) {
    return ActivityBucketsCompanion(
      deviceId: Value(deviceId),
      startUtcMs: Value(startUtcMs),
      offsetMinutes: Value(offsetMinutes),
      durationSeconds: Value(durationSeconds),
      steps: Value(steps),
      distanceMeters: Value(distanceMeters),
      activeKilocalories: Value(activeKilocalories),
    );
  }

  factory ActivityBucketRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityBucketRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      steps: serializer.fromJson<int>(json['steps']),
      distanceMeters: serializer.fromJson<int>(json['distanceMeters']),
      activeKilocalories: serializer.fromJson<double>(
        json['activeKilocalories'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'steps': serializer.toJson<int>(steps),
      'distanceMeters': serializer.toJson<int>(distanceMeters),
      'activeKilocalories': serializer.toJson<double>(activeKilocalories),
    };
  }

  ActivityBucketRow copyWith({
    String? deviceId,
    int? startUtcMs,
    int? offsetMinutes,
    int? durationSeconds,
    int? steps,
    int? distanceMeters,
    double? activeKilocalories,
  }) => ActivityBucketRow(
    deviceId: deviceId ?? this.deviceId,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    steps: steps ?? this.steps,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    activeKilocalories: activeKilocalories ?? this.activeKilocalories,
  );
  ActivityBucketRow copyWithCompanion(ActivityBucketsCompanion data) {
    return ActivityBucketRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      steps: data.steps.present ? data.steps.value : this.steps,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      activeKilocalories: data.activeKilocalories.present
          ? data.activeKilocalories.value
          : this.activeKilocalories,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityBucketRow(')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('steps: $steps, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('activeKilocalories: $activeKilocalories')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    startUtcMs,
    offsetMinutes,
    durationSeconds,
    steps,
    distanceMeters,
    activeKilocalories,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityBucketRow &&
          other.deviceId == this.deviceId &&
          other.startUtcMs == this.startUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.durationSeconds == this.durationSeconds &&
          other.steps == this.steps &&
          other.distanceMeters == this.distanceMeters &&
          other.activeKilocalories == this.activeKilocalories);
}

class ActivityBucketsCompanion extends UpdateCompanion<ActivityBucketRow> {
  final Value<String> deviceId;
  final Value<int> startUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> durationSeconds;
  final Value<int> steps;
  final Value<int> distanceMeters;
  final Value<double> activeKilocalories;
  final Value<int> rowid;
  const ActivityBucketsCompanion({
    this.deviceId = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.steps = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.activeKilocalories = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivityBucketsCompanion.insert({
    required String deviceId,
    required int startUtcMs,
    required int offsetMinutes,
    required int durationSeconds,
    required int steps,
    required int distanceMeters,
    required double activeKilocalories,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       startUtcMs = Value(startUtcMs),
       offsetMinutes = Value(offsetMinutes),
       durationSeconds = Value(durationSeconds),
       steps = Value(steps),
       distanceMeters = Value(distanceMeters),
       activeKilocalories = Value(activeKilocalories);
  static Insertable<ActivityBucketRow> custom({
    Expression<String>? deviceId,
    Expression<int>? startUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? durationSeconds,
    Expression<int>? steps,
    Expression<int>? distanceMeters,
    Expression<double>? activeKilocalories,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (steps != null) 'steps': steps,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (activeKilocalories != null) 'active_kilocalories': activeKilocalories,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivityBucketsCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? startUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? durationSeconds,
    Value<int>? steps,
    Value<int>? distanceMeters,
    Value<double>? activeKilocalories,
    Value<int>? rowid,
  }) {
    return ActivityBucketsCompanion(
      deviceId: deviceId ?? this.deviceId,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      steps: steps ?? this.steps,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      activeKilocalories: activeKilocalories ?? this.activeKilocalories,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (steps.present) {
      map['steps'] = Variable<int>(steps.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<int>(distanceMeters.value);
    }
    if (activeKilocalories.present) {
      map['active_kilocalories'] = Variable<double>(activeKilocalories.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityBucketsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('steps: $steps, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('activeKilocalories: $activeKilocalories, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HrSamplesTable extends HrSamples
    with TableInfo<$HrSamplesTable, HrSampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HrSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<int> bpm = GeneratedColumn<int>(
    'bpm',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [deviceId, atUtcMs, offsetMinutes, bpm];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hr_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<HrSampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('bpm')) {
      context.handle(
        _bpmMeta,
        bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta),
      );
    } else if (isInserting) {
      context.missing(_bpmMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, atUtcMs};
  @override
  HrSampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HrSampleRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      bpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bpm'],
      )!,
    );
  }

  @override
  $HrSamplesTable createAlias(String alias) {
    return $HrSamplesTable(attachedDatabase, alias);
  }
}

class HrSampleRow extends DataClass implements Insertable<HrSampleRow> {
  final String deviceId;
  final int atUtcMs;
  final int offsetMinutes;
  final int bpm;
  const HrSampleRow({
    required this.deviceId,
    required this.atUtcMs,
    required this.offsetMinutes,
    required this.bpm,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['bpm'] = Variable<int>(bpm);
    return map;
  }

  HrSamplesCompanion toCompanion(bool nullToAbsent) {
    return HrSamplesCompanion(
      deviceId: Value(deviceId),
      atUtcMs: Value(atUtcMs),
      offsetMinutes: Value(offsetMinutes),
      bpm: Value(bpm),
    );
  }

  factory HrSampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HrSampleRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      bpm: serializer.fromJson<int>(json['bpm']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'bpm': serializer.toJson<int>(bpm),
    };
  }

  HrSampleRow copyWith({
    String? deviceId,
    int? atUtcMs,
    int? offsetMinutes,
    int? bpm,
  }) => HrSampleRow(
    deviceId: deviceId ?? this.deviceId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    bpm: bpm ?? this.bpm,
  );
  HrSampleRow copyWithCompanion(HrSamplesCompanion data) {
    return HrSampleRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HrSampleRow(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('bpm: $bpm')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, atUtcMs, offsetMinutes, bpm);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HrSampleRow &&
          other.deviceId == this.deviceId &&
          other.atUtcMs == this.atUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.bpm == this.bpm);
}

class HrSamplesCompanion extends UpdateCompanion<HrSampleRow> {
  final Value<String> deviceId;
  final Value<int> atUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> bpm;
  final Value<int> rowid;
  const HrSamplesCompanion({
    this.deviceId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.bpm = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HrSamplesCompanion.insert({
    required String deviceId,
    required int atUtcMs,
    required int offsetMinutes,
    required int bpm,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       atUtcMs = Value(atUtcMs),
       offsetMinutes = Value(offsetMinutes),
       bpm = Value(bpm);
  static Insertable<HrSampleRow> custom({
    Expression<String>? deviceId,
    Expression<int>? atUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? bpm,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (bpm != null) 'bpm': bpm,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HrSamplesCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? atUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? bpm,
    Value<int>? rowid,
  }) {
    return HrSamplesCompanion(
      deviceId: deviceId ?? this.deviceId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      bpm: bpm ?? this.bpm,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<int>(bpm.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HrSamplesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('bpm: $bpm, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Spo2SamplesTable extends Spo2Samples
    with TableInfo<$Spo2SamplesTable, Spo2SampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Spo2SamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _percentMeta = const VerificationMeta(
    'percent',
  );
  @override
  late final GeneratedColumn<int> percent = GeneratedColumn<int>(
    'percent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    atUtcMs,
    offsetMinutes,
    percent,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'spo2_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<Spo2SampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('percent')) {
      context.handle(
        _percentMeta,
        percent.isAcceptableOrUnknown(data['percent']!, _percentMeta),
      );
    } else if (isInserting) {
      context.missing(_percentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, atUtcMs};
  @override
  Spo2SampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Spo2SampleRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      percent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}percent'],
      )!,
    );
  }

  @override
  $Spo2SamplesTable createAlias(String alias) {
    return $Spo2SamplesTable(attachedDatabase, alias);
  }
}

class Spo2SampleRow extends DataClass implements Insertable<Spo2SampleRow> {
  final String deviceId;
  final int atUtcMs;
  final int offsetMinutes;
  final int percent;
  const Spo2SampleRow({
    required this.deviceId,
    required this.atUtcMs,
    required this.offsetMinutes,
    required this.percent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['percent'] = Variable<int>(percent);
    return map;
  }

  Spo2SamplesCompanion toCompanion(bool nullToAbsent) {
    return Spo2SamplesCompanion(
      deviceId: Value(deviceId),
      atUtcMs: Value(atUtcMs),
      offsetMinutes: Value(offsetMinutes),
      percent: Value(percent),
    );
  }

  factory Spo2SampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Spo2SampleRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      percent: serializer.fromJson<int>(json['percent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'percent': serializer.toJson<int>(percent),
    };
  }

  Spo2SampleRow copyWith({
    String? deviceId,
    int? atUtcMs,
    int? offsetMinutes,
    int? percent,
  }) => Spo2SampleRow(
    deviceId: deviceId ?? this.deviceId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    percent: percent ?? this.percent,
  );
  Spo2SampleRow copyWithCompanion(Spo2SamplesCompanion data) {
    return Spo2SampleRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      percent: data.percent.present ? data.percent.value : this.percent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Spo2SampleRow(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('percent: $percent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, atUtcMs, offsetMinutes, percent);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Spo2SampleRow &&
          other.deviceId == this.deviceId &&
          other.atUtcMs == this.atUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.percent == this.percent);
}

class Spo2SamplesCompanion extends UpdateCompanion<Spo2SampleRow> {
  final Value<String> deviceId;
  final Value<int> atUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> percent;
  final Value<int> rowid;
  const Spo2SamplesCompanion({
    this.deviceId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.percent = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Spo2SamplesCompanion.insert({
    required String deviceId,
    required int atUtcMs,
    required int offsetMinutes,
    required int percent,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       atUtcMs = Value(atUtcMs),
       offsetMinutes = Value(offsetMinutes),
       percent = Value(percent);
  static Insertable<Spo2SampleRow> custom({
    Expression<String>? deviceId,
    Expression<int>? atUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? percent,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (percent != null) 'percent': percent,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Spo2SamplesCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? atUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? percent,
    Value<int>? rowid,
  }) {
    return Spo2SamplesCompanion(
      deviceId: deviceId ?? this.deviceId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      percent: percent ?? this.percent,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (percent.present) {
      map['percent'] = Variable<int>(percent.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Spo2SamplesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('percent: $percent, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StressSamplesTable extends StressSamples
    with TableInfo<$StressSamplesTable, StressSampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StressSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    atUtcMs,
    offsetMinutes,
    level,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stress_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<StressSampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, atUtcMs};
  @override
  StressSampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StressSampleRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
    );
  }

  @override
  $StressSamplesTable createAlias(String alias) {
    return $StressSamplesTable(attachedDatabase, alias);
  }
}

class StressSampleRow extends DataClass implements Insertable<StressSampleRow> {
  final String deviceId;
  final int atUtcMs;
  final int offsetMinutes;
  final int level;
  const StressSampleRow({
    required this.deviceId,
    required this.atUtcMs,
    required this.offsetMinutes,
    required this.level,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['level'] = Variable<int>(level);
    return map;
  }

  StressSamplesCompanion toCompanion(bool nullToAbsent) {
    return StressSamplesCompanion(
      deviceId: Value(deviceId),
      atUtcMs: Value(atUtcMs),
      offsetMinutes: Value(offsetMinutes),
      level: Value(level),
    );
  }

  factory StressSampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StressSampleRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      level: serializer.fromJson<int>(json['level']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'level': serializer.toJson<int>(level),
    };
  }

  StressSampleRow copyWith({
    String? deviceId,
    int? atUtcMs,
    int? offsetMinutes,
    int? level,
  }) => StressSampleRow(
    deviceId: deviceId ?? this.deviceId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    level: level ?? this.level,
  );
  StressSampleRow copyWithCompanion(StressSamplesCompanion data) {
    return StressSampleRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      level: data.level.present ? data.level.value : this.level,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StressSampleRow(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('level: $level')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, atUtcMs, offsetMinutes, level);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StressSampleRow &&
          other.deviceId == this.deviceId &&
          other.atUtcMs == this.atUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.level == this.level);
}

class StressSamplesCompanion extends UpdateCompanion<StressSampleRow> {
  final Value<String> deviceId;
  final Value<int> atUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> level;
  final Value<int> rowid;
  const StressSamplesCompanion({
    this.deviceId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.level = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StressSamplesCompanion.insert({
    required String deviceId,
    required int atUtcMs,
    required int offsetMinutes,
    required int level,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       atUtcMs = Value(atUtcMs),
       offsetMinutes = Value(offsetMinutes),
       level = Value(level);
  static Insertable<StressSampleRow> custom({
    Expression<String>? deviceId,
    Expression<int>? atUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? level,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (level != null) 'level': level,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StressSamplesCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? atUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? level,
    Value<int>? rowid,
  }) {
    return StressSamplesCompanion(
      deviceId: deviceId ?? this.deviceId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      level: level ?? this.level,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StressSamplesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('level: $level, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HrvSamplesTable extends HrvSamples
    with TableInfo<$HrvSamplesTable, HrvSampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HrvSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _millisecondsMeta = const VerificationMeta(
    'milliseconds',
  );
  @override
  late final GeneratedColumn<int> milliseconds = GeneratedColumn<int>(
    'milliseconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    atUtcMs,
    offsetMinutes,
    milliseconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hrv_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<HrvSampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('milliseconds')) {
      context.handle(
        _millisecondsMeta,
        milliseconds.isAcceptableOrUnknown(
          data['milliseconds']!,
          _millisecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_millisecondsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, atUtcMs};
  @override
  HrvSampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HrvSampleRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      milliseconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}milliseconds'],
      )!,
    );
  }

  @override
  $HrvSamplesTable createAlias(String alias) {
    return $HrvSamplesTable(attachedDatabase, alias);
  }
}

class HrvSampleRow extends DataClass implements Insertable<HrvSampleRow> {
  final String deviceId;
  final int atUtcMs;
  final int offsetMinutes;
  final int milliseconds;
  const HrvSampleRow({
    required this.deviceId,
    required this.atUtcMs,
    required this.offsetMinutes,
    required this.milliseconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['milliseconds'] = Variable<int>(milliseconds);
    return map;
  }

  HrvSamplesCompanion toCompanion(bool nullToAbsent) {
    return HrvSamplesCompanion(
      deviceId: Value(deviceId),
      atUtcMs: Value(atUtcMs),
      offsetMinutes: Value(offsetMinutes),
      milliseconds: Value(milliseconds),
    );
  }

  factory HrvSampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HrvSampleRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      milliseconds: serializer.fromJson<int>(json['milliseconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'milliseconds': serializer.toJson<int>(milliseconds),
    };
  }

  HrvSampleRow copyWith({
    String? deviceId,
    int? atUtcMs,
    int? offsetMinutes,
    int? milliseconds,
  }) => HrvSampleRow(
    deviceId: deviceId ?? this.deviceId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    milliseconds: milliseconds ?? this.milliseconds,
  );
  HrvSampleRow copyWithCompanion(HrvSamplesCompanion data) {
    return HrvSampleRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      milliseconds: data.milliseconds.present
          ? data.milliseconds.value
          : this.milliseconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HrvSampleRow(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('milliseconds: $milliseconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(deviceId, atUtcMs, offsetMinutes, milliseconds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HrvSampleRow &&
          other.deviceId == this.deviceId &&
          other.atUtcMs == this.atUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.milliseconds == this.milliseconds);
}

class HrvSamplesCompanion extends UpdateCompanion<HrvSampleRow> {
  final Value<String> deviceId;
  final Value<int> atUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> milliseconds;
  final Value<int> rowid;
  const HrvSamplesCompanion({
    this.deviceId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.milliseconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HrvSamplesCompanion.insert({
    required String deviceId,
    required int atUtcMs,
    required int offsetMinutes,
    required int milliseconds,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       atUtcMs = Value(atUtcMs),
       offsetMinutes = Value(offsetMinutes),
       milliseconds = Value(milliseconds);
  static Insertable<HrvSampleRow> custom({
    Expression<String>? deviceId,
    Expression<int>? atUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? milliseconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (milliseconds != null) 'milliseconds': milliseconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HrvSamplesCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? atUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? milliseconds,
    Value<int>? rowid,
  }) {
    return HrvSamplesCompanion(
      deviceId: deviceId ?? this.deviceId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      milliseconds: milliseconds ?? this.milliseconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (milliseconds.present) {
      map['milliseconds'] = Variable<int>(milliseconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HrvSamplesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('milliseconds: $milliseconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SleepSessionsTable extends SleepSessions
    with TableInfo<$SleepSessionsTable, SleepSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SleepSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sleep_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SleepSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, startUtcMs};
  @override
  SleepSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SleepSessionRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
    );
  }

  @override
  $SleepSessionsTable createAlias(String alias) {
    return $SleepSessionsTable(attachedDatabase, alias);
  }
}

class SleepSessionRow extends DataClass implements Insertable<SleepSessionRow> {
  final String deviceId;
  final int startUtcMs;
  final int endUtcMs;
  final int offsetMinutes;
  const SleepSessionRow({
    required this.deviceId,
    required this.startUtcMs,
    required this.endUtcMs,
    required this.offsetMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    return map;
  }

  SleepSessionsCompanion toCompanion(bool nullToAbsent) {
    return SleepSessionsCompanion(
      deviceId: Value(deviceId),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
      offsetMinutes: Value(offsetMinutes),
    );
  }

  factory SleepSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SleepSessionRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
    };
  }

  SleepSessionRow copyWith({
    String? deviceId,
    int? startUtcMs,
    int? endUtcMs,
    int? offsetMinutes,
  }) => SleepSessionRow(
    deviceId: deviceId ?? this.deviceId,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
  );
  SleepSessionRow copyWithCompanion(SleepSessionsCompanion data) {
    return SleepSessionRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SleepSessionRow(')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(deviceId, startUtcMs, endUtcMs, offsetMinutes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SleepSessionRow &&
          other.deviceId == this.deviceId &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.offsetMinutes == this.offsetMinutes);
}

class SleepSessionsCompanion extends UpdateCompanion<SleepSessionRow> {
  final Value<String> deviceId;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> rowid;
  const SleepSessionsCompanion({
    this.deviceId = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SleepSessionsCompanion.insert({
    required String deviceId,
    required int startUtcMs,
    required int endUtcMs,
    required int offsetMinutes,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs),
       offsetMinutes = Value(offsetMinutes);
  static Insertable<SleepSessionRow> custom({
    Expression<String>? deviceId,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SleepSessionsCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? rowid,
  }) {
    return SleepSessionsCompanion(
      deviceId: deviceId ?? this.deviceId,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SleepSessionsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SleepSegmentsTable extends SleepSegments
    with TableInfo<$SleepSegmentsTable, SleepSegmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SleepSegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ring_devices (device_id)',
    ),
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SleepStage, String> stage =
      GeneratedColumn<String>(
        'stage',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SleepStage>($SleepSegmentsTable.$converterstage);
  static const VerificationMeta _sessionStartUtcMsMeta = const VerificationMeta(
    'sessionStartUtcMs',
  );
  @override
  late final GeneratedColumn<int> sessionStartUtcMs = GeneratedColumn<int>(
    'session_start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    stage,
    sessionStartUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sleep_segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<SleepSegmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('session_start_utc_ms')) {
      context.handle(
        _sessionStartUtcMsMeta,
        sessionStartUtcMs.isAcceptableOrUnknown(
          data['session_start_utc_ms']!,
          _sessionStartUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionStartUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, startUtcMs};
  @override
  SleepSegmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SleepSegmentRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      stage: $SleepSegmentsTable.$converterstage.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}stage'],
        )!,
      ),
      sessionStartUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_start_utc_ms'],
      )!,
    );
  }

  @override
  $SleepSegmentsTable createAlias(String alias) {
    return $SleepSegmentsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SleepStage, String, String> $converterstage =
      const EnumNameConverter<SleepStage>(SleepStage.values);
}

class SleepSegmentRow extends DataClass implements Insertable<SleepSegmentRow> {
  final String deviceId;
  final int startUtcMs;
  final int endUtcMs;
  final int offsetMinutes;
  final SleepStage stage;
  final int sessionStartUtcMs;
  const SleepSegmentRow({
    required this.deviceId,
    required this.startUtcMs,
    required this.endUtcMs,
    required this.offsetMinutes,
    required this.stage,
    required this.sessionStartUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    {
      map['stage'] = Variable<String>(
        $SleepSegmentsTable.$converterstage.toSql(stage),
      );
    }
    map['session_start_utc_ms'] = Variable<int>(sessionStartUtcMs);
    return map;
  }

  SleepSegmentsCompanion toCompanion(bool nullToAbsent) {
    return SleepSegmentsCompanion(
      deviceId: Value(deviceId),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
      offsetMinutes: Value(offsetMinutes),
      stage: Value(stage),
      sessionStartUtcMs: Value(sessionStartUtcMs),
    );
  }

  factory SleepSegmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SleepSegmentRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      stage: $SleepSegmentsTable.$converterstage.fromJson(
        serializer.fromJson<String>(json['stage']),
      ),
      sessionStartUtcMs: serializer.fromJson<int>(json['sessionStartUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'stage': serializer.toJson<String>(
        $SleepSegmentsTable.$converterstage.toJson(stage),
      ),
      'sessionStartUtcMs': serializer.toJson<int>(sessionStartUtcMs),
    };
  }

  SleepSegmentRow copyWith({
    String? deviceId,
    int? startUtcMs,
    int? endUtcMs,
    int? offsetMinutes,
    SleepStage? stage,
    int? sessionStartUtcMs,
  }) => SleepSegmentRow(
    deviceId: deviceId ?? this.deviceId,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    stage: stage ?? this.stage,
    sessionStartUtcMs: sessionStartUtcMs ?? this.sessionStartUtcMs,
  );
  SleepSegmentRow copyWithCompanion(SleepSegmentsCompanion data) {
    return SleepSegmentRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      stage: data.stage.present ? data.stage.value : this.stage,
      sessionStartUtcMs: data.sessionStartUtcMs.present
          ? data.sessionStartUtcMs.value
          : this.sessionStartUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SleepSegmentRow(')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('stage: $stage, ')
          ..write('sessionStartUtcMs: $sessionStartUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    stage,
    sessionStartUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SleepSegmentRow &&
          other.deviceId == this.deviceId &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.stage == this.stage &&
          other.sessionStartUtcMs == this.sessionStartUtcMs);
}

class SleepSegmentsCompanion extends UpdateCompanion<SleepSegmentRow> {
  final Value<String> deviceId;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<int> offsetMinutes;
  final Value<SleepStage> stage;
  final Value<int> sessionStartUtcMs;
  final Value<int> rowid;
  const SleepSegmentsCompanion({
    this.deviceId = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.stage = const Value.absent(),
    this.sessionStartUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SleepSegmentsCompanion.insert({
    required String deviceId,
    required int startUtcMs,
    required int endUtcMs,
    required int offsetMinutes,
    required SleepStage stage,
    required int sessionStartUtcMs,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs),
       offsetMinutes = Value(offsetMinutes),
       stage = Value(stage),
       sessionStartUtcMs = Value(sessionStartUtcMs);
  static Insertable<SleepSegmentRow> custom({
    Expression<String>? deviceId,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<int>? offsetMinutes,
    Expression<String>? stage,
    Expression<int>? sessionStartUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (stage != null) 'stage': stage,
      if (sessionStartUtcMs != null) 'session_start_utc_ms': sessionStartUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SleepSegmentsCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<int>? offsetMinutes,
    Value<SleepStage>? stage,
    Value<int>? sessionStartUtcMs,
    Value<int>? rowid,
  }) {
    return SleepSegmentsCompanion(
      deviceId: deviceId ?? this.deviceId,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      stage: stage ?? this.stage,
      sessionStartUtcMs: sessionStartUtcMs ?? this.sessionStartUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(
        $SleepSegmentsTable.$converterstage.toSql(stage.value),
      );
    }
    if (sessionStartUtcMs.present) {
      map['session_start_utc_ms'] = Variable<int>(sessionStartUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SleepSegmentsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('stage: $stage, ')
          ..write('sessionStartUtcMs: $sessionStartUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutsTable extends Workouts
    with TableInfo<$WorkoutsTable, WorkoutRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _activityTypeMeta = const VerificationMeta(
    'activityType',
  );
  @override
  late final GeneratedColumn<String> activityType = GeneratedColumn<String>(
    'activity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<double> distanceMeters = GeneratedColumn<double>(
    'distance_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeKilocaloriesMeta =
      const VerificationMeta('activeKilocalories');
  @override
  late final GeneratedColumn<double> activeKilocalories =
      GeneratedColumn<double>(
        'active_kilocalories',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _elapsedMsMeta = const VerificationMeta(
    'elapsedMs',
  );
  @override
  late final GeneratedColumn<int> elapsedMs = GeneratedColumn<int>(
    'elapsed_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _averageHeartRateMeta = const VerificationMeta(
    'averageHeartRate',
  );
  @override
  late final GeneratedColumn<int> averageHeartRate = GeneratedColumn<int>(
    'average_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxHeartRateMeta = const VerificationMeta(
    'maxHeartRate',
  );
  @override
  late final GeneratedColumn<int> maxHeartRate = GeneratedColumn<int>(
    'max_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientId,
    activityType,
    deviceId,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    distanceMeters,
    activeKilocalories,
    elapsedMs,
    averageHeartRate,
    maxHeartRate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('activity_type')) {
      context.handle(
        _activityTypeMeta,
        activityType.isAcceptableOrUnknown(
          data['activity_type']!,
          _activityTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityTypeMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    }
    if (data.containsKey('active_kilocalories')) {
      context.handle(
        _activeKilocaloriesMeta,
        activeKilocalories.isAcceptableOrUnknown(
          data['active_kilocalories']!,
          _activeKilocaloriesMeta,
        ),
      );
    }
    if (data.containsKey('elapsed_ms')) {
      context.handle(
        _elapsedMsMeta,
        elapsedMs.isAcceptableOrUnknown(data['elapsed_ms']!, _elapsedMsMeta),
      );
    }
    if (data.containsKey('average_heart_rate')) {
      context.handle(
        _averageHeartRateMeta,
        averageHeartRate.isAcceptableOrUnknown(
          data['average_heart_rate']!,
          _averageHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('max_heart_rate')) {
      context.handle(
        _maxHeartRateMeta,
        maxHeartRate.isAcceptableOrUnknown(
          data['max_heart_rate']!,
          _maxHeartRateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkoutRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      activityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_type'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      ),
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_meters'],
      ),
      activeKilocalories: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}active_kilocalories'],
      ),
      elapsedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_ms'],
      ),
      averageHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}average_heart_rate'],
      ),
      maxHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_heart_rate'],
      ),
    );
  }

  @override
  $WorkoutsTable createAlias(String alias) {
    return $WorkoutsTable(attachedDatabase, alias);
  }
}

class WorkoutRow extends DataClass implements Insertable<WorkoutRow> {
  final int id;
  final String clientId;
  final String activityType;
  final String? deviceId;
  final int startUtcMs;
  final int? endUtcMs;
  final int offsetMinutes;
  final double? distanceMeters;
  final double? activeKilocalories;
  final int? elapsedMs;
  final int? averageHeartRate;
  final int? maxHeartRate;
  const WorkoutRow({
    required this.id,
    required this.clientId,
    required this.activityType,
    this.deviceId,
    required this.startUtcMs,
    this.endUtcMs,
    required this.offsetMinutes,
    this.distanceMeters,
    this.activeKilocalories,
    this.elapsedMs,
    this.averageHeartRate,
    this.maxHeartRate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['client_id'] = Variable<String>(clientId);
    map['activity_type'] = Variable<String>(activityType);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    if (!nullToAbsent || endUtcMs != null) {
      map['end_utc_ms'] = Variable<int>(endUtcMs);
    }
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    if (!nullToAbsent || distanceMeters != null) {
      map['distance_meters'] = Variable<double>(distanceMeters);
    }
    if (!nullToAbsent || activeKilocalories != null) {
      map['active_kilocalories'] = Variable<double>(activeKilocalories);
    }
    if (!nullToAbsent || elapsedMs != null) {
      map['elapsed_ms'] = Variable<int>(elapsedMs);
    }
    if (!nullToAbsent || averageHeartRate != null) {
      map['average_heart_rate'] = Variable<int>(averageHeartRate);
    }
    if (!nullToAbsent || maxHeartRate != null) {
      map['max_heart_rate'] = Variable<int>(maxHeartRate);
    }
    return map;
  }

  WorkoutsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutsCompanion(
      id: Value(id),
      clientId: Value(clientId),
      activityType: Value(activityType),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      startUtcMs: Value(startUtcMs),
      endUtcMs: endUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endUtcMs),
      offsetMinutes: Value(offsetMinutes),
      distanceMeters: distanceMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(distanceMeters),
      activeKilocalories: activeKilocalories == null && nullToAbsent
          ? const Value.absent()
          : Value(activeKilocalories),
      elapsedMs: elapsedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(elapsedMs),
      averageHeartRate: averageHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(averageHeartRate),
      maxHeartRate: maxHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(maxHeartRate),
    );
  }

  factory WorkoutRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutRow(
      id: serializer.fromJson<int>(json['id']),
      clientId: serializer.fromJson<String>(json['clientId']),
      activityType: serializer.fromJson<String>(json['activityType']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int?>(json['endUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      distanceMeters: serializer.fromJson<double?>(json['distanceMeters']),
      activeKilocalories: serializer.fromJson<double?>(
        json['activeKilocalories'],
      ),
      elapsedMs: serializer.fromJson<int?>(json['elapsedMs']),
      averageHeartRate: serializer.fromJson<int?>(json['averageHeartRate']),
      maxHeartRate: serializer.fromJson<int?>(json['maxHeartRate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'clientId': serializer.toJson<String>(clientId),
      'activityType': serializer.toJson<String>(activityType),
      'deviceId': serializer.toJson<String?>(deviceId),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int?>(endUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'distanceMeters': serializer.toJson<double?>(distanceMeters),
      'activeKilocalories': serializer.toJson<double?>(activeKilocalories),
      'elapsedMs': serializer.toJson<int?>(elapsedMs),
      'averageHeartRate': serializer.toJson<int?>(averageHeartRate),
      'maxHeartRate': serializer.toJson<int?>(maxHeartRate),
    };
  }

  WorkoutRow copyWith({
    int? id,
    String? clientId,
    String? activityType,
    Value<String?> deviceId = const Value.absent(),
    int? startUtcMs,
    Value<int?> endUtcMs = const Value.absent(),
    int? offsetMinutes,
    Value<double?> distanceMeters = const Value.absent(),
    Value<double?> activeKilocalories = const Value.absent(),
    Value<int?> elapsedMs = const Value.absent(),
    Value<int?> averageHeartRate = const Value.absent(),
    Value<int?> maxHeartRate = const Value.absent(),
  }) => WorkoutRow(
    id: id ?? this.id,
    clientId: clientId ?? this.clientId,
    activityType: activityType ?? this.activityType,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs.present ? endUtcMs.value : this.endUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    distanceMeters: distanceMeters.present
        ? distanceMeters.value
        : this.distanceMeters,
    activeKilocalories: activeKilocalories.present
        ? activeKilocalories.value
        : this.activeKilocalories,
    elapsedMs: elapsedMs.present ? elapsedMs.value : this.elapsedMs,
    averageHeartRate: averageHeartRate.present
        ? averageHeartRate.value
        : this.averageHeartRate,
    maxHeartRate: maxHeartRate.present ? maxHeartRate.value : this.maxHeartRate,
  );
  WorkoutRow copyWithCompanion(WorkoutsCompanion data) {
    return WorkoutRow(
      id: data.id.present ? data.id.value : this.id,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      activityType: data.activityType.present
          ? data.activityType.value
          : this.activityType,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      activeKilocalories: data.activeKilocalories.present
          ? data.activeKilocalories.value
          : this.activeKilocalories,
      elapsedMs: data.elapsedMs.present ? data.elapsedMs.value : this.elapsedMs,
      averageHeartRate: data.averageHeartRate.present
          ? data.averageHeartRate.value
          : this.averageHeartRate,
      maxHeartRate: data.maxHeartRate.present
          ? data.maxHeartRate.value
          : this.maxHeartRate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutRow(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('activityType: $activityType, ')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('activeKilocalories: $activeKilocalories, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('maxHeartRate: $maxHeartRate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientId,
    activityType,
    deviceId,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    distanceMeters,
    activeKilocalories,
    elapsedMs,
    averageHeartRate,
    maxHeartRate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutRow &&
          other.id == this.id &&
          other.clientId == this.clientId &&
          other.activityType == this.activityType &&
          other.deviceId == this.deviceId &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.distanceMeters == this.distanceMeters &&
          other.activeKilocalories == this.activeKilocalories &&
          other.elapsedMs == this.elapsedMs &&
          other.averageHeartRate == this.averageHeartRate &&
          other.maxHeartRate == this.maxHeartRate);
}

class WorkoutsCompanion extends UpdateCompanion<WorkoutRow> {
  final Value<int> id;
  final Value<String> clientId;
  final Value<String> activityType;
  final Value<String?> deviceId;
  final Value<int> startUtcMs;
  final Value<int?> endUtcMs;
  final Value<int> offsetMinutes;
  final Value<double?> distanceMeters;
  final Value<double?> activeKilocalories;
  final Value<int?> elapsedMs;
  final Value<int?> averageHeartRate;
  final Value<int?> maxHeartRate;
  const WorkoutsCompanion({
    this.id = const Value.absent(),
    this.clientId = const Value.absent(),
    this.activityType = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.activeKilocalories = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.averageHeartRate = const Value.absent(),
    this.maxHeartRate = const Value.absent(),
  });
  WorkoutsCompanion.insert({
    this.id = const Value.absent(),
    required String clientId,
    required String activityType,
    this.deviceId = const Value.absent(),
    required int startUtcMs,
    this.endUtcMs = const Value.absent(),
    required int offsetMinutes,
    this.distanceMeters = const Value.absent(),
    this.activeKilocalories = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.averageHeartRate = const Value.absent(),
    this.maxHeartRate = const Value.absent(),
  }) : clientId = Value(clientId),
       activityType = Value(activityType),
       startUtcMs = Value(startUtcMs),
       offsetMinutes = Value(offsetMinutes);
  static Insertable<WorkoutRow> custom({
    Expression<int>? id,
    Expression<String>? clientId,
    Expression<String>? activityType,
    Expression<String>? deviceId,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<int>? offsetMinutes,
    Expression<double>? distanceMeters,
    Expression<double>? activeKilocalories,
    Expression<int>? elapsedMs,
    Expression<int>? averageHeartRate,
    Expression<int>? maxHeartRate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientId != null) 'client_id': clientId,
      if (activityType != null) 'activity_type': activityType,
      if (deviceId != null) 'device_id': deviceId,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (activeKilocalories != null) 'active_kilocalories': activeKilocalories,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      if (averageHeartRate != null) 'average_heart_rate': averageHeartRate,
      if (maxHeartRate != null) 'max_heart_rate': maxHeartRate,
    });
  }

  WorkoutsCompanion copyWith({
    Value<int>? id,
    Value<String>? clientId,
    Value<String>? activityType,
    Value<String?>? deviceId,
    Value<int>? startUtcMs,
    Value<int?>? endUtcMs,
    Value<int>? offsetMinutes,
    Value<double?>? distanceMeters,
    Value<double?>? activeKilocalories,
    Value<int?>? elapsedMs,
    Value<int?>? averageHeartRate,
    Value<int?>? maxHeartRate,
  }) {
    return WorkoutsCompanion(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      activityType: activityType ?? this.activityType,
      deviceId: deviceId ?? this.deviceId,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      activeKilocalories: activeKilocalories ?? this.activeKilocalories,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (activityType.present) {
      map['activity_type'] = Variable<String>(activityType.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<double>(distanceMeters.value);
    }
    if (activeKilocalories.present) {
      map['active_kilocalories'] = Variable<double>(activeKilocalories.value);
    }
    if (elapsedMs.present) {
      map['elapsed_ms'] = Variable<int>(elapsedMs.value);
    }
    if (averageHeartRate.present) {
      map['average_heart_rate'] = Variable<int>(averageHeartRate.value);
    }
    if (maxHeartRate.present) {
      map['max_heart_rate'] = Variable<int>(maxHeartRate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutsCompanion(')
          ..write('id: $id, ')
          ..write('clientId: $clientId, ')
          ..write('activityType: $activityType, ')
          ..write('deviceId: $deviceId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('activeKilocalories: $activeKilocalories, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('maxHeartRate: $maxHeartRate')
          ..write(')'))
        .toString();
  }
}

class $WorkoutHrSamplesTable extends WorkoutHrSamples
    with TableInfo<$WorkoutHrSamplesTable, WorkoutHrSampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutHrSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workoutIdMeta = const VerificationMeta(
    'workoutId',
  );
  @override
  late final GeneratedColumn<int> workoutId = GeneratedColumn<int>(
    'workout_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workouts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<int> bpm = GeneratedColumn<int>(
    'bpm',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workoutId,
    atUtcMs,
    offsetMinutes,
    bpm,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_hr_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutHrSampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workout_id')) {
      context.handle(
        _workoutIdMeta,
        workoutId.isAcceptableOrUnknown(data['workout_id']!, _workoutIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workoutIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('bpm')) {
      context.handle(
        _bpmMeta,
        bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta),
      );
    } else if (isInserting) {
      context.missing(_bpmMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workoutId, atUtcMs};
  @override
  WorkoutHrSampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutHrSampleRow(
      workoutId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workout_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      bpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bpm'],
      )!,
    );
  }

  @override
  $WorkoutHrSamplesTable createAlias(String alias) {
    return $WorkoutHrSamplesTable(attachedDatabase, alias);
  }
}

class WorkoutHrSampleRow extends DataClass
    implements Insertable<WorkoutHrSampleRow> {
  final int workoutId;
  final int atUtcMs;
  final int offsetMinutes;
  final int bpm;
  const WorkoutHrSampleRow({
    required this.workoutId,
    required this.atUtcMs,
    required this.offsetMinutes,
    required this.bpm,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workout_id'] = Variable<int>(workoutId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['bpm'] = Variable<int>(bpm);
    return map;
  }

  WorkoutHrSamplesCompanion toCompanion(bool nullToAbsent) {
    return WorkoutHrSamplesCompanion(
      workoutId: Value(workoutId),
      atUtcMs: Value(atUtcMs),
      offsetMinutes: Value(offsetMinutes),
      bpm: Value(bpm),
    );
  }

  factory WorkoutHrSampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutHrSampleRow(
      workoutId: serializer.fromJson<int>(json['workoutId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      bpm: serializer.fromJson<int>(json['bpm']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workoutId': serializer.toJson<int>(workoutId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'bpm': serializer.toJson<int>(bpm),
    };
  }

  WorkoutHrSampleRow copyWith({
    int? workoutId,
    int? atUtcMs,
    int? offsetMinutes,
    int? bpm,
  }) => WorkoutHrSampleRow(
    workoutId: workoutId ?? this.workoutId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    bpm: bpm ?? this.bpm,
  );
  WorkoutHrSampleRow copyWithCompanion(WorkoutHrSamplesCompanion data) {
    return WorkoutHrSampleRow(
      workoutId: data.workoutId.present ? data.workoutId.value : this.workoutId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutHrSampleRow(')
          ..write('workoutId: $workoutId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('bpm: $bpm')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(workoutId, atUtcMs, offsetMinutes, bpm);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutHrSampleRow &&
          other.workoutId == this.workoutId &&
          other.atUtcMs == this.atUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.bpm == this.bpm);
}

class WorkoutHrSamplesCompanion extends UpdateCompanion<WorkoutHrSampleRow> {
  final Value<int> workoutId;
  final Value<int> atUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> bpm;
  final Value<int> rowid;
  const WorkoutHrSamplesCompanion({
    this.workoutId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.bpm = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkoutHrSamplesCompanion.insert({
    required int workoutId,
    required int atUtcMs,
    required int offsetMinutes,
    required int bpm,
    this.rowid = const Value.absent(),
  }) : workoutId = Value(workoutId),
       atUtcMs = Value(atUtcMs),
       offsetMinutes = Value(offsetMinutes),
       bpm = Value(bpm);
  static Insertable<WorkoutHrSampleRow> custom({
    Expression<int>? workoutId,
    Expression<int>? atUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? bpm,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workoutId != null) 'workout_id': workoutId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (bpm != null) 'bpm': bpm,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkoutHrSamplesCompanion copyWith({
    Value<int>? workoutId,
    Value<int>? atUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? bpm,
    Value<int>? rowid,
  }) {
    return WorkoutHrSamplesCompanion(
      workoutId: workoutId ?? this.workoutId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      bpm: bpm ?? this.bpm,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workoutId.present) {
      map['workout_id'] = Variable<int>(workoutId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<int>(bpm.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutHrSamplesCompanion(')
          ..write('workoutId: $workoutId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('bpm: $bpm, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutRoutePointsTable extends WorkoutRoutePoints
    with TableInfo<$WorkoutRoutePointsTable, WorkoutRoutePointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutRoutePointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workoutIdMeta = const VerificationMeta(
    'workoutId',
  );
  @override
  late final GeneratedColumn<int> workoutId = GeneratedColumn<int>(
    'workout_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workouts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _atUtcMsMeta = const VerificationMeta(
    'atUtcMs',
  );
  @override
  late final GeneratedColumn<int> atUtcMs = GeneratedColumn<int>(
    'at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _altitudeMetersMeta = const VerificationMeta(
    'altitudeMeters',
  );
  @override
  late final GeneratedColumn<double> altitudeMeters = GeneratedColumn<double>(
    'altitude_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMetersMeta = const VerificationMeta(
    'accuracyMeters',
  );
  @override
  late final GeneratedColumn<double> accuracyMeters = GeneratedColumn<double>(
    'accuracy_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workoutId,
    atUtcMs,
    offsetMinutes,
    latitude,
    longitude,
    altitudeMeters,
    accuracyMeters,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_route_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutRoutePointRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workout_id')) {
      context.handle(
        _workoutIdMeta,
        workoutId.isAcceptableOrUnknown(data['workout_id']!, _workoutIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workoutIdMeta);
    }
    if (data.containsKey('at_utc_ms')) {
      context.handle(
        _atUtcMsMeta,
        atUtcMs.isAcceptableOrUnknown(data['at_utc_ms']!, _atUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('altitude_meters')) {
      context.handle(
        _altitudeMetersMeta,
        altitudeMeters.isAcceptableOrUnknown(
          data['altitude_meters']!,
          _altitudeMetersMeta,
        ),
      );
    }
    if (data.containsKey('accuracy_meters')) {
      context.handle(
        _accuracyMetersMeta,
        accuracyMeters.isAcceptableOrUnknown(
          data['accuracy_meters']!,
          _accuracyMetersMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workoutId, atUtcMs};
  @override
  WorkoutRoutePointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutRoutePointRow(
      workoutId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workout_id'],
      )!,
      atUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      altitudeMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude_meters'],
      ),
      accuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_meters'],
      ),
    );
  }

  @override
  $WorkoutRoutePointsTable createAlias(String alias) {
    return $WorkoutRoutePointsTable(attachedDatabase, alias);
  }
}

class WorkoutRoutePointRow extends DataClass
    implements Insertable<WorkoutRoutePointRow> {
  final int workoutId;
  final int atUtcMs;
  final int offsetMinutes;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? accuracyMeters;
  const WorkoutRoutePointRow({
    required this.workoutId,
    required this.atUtcMs,
    required this.offsetMinutes,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.accuracyMeters,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workout_id'] = Variable<int>(workoutId);
    map['at_utc_ms'] = Variable<int>(atUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || altitudeMeters != null) {
      map['altitude_meters'] = Variable<double>(altitudeMeters);
    }
    if (!nullToAbsent || accuracyMeters != null) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters);
    }
    return map;
  }

  WorkoutRoutePointsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutRoutePointsCompanion(
      workoutId: Value(workoutId),
      atUtcMs: Value(atUtcMs),
      offsetMinutes: Value(offsetMinutes),
      latitude: Value(latitude),
      longitude: Value(longitude),
      altitudeMeters: altitudeMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeMeters),
      accuracyMeters: accuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyMeters),
    );
  }

  factory WorkoutRoutePointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutRoutePointRow(
      workoutId: serializer.fromJson<int>(json['workoutId']),
      atUtcMs: serializer.fromJson<int>(json['atUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      altitudeMeters: serializer.fromJson<double?>(json['altitudeMeters']),
      accuracyMeters: serializer.fromJson<double?>(json['accuracyMeters']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workoutId': serializer.toJson<int>(workoutId),
      'atUtcMs': serializer.toJson<int>(atUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'altitudeMeters': serializer.toJson<double?>(altitudeMeters),
      'accuracyMeters': serializer.toJson<double?>(accuracyMeters),
    };
  }

  WorkoutRoutePointRow copyWith({
    int? workoutId,
    int? atUtcMs,
    int? offsetMinutes,
    double? latitude,
    double? longitude,
    Value<double?> altitudeMeters = const Value.absent(),
    Value<double?> accuracyMeters = const Value.absent(),
  }) => WorkoutRoutePointRow(
    workoutId: workoutId ?? this.workoutId,
    atUtcMs: atUtcMs ?? this.atUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    altitudeMeters: altitudeMeters.present
        ? altitudeMeters.value
        : this.altitudeMeters,
    accuracyMeters: accuracyMeters.present
        ? accuracyMeters.value
        : this.accuracyMeters,
  );
  WorkoutRoutePointRow copyWithCompanion(WorkoutRoutePointsCompanion data) {
    return WorkoutRoutePointRow(
      workoutId: data.workoutId.present ? data.workoutId.value : this.workoutId,
      atUtcMs: data.atUtcMs.present ? data.atUtcMs.value : this.atUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitudeMeters: data.altitudeMeters.present
          ? data.altitudeMeters.value
          : this.altitudeMeters,
      accuracyMeters: data.accuracyMeters.present
          ? data.accuracyMeters.value
          : this.accuracyMeters,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutRoutePointRow(')
          ..write('workoutId: $workoutId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitudeMeters: $altitudeMeters, ')
          ..write('accuracyMeters: $accuracyMeters')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workoutId,
    atUtcMs,
    offsetMinutes,
    latitude,
    longitude,
    altitudeMeters,
    accuracyMeters,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutRoutePointRow &&
          other.workoutId == this.workoutId &&
          other.atUtcMs == this.atUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitudeMeters == this.altitudeMeters &&
          other.accuracyMeters == this.accuracyMeters);
}

class WorkoutRoutePointsCompanion
    extends UpdateCompanion<WorkoutRoutePointRow> {
  final Value<int> workoutId;
  final Value<int> atUtcMs;
  final Value<int> offsetMinutes;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> altitudeMeters;
  final Value<double?> accuracyMeters;
  final Value<int> rowid;
  const WorkoutRoutePointsCompanion({
    this.workoutId = const Value.absent(),
    this.atUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitudeMeters = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkoutRoutePointsCompanion.insert({
    required int workoutId,
    required int atUtcMs,
    required int offsetMinutes,
    required double latitude,
    required double longitude,
    this.altitudeMeters = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : workoutId = Value(workoutId),
       atUtcMs = Value(atUtcMs),
       offsetMinutes = Value(offsetMinutes),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<WorkoutRoutePointRow> custom({
    Expression<int>? workoutId,
    Expression<int>? atUtcMs,
    Expression<int>? offsetMinutes,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitudeMeters,
    Expression<double>? accuracyMeters,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workoutId != null) 'workout_id': workoutId,
      if (atUtcMs != null) 'at_utc_ms': atUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitudeMeters != null) 'altitude_meters': altitudeMeters,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkoutRoutePointsCompanion copyWith({
    Value<int>? workoutId,
    Value<int>? atUtcMs,
    Value<int>? offsetMinutes,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? altitudeMeters,
    Value<double?>? accuracyMeters,
    Value<int>? rowid,
  }) {
    return WorkoutRoutePointsCompanion(
      workoutId: workoutId ?? this.workoutId,
      atUtcMs: atUtcMs ?? this.atUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workoutId.present) {
      map['workout_id'] = Variable<int>(workoutId.value);
    }
    if (atUtcMs.present) {
      map['at_utc_ms'] = Variable<int>(atUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitudeMeters.present) {
      map['altitude_meters'] = Variable<double>(altitudeMeters.value);
    }
    if (accuracyMeters.present) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutRoutePointsCompanion(')
          ..write('workoutId: $workoutId, ')
          ..write('atUtcMs: $atUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitudeMeters: $altitudeMeters, ')
          ..write('accuracyMeters: $accuracyMeters, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutPausesTable extends WorkoutPauses
    with TableInfo<$WorkoutPausesTable, WorkoutPauseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutPausesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workoutIdMeta = const VerificationMeta(
    'workoutId',
  );
  @override
  late final GeneratedColumn<int> workoutId = GeneratedColumn<int>(
    'workout_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES workouts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [workoutId, startUtcMs, endUtcMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_pauses';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutPauseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workout_id')) {
      context.handle(
        _workoutIdMeta,
        workoutId.isAcceptableOrUnknown(data['workout_id']!, _workoutIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workoutIdMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workoutId, startUtcMs};
  @override
  WorkoutPauseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutPauseRow(
      workoutId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workout_id'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
    );
  }

  @override
  $WorkoutPausesTable createAlias(String alias) {
    return $WorkoutPausesTable(attachedDatabase, alias);
  }
}

class WorkoutPauseRow extends DataClass implements Insertable<WorkoutPauseRow> {
  final int workoutId;
  final int startUtcMs;
  final int endUtcMs;
  const WorkoutPauseRow({
    required this.workoutId,
    required this.startUtcMs,
    required this.endUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workout_id'] = Variable<int>(workoutId);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    return map;
  }

  WorkoutPausesCompanion toCompanion(bool nullToAbsent) {
    return WorkoutPausesCompanion(
      workoutId: Value(workoutId),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
    );
  }

  factory WorkoutPauseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutPauseRow(
      workoutId: serializer.fromJson<int>(json['workoutId']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workoutId': serializer.toJson<int>(workoutId),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
    };
  }

  WorkoutPauseRow copyWith({int? workoutId, int? startUtcMs, int? endUtcMs}) =>
      WorkoutPauseRow(
        workoutId: workoutId ?? this.workoutId,
        startUtcMs: startUtcMs ?? this.startUtcMs,
        endUtcMs: endUtcMs ?? this.endUtcMs,
      );
  WorkoutPauseRow copyWithCompanion(WorkoutPausesCompanion data) {
    return WorkoutPauseRow(
      workoutId: data.workoutId.present ? data.workoutId.value : this.workoutId,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutPauseRow(')
          ..write('workoutId: $workoutId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(workoutId, startUtcMs, endUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutPauseRow &&
          other.workoutId == this.workoutId &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs);
}

class WorkoutPausesCompanion extends UpdateCompanion<WorkoutPauseRow> {
  final Value<int> workoutId;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<int> rowid;
  const WorkoutPausesCompanion({
    this.workoutId = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkoutPausesCompanion.insert({
    required int workoutId,
    required int startUtcMs,
    required int endUtcMs,
    this.rowid = const Value.absent(),
  }) : workoutId = Value(workoutId),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs);
  static Insertable<WorkoutPauseRow> custom({
    Expression<int>? workoutId,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workoutId != null) 'workout_id': workoutId,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkoutPausesCompanion copyWith({
    Value<int>? workoutId,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<int>? rowid,
  }) {
    return WorkoutPausesCompanion(
      workoutId: workoutId ?? this.workoutId,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workoutId.present) {
      map['workout_id'] = Variable<int>(workoutId.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutPausesCompanion(')
          ..write('workoutId: $workoutId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HealthOutboxTable extends HealthOutbox
    with TableInfo<$HealthOutboxTable, HealthOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HealthOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<HealthRecordKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<HealthRecordKind>($HealthOutboxTable.$converterkind);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fromUtcMsMeta = const VerificationMeta(
    'fromUtcMs',
  );
  @override
  late final GeneratedColumn<int> fromUtcMs = GeneratedColumn<int>(
    'from_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toUtcMsMeta = const VerificationMeta(
    'toUtcMs',
  );
  @override
  late final GeneratedColumn<int> toUtcMs = GeneratedColumn<int>(
    'to_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordCountMeta = const VerificationMeta(
    'recordCount',
  );
  @override
  late final GeneratedColumn<int> recordCount = GeneratedColumn<int>(
    'record_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enqueuedAtUtcMsMeta = const VerificationMeta(
    'enqueuedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> enqueuedAtUtcMs = GeneratedColumn<int>(
    'enqueued_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtUtcMsMeta = const VerificationMeta(
    'completedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> completedAtUtcMs = GeneratedColumn<int>(
    'completed_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<OutboxStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(OutboxStatus.pending.name),
      ).withConverter<OutboxStatus>($HealthOutboxTable.$converterstatus);
  static const VerificationMeta _lastAttemptAtUtcMsMeta =
      const VerificationMeta('lastAttemptAtUtcMs');
  @override
  late final GeneratedColumn<int> lastAttemptAtUtcMs = GeneratedColumn<int>(
    'last_attempt_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextAttemptAtUtcMsMeta =
      const VerificationMeta('nextAttemptAtUtcMs');
  @override
  late final GeneratedColumn<int> nextAttemptAtUtcMs = GeneratedColumn<int>(
    'next_attempt_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    deviceId,
    fromUtcMs,
    toUtcMs,
    recordCount,
    enqueuedAtUtcMs,
    attempts,
    lastError,
    completedAtUtcMs,
    status,
    lastAttemptAtUtcMs,
    nextAttemptAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'health_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<HealthOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('from_utc_ms')) {
      context.handle(
        _fromUtcMsMeta,
        fromUtcMs.isAcceptableOrUnknown(data['from_utc_ms']!, _fromUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_fromUtcMsMeta);
    }
    if (data.containsKey('to_utc_ms')) {
      context.handle(
        _toUtcMsMeta,
        toUtcMs.isAcceptableOrUnknown(data['to_utc_ms']!, _toUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_toUtcMsMeta);
    }
    if (data.containsKey('record_count')) {
      context.handle(
        _recordCountMeta,
        recordCount.isAcceptableOrUnknown(
          data['record_count']!,
          _recordCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordCountMeta);
    }
    if (data.containsKey('enqueued_at_utc_ms')) {
      context.handle(
        _enqueuedAtUtcMsMeta,
        enqueuedAtUtcMs.isAcceptableOrUnknown(
          data['enqueued_at_utc_ms']!,
          _enqueuedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_enqueuedAtUtcMsMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('completed_at_utc_ms')) {
      context.handle(
        _completedAtUtcMsMeta,
        completedAtUtcMs.isAcceptableOrUnknown(
          data['completed_at_utc_ms']!,
          _completedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at_utc_ms')) {
      context.handle(
        _lastAttemptAtUtcMsMeta,
        lastAttemptAtUtcMs.isAcceptableOrUnknown(
          data['last_attempt_at_utc_ms']!,
          _lastAttemptAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at_utc_ms')) {
      context.handle(
        _nextAttemptAtUtcMsMeta,
        nextAttemptAtUtcMs.isAcceptableOrUnknown(
          data['next_attempt_at_utc_ms']!,
          _nextAttemptAtUtcMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HealthOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HealthOutboxRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: $HealthOutboxTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      fromUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}from_utc_ms'],
      )!,
      toUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_utc_ms'],
      )!,
      recordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}record_count'],
      )!,
      enqueuedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}enqueued_at_utc_ms'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      completedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_utc_ms'],
      ),
      status: $HealthOutboxTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      lastAttemptAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_attempt_at_utc_ms'],
      ),
      nextAttemptAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at_utc_ms'],
      ),
    );
  }

  @override
  $HealthOutboxTable createAlias(String alias) {
    return $HealthOutboxTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<HealthRecordKind, String, String> $converterkind =
      const EnumNameConverter<HealthRecordKind>(HealthRecordKind.values);
  static JsonTypeConverter2<OutboxStatus, String, String> $converterstatus =
      const EnumNameConverter<OutboxStatus>(OutboxStatus.values);
}

class HealthOutboxRow extends DataClass implements Insertable<HealthOutboxRow> {
  final int id;
  final HealthRecordKind kind;
  final String? deviceId;
  final int fromUtcMs;
  final int toUtcMs;
  final int recordCount;
  final int enqueuedAtUtcMs;
  final int attempts;
  final String? lastError;
  final int? completedAtUtcMs;
  final OutboxStatus status;
  final int? lastAttemptAtUtcMs;
  final int? nextAttemptAtUtcMs;
  const HealthOutboxRow({
    required this.id,
    required this.kind,
    this.deviceId,
    required this.fromUtcMs,
    required this.toUtcMs,
    required this.recordCount,
    required this.enqueuedAtUtcMs,
    required this.attempts,
    this.lastError,
    this.completedAtUtcMs,
    required this.status,
    this.lastAttemptAtUtcMs,
    this.nextAttemptAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['kind'] = Variable<String>(
        $HealthOutboxTable.$converterkind.toSql(kind),
      );
    }
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    map['from_utc_ms'] = Variable<int>(fromUtcMs);
    map['to_utc_ms'] = Variable<int>(toUtcMs);
    map['record_count'] = Variable<int>(recordCount);
    map['enqueued_at_utc_ms'] = Variable<int>(enqueuedAtUtcMs);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || completedAtUtcMs != null) {
      map['completed_at_utc_ms'] = Variable<int>(completedAtUtcMs);
    }
    {
      map['status'] = Variable<String>(
        $HealthOutboxTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || lastAttemptAtUtcMs != null) {
      map['last_attempt_at_utc_ms'] = Variable<int>(lastAttemptAtUtcMs);
    }
    if (!nullToAbsent || nextAttemptAtUtcMs != null) {
      map['next_attempt_at_utc_ms'] = Variable<int>(nextAttemptAtUtcMs);
    }
    return map;
  }

  HealthOutboxCompanion toCompanion(bool nullToAbsent) {
    return HealthOutboxCompanion(
      id: Value(id),
      kind: Value(kind),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      fromUtcMs: Value(fromUtcMs),
      toUtcMs: Value(toUtcMs),
      recordCount: Value(recordCount),
      enqueuedAtUtcMs: Value(enqueuedAtUtcMs),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      completedAtUtcMs: completedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtcMs),
      status: Value(status),
      lastAttemptAtUtcMs: lastAttemptAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAtUtcMs),
      nextAttemptAtUtcMs: nextAttemptAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAtUtcMs),
    );
  }

  factory HealthOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HealthOutboxRow(
      id: serializer.fromJson<int>(json['id']),
      kind: $HealthOutboxTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      fromUtcMs: serializer.fromJson<int>(json['fromUtcMs']),
      toUtcMs: serializer.fromJson<int>(json['toUtcMs']),
      recordCount: serializer.fromJson<int>(json['recordCount']),
      enqueuedAtUtcMs: serializer.fromJson<int>(json['enqueuedAtUtcMs']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      completedAtUtcMs: serializer.fromJson<int?>(json['completedAtUtcMs']),
      status: $HealthOutboxTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      lastAttemptAtUtcMs: serializer.fromJson<int?>(json['lastAttemptAtUtcMs']),
      nextAttemptAtUtcMs: serializer.fromJson<int?>(json['nextAttemptAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(
        $HealthOutboxTable.$converterkind.toJson(kind),
      ),
      'deviceId': serializer.toJson<String?>(deviceId),
      'fromUtcMs': serializer.toJson<int>(fromUtcMs),
      'toUtcMs': serializer.toJson<int>(toUtcMs),
      'recordCount': serializer.toJson<int>(recordCount),
      'enqueuedAtUtcMs': serializer.toJson<int>(enqueuedAtUtcMs),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'completedAtUtcMs': serializer.toJson<int?>(completedAtUtcMs),
      'status': serializer.toJson<String>(
        $HealthOutboxTable.$converterstatus.toJson(status),
      ),
      'lastAttemptAtUtcMs': serializer.toJson<int?>(lastAttemptAtUtcMs),
      'nextAttemptAtUtcMs': serializer.toJson<int?>(nextAttemptAtUtcMs),
    };
  }

  HealthOutboxRow copyWith({
    int? id,
    HealthRecordKind? kind,
    Value<String?> deviceId = const Value.absent(),
    int? fromUtcMs,
    int? toUtcMs,
    int? recordCount,
    int? enqueuedAtUtcMs,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<int?> completedAtUtcMs = const Value.absent(),
    OutboxStatus? status,
    Value<int?> lastAttemptAtUtcMs = const Value.absent(),
    Value<int?> nextAttemptAtUtcMs = const Value.absent(),
  }) => HealthOutboxRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    fromUtcMs: fromUtcMs ?? this.fromUtcMs,
    toUtcMs: toUtcMs ?? this.toUtcMs,
    recordCount: recordCount ?? this.recordCount,
    enqueuedAtUtcMs: enqueuedAtUtcMs ?? this.enqueuedAtUtcMs,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    completedAtUtcMs: completedAtUtcMs.present
        ? completedAtUtcMs.value
        : this.completedAtUtcMs,
    status: status ?? this.status,
    lastAttemptAtUtcMs: lastAttemptAtUtcMs.present
        ? lastAttemptAtUtcMs.value
        : this.lastAttemptAtUtcMs,
    nextAttemptAtUtcMs: nextAttemptAtUtcMs.present
        ? nextAttemptAtUtcMs.value
        : this.nextAttemptAtUtcMs,
  );
  HealthOutboxRow copyWithCompanion(HealthOutboxCompanion data) {
    return HealthOutboxRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      fromUtcMs: data.fromUtcMs.present ? data.fromUtcMs.value : this.fromUtcMs,
      toUtcMs: data.toUtcMs.present ? data.toUtcMs.value : this.toUtcMs,
      recordCount: data.recordCount.present
          ? data.recordCount.value
          : this.recordCount,
      enqueuedAtUtcMs: data.enqueuedAtUtcMs.present
          ? data.enqueuedAtUtcMs.value
          : this.enqueuedAtUtcMs,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      completedAtUtcMs: data.completedAtUtcMs.present
          ? data.completedAtUtcMs.value
          : this.completedAtUtcMs,
      status: data.status.present ? data.status.value : this.status,
      lastAttemptAtUtcMs: data.lastAttemptAtUtcMs.present
          ? data.lastAttemptAtUtcMs.value
          : this.lastAttemptAtUtcMs,
      nextAttemptAtUtcMs: data.nextAttemptAtUtcMs.present
          ? data.nextAttemptAtUtcMs.value
          : this.nextAttemptAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HealthOutboxRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('deviceId: $deviceId, ')
          ..write('fromUtcMs: $fromUtcMs, ')
          ..write('toUtcMs: $toUtcMs, ')
          ..write('recordCount: $recordCount, ')
          ..write('enqueuedAtUtcMs: $enqueuedAtUtcMs, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('completedAtUtcMs: $completedAtUtcMs, ')
          ..write('status: $status, ')
          ..write('lastAttemptAtUtcMs: $lastAttemptAtUtcMs, ')
          ..write('nextAttemptAtUtcMs: $nextAttemptAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    deviceId,
    fromUtcMs,
    toUtcMs,
    recordCount,
    enqueuedAtUtcMs,
    attempts,
    lastError,
    completedAtUtcMs,
    status,
    lastAttemptAtUtcMs,
    nextAttemptAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HealthOutboxRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.deviceId == this.deviceId &&
          other.fromUtcMs == this.fromUtcMs &&
          other.toUtcMs == this.toUtcMs &&
          other.recordCount == this.recordCount &&
          other.enqueuedAtUtcMs == this.enqueuedAtUtcMs &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.completedAtUtcMs == this.completedAtUtcMs &&
          other.status == this.status &&
          other.lastAttemptAtUtcMs == this.lastAttemptAtUtcMs &&
          other.nextAttemptAtUtcMs == this.nextAttemptAtUtcMs);
}

class HealthOutboxCompanion extends UpdateCompanion<HealthOutboxRow> {
  final Value<int> id;
  final Value<HealthRecordKind> kind;
  final Value<String?> deviceId;
  final Value<int> fromUtcMs;
  final Value<int> toUtcMs;
  final Value<int> recordCount;
  final Value<int> enqueuedAtUtcMs;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int?> completedAtUtcMs;
  final Value<OutboxStatus> status;
  final Value<int?> lastAttemptAtUtcMs;
  final Value<int?> nextAttemptAtUtcMs;
  const HealthOutboxCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.fromUtcMs = const Value.absent(),
    this.toUtcMs = const Value.absent(),
    this.recordCount = const Value.absent(),
    this.enqueuedAtUtcMs = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.completedAtUtcMs = const Value.absent(),
    this.status = const Value.absent(),
    this.lastAttemptAtUtcMs = const Value.absent(),
    this.nextAttemptAtUtcMs = const Value.absent(),
  });
  HealthOutboxCompanion.insert({
    this.id = const Value.absent(),
    required HealthRecordKind kind,
    this.deviceId = const Value.absent(),
    required int fromUtcMs,
    required int toUtcMs,
    required int recordCount,
    required int enqueuedAtUtcMs,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.completedAtUtcMs = const Value.absent(),
    this.status = const Value.absent(),
    this.lastAttemptAtUtcMs = const Value.absent(),
    this.nextAttemptAtUtcMs = const Value.absent(),
  }) : kind = Value(kind),
       fromUtcMs = Value(fromUtcMs),
       toUtcMs = Value(toUtcMs),
       recordCount = Value(recordCount),
       enqueuedAtUtcMs = Value(enqueuedAtUtcMs);
  static Insertable<HealthOutboxRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? deviceId,
    Expression<int>? fromUtcMs,
    Expression<int>? toUtcMs,
    Expression<int>? recordCount,
    Expression<int>? enqueuedAtUtcMs,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? completedAtUtcMs,
    Expression<String>? status,
    Expression<int>? lastAttemptAtUtcMs,
    Expression<int>? nextAttemptAtUtcMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (deviceId != null) 'device_id': deviceId,
      if (fromUtcMs != null) 'from_utc_ms': fromUtcMs,
      if (toUtcMs != null) 'to_utc_ms': toUtcMs,
      if (recordCount != null) 'record_count': recordCount,
      if (enqueuedAtUtcMs != null) 'enqueued_at_utc_ms': enqueuedAtUtcMs,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (completedAtUtcMs != null) 'completed_at_utc_ms': completedAtUtcMs,
      if (status != null) 'status': status,
      if (lastAttemptAtUtcMs != null)
        'last_attempt_at_utc_ms': lastAttemptAtUtcMs,
      if (nextAttemptAtUtcMs != null)
        'next_attempt_at_utc_ms': nextAttemptAtUtcMs,
    });
  }

  HealthOutboxCompanion copyWith({
    Value<int>? id,
    Value<HealthRecordKind>? kind,
    Value<String?>? deviceId,
    Value<int>? fromUtcMs,
    Value<int>? toUtcMs,
    Value<int>? recordCount,
    Value<int>? enqueuedAtUtcMs,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int?>? completedAtUtcMs,
    Value<OutboxStatus>? status,
    Value<int?>? lastAttemptAtUtcMs,
    Value<int?>? nextAttemptAtUtcMs,
  }) {
    return HealthOutboxCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      deviceId: deviceId ?? this.deviceId,
      fromUtcMs: fromUtcMs ?? this.fromUtcMs,
      toUtcMs: toUtcMs ?? this.toUtcMs,
      recordCount: recordCount ?? this.recordCount,
      enqueuedAtUtcMs: enqueuedAtUtcMs ?? this.enqueuedAtUtcMs,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      completedAtUtcMs: completedAtUtcMs ?? this.completedAtUtcMs,
      status: status ?? this.status,
      lastAttemptAtUtcMs: lastAttemptAtUtcMs ?? this.lastAttemptAtUtcMs,
      nextAttemptAtUtcMs: nextAttemptAtUtcMs ?? this.nextAttemptAtUtcMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $HealthOutboxTable.$converterkind.toSql(kind.value),
      );
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (fromUtcMs.present) {
      map['from_utc_ms'] = Variable<int>(fromUtcMs.value);
    }
    if (toUtcMs.present) {
      map['to_utc_ms'] = Variable<int>(toUtcMs.value);
    }
    if (recordCount.present) {
      map['record_count'] = Variable<int>(recordCount.value);
    }
    if (enqueuedAtUtcMs.present) {
      map['enqueued_at_utc_ms'] = Variable<int>(enqueuedAtUtcMs.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (completedAtUtcMs.present) {
      map['completed_at_utc_ms'] = Variable<int>(completedAtUtcMs.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $HealthOutboxTable.$converterstatus.toSql(status.value),
      );
    }
    if (lastAttemptAtUtcMs.present) {
      map['last_attempt_at_utc_ms'] = Variable<int>(lastAttemptAtUtcMs.value);
    }
    if (nextAttemptAtUtcMs.present) {
      map['next_attempt_at_utc_ms'] = Variable<int>(nextAttemptAtUtcMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HealthOutboxCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('deviceId: $deviceId, ')
          ..write('fromUtcMs: $fromUtcMs, ')
          ..write('toUtcMs: $toUtcMs, ')
          ..write('recordCount: $recordCount, ')
          ..write('enqueuedAtUtcMs: $enqueuedAtUtcMs, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('completedAtUtcMs: $completedAtUtcMs, ')
          ..write('status: $status, ')
          ..write('lastAttemptAtUtcMs: $lastAttemptAtUtcMs, ')
          ..write('nextAttemptAtUtcMs: $nextAttemptAtUtcMs')
          ..write(')'))
        .toString();
  }
}

class $SourcePrioritiesTable extends SourcePriorities
    with TableInfo<$SourcePrioritiesTable, SourcePriorityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcePrioritiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _metricMeta = const VerificationMeta('metric');
  @override
  late final GeneratedColumn<String> metric = GeneratedColumn<String>(
    'metric',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [metric, source, priority];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_priorities';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourcePriorityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('metric')) {
      context.handle(
        _metricMeta,
        metric.isAcceptableOrUnknown(data['metric']!, _metricMeta),
      );
    } else if (isInserting) {
      context.missing(_metricMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {metric, source};
  @override
  SourcePriorityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourcePriorityRow(
      metric: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
    );
  }

  @override
  $SourcePrioritiesTable createAlias(String alias) {
    return $SourcePrioritiesTable(attachedDatabase, alias);
  }
}

class SourcePriorityRow extends DataClass
    implements Insertable<SourcePriorityRow> {
  final String metric;
  final String source;
  final int priority;
  const SourcePriorityRow({
    required this.metric,
    required this.source,
    required this.priority,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['metric'] = Variable<String>(metric);
    map['source'] = Variable<String>(source);
    map['priority'] = Variable<int>(priority);
    return map;
  }

  SourcePrioritiesCompanion toCompanion(bool nullToAbsent) {
    return SourcePrioritiesCompanion(
      metric: Value(metric),
      source: Value(source),
      priority: Value(priority),
    );
  }

  factory SourcePriorityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourcePriorityRow(
      metric: serializer.fromJson<String>(json['metric']),
      source: serializer.fromJson<String>(json['source']),
      priority: serializer.fromJson<int>(json['priority']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'metric': serializer.toJson<String>(metric),
      'source': serializer.toJson<String>(source),
      'priority': serializer.toJson<int>(priority),
    };
  }

  SourcePriorityRow copyWith({String? metric, String? source, int? priority}) =>
      SourcePriorityRow(
        metric: metric ?? this.metric,
        source: source ?? this.source,
        priority: priority ?? this.priority,
      );
  SourcePriorityRow copyWithCompanion(SourcePrioritiesCompanion data) {
    return SourcePriorityRow(
      metric: data.metric.present ? data.metric.value : this.metric,
      source: data.source.present ? data.source.value : this.source,
      priority: data.priority.present ? data.priority.value : this.priority,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourcePriorityRow(')
          ..write('metric: $metric, ')
          ..write('source: $source, ')
          ..write('priority: $priority')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(metric, source, priority);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourcePriorityRow &&
          other.metric == this.metric &&
          other.source == this.source &&
          other.priority == this.priority);
}

class SourcePrioritiesCompanion extends UpdateCompanion<SourcePriorityRow> {
  final Value<String> metric;
  final Value<String> source;
  final Value<int> priority;
  final Value<int> rowid;
  const SourcePrioritiesCompanion({
    this.metric = const Value.absent(),
    this.source = const Value.absent(),
    this.priority = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourcePrioritiesCompanion.insert({
    required String metric,
    required String source,
    required int priority,
    this.rowid = const Value.absent(),
  }) : metric = Value(metric),
       source = Value(source),
       priority = Value(priority);
  static Insertable<SourcePriorityRow> custom({
    Expression<String>? metric,
    Expression<String>? source,
    Expression<int>? priority,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (metric != null) 'metric': metric,
      if (source != null) 'source': source,
      if (priority != null) 'priority': priority,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourcePrioritiesCompanion copyWith({
    Value<String>? metric,
    Value<String>? source,
    Value<int>? priority,
    Value<int>? rowid,
  }) {
    return SourcePrioritiesCompanion(
      metric: metric ?? this.metric,
      source: source ?? this.source,
      priority: priority ?? this.priority,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (metric.present) {
      map['metric'] = Variable<String>(metric.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcePrioritiesCompanion(')
          ..write('metric: $metric, ')
          ..write('source: $source, ')
          ..write('priority: $priority, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserProfileTable extends UserProfile
    with TableInfo<$UserProfileTable, UserProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserProfileTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    check: () => const CustomExpression<bool>('id = 1'),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _birthYearMeta = const VerificationMeta(
    'birthYear',
  );
  @override
  late final GeneratedColumn<int> birthYear = GeneratedColumn<int>(
    'birth_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sexMeta = const VerificationMeta('sex');
  @override
  late final GeneratedColumn<String> sex = GeneratedColumn<String>(
    'sex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightCentimetersMeta = const VerificationMeta(
    'heightCentimeters',
  );
  @override
  late final GeneratedColumn<double> heightCentimeters =
      GeneratedColumn<double>(
        'height_centimeters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _weightKilogramsMeta = const VerificationMeta(
    'weightKilograms',
  );
  @override
  late final GeneratedColumn<double> weightKilograms = GeneratedColumn<double>(
    'weight_kilograms',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxHeartRateMeta = const VerificationMeta(
    'maxHeartRate',
  );
  @override
  late final GeneratedColumn<int> maxHeartRate = GeneratedColumn<int>(
    'max_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dailyStepGoalMeta = const VerificationMeta(
    'dailyStepGoal',
  );
  @override
  late final GeneratedColumn<int> dailyStepGoal = GeneratedColumn<int>(
    'daily_step_goal',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    birthYear,
    sex,
    heightCentimeters,
    weightKilograms,
    maxHeartRate,
    dailyStepGoal,
    updatedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_profile';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('birth_year')) {
      context.handle(
        _birthYearMeta,
        birthYear.isAcceptableOrUnknown(data['birth_year']!, _birthYearMeta),
      );
    }
    if (data.containsKey('sex')) {
      context.handle(
        _sexMeta,
        sex.isAcceptableOrUnknown(data['sex']!, _sexMeta),
      );
    }
    if (data.containsKey('height_centimeters')) {
      context.handle(
        _heightCentimetersMeta,
        heightCentimeters.isAcceptableOrUnknown(
          data['height_centimeters']!,
          _heightCentimetersMeta,
        ),
      );
    }
    if (data.containsKey('weight_kilograms')) {
      context.handle(
        _weightKilogramsMeta,
        weightKilograms.isAcceptableOrUnknown(
          data['weight_kilograms']!,
          _weightKilogramsMeta,
        ),
      );
    }
    if (data.containsKey('max_heart_rate')) {
      context.handle(
        _maxHeartRateMeta,
        maxHeartRate.isAcceptableOrUnknown(
          data['max_heart_rate']!,
          _maxHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('daily_step_goal')) {
      context.handle(
        _dailyStepGoalMeta,
        dailyStepGoal.isAcceptableOrUnknown(
          data['daily_step_goal']!,
          _dailyStepGoalMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      birthYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}birth_year'],
      ),
      sex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sex'],
      ),
      heightCentimeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height_centimeters'],
      ),
      weightKilograms: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_kilograms'],
      ),
      maxHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_heart_rate'],
      ),
      dailyStepGoal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_step_goal'],
      ),
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
    );
  }

  @override
  $UserProfileTable createAlias(String alias) {
    return $UserProfileTable(attachedDatabase, alias);
  }
}

class UserProfileRow extends DataClass implements Insertable<UserProfileRow> {
  final int id;
  final int? birthYear;
  final String? sex;
  final double? heightCentimeters;
  final double? weightKilograms;
  final int? maxHeartRate;
  final int? dailyStepGoal;
  final int updatedAtUtcMs;
  const UserProfileRow({
    required this.id,
    this.birthYear,
    this.sex,
    this.heightCentimeters,
    this.weightKilograms,
    this.maxHeartRate,
    this.dailyStepGoal,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || birthYear != null) {
      map['birth_year'] = Variable<int>(birthYear);
    }
    if (!nullToAbsent || sex != null) {
      map['sex'] = Variable<String>(sex);
    }
    if (!nullToAbsent || heightCentimeters != null) {
      map['height_centimeters'] = Variable<double>(heightCentimeters);
    }
    if (!nullToAbsent || weightKilograms != null) {
      map['weight_kilograms'] = Variable<double>(weightKilograms);
    }
    if (!nullToAbsent || maxHeartRate != null) {
      map['max_heart_rate'] = Variable<int>(maxHeartRate);
    }
    if (!nullToAbsent || dailyStepGoal != null) {
      map['daily_step_goal'] = Variable<int>(dailyStepGoal);
    }
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    return map;
  }

  UserProfileCompanion toCompanion(bool nullToAbsent) {
    return UserProfileCompanion(
      id: Value(id),
      birthYear: birthYear == null && nullToAbsent
          ? const Value.absent()
          : Value(birthYear),
      sex: sex == null && nullToAbsent ? const Value.absent() : Value(sex),
      heightCentimeters: heightCentimeters == null && nullToAbsent
          ? const Value.absent()
          : Value(heightCentimeters),
      weightKilograms: weightKilograms == null && nullToAbsent
          ? const Value.absent()
          : Value(weightKilograms),
      maxHeartRate: maxHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(maxHeartRate),
      dailyStepGoal: dailyStepGoal == null && nullToAbsent
          ? const Value.absent()
          : Value(dailyStepGoal),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory UserProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserProfileRow(
      id: serializer.fromJson<int>(json['id']),
      birthYear: serializer.fromJson<int?>(json['birthYear']),
      sex: serializer.fromJson<String?>(json['sex']),
      heightCentimeters: serializer.fromJson<double?>(
        json['heightCentimeters'],
      ),
      weightKilograms: serializer.fromJson<double?>(json['weightKilograms']),
      maxHeartRate: serializer.fromJson<int?>(json['maxHeartRate']),
      dailyStepGoal: serializer.fromJson<int?>(json['dailyStepGoal']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'birthYear': serializer.toJson<int?>(birthYear),
      'sex': serializer.toJson<String?>(sex),
      'heightCentimeters': serializer.toJson<double?>(heightCentimeters),
      'weightKilograms': serializer.toJson<double?>(weightKilograms),
      'maxHeartRate': serializer.toJson<int?>(maxHeartRate),
      'dailyStepGoal': serializer.toJson<int?>(dailyStepGoal),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
    };
  }

  UserProfileRow copyWith({
    int? id,
    Value<int?> birthYear = const Value.absent(),
    Value<String?> sex = const Value.absent(),
    Value<double?> heightCentimeters = const Value.absent(),
    Value<double?> weightKilograms = const Value.absent(),
    Value<int?> maxHeartRate = const Value.absent(),
    Value<int?> dailyStepGoal = const Value.absent(),
    int? updatedAtUtcMs,
  }) => UserProfileRow(
    id: id ?? this.id,
    birthYear: birthYear.present ? birthYear.value : this.birthYear,
    sex: sex.present ? sex.value : this.sex,
    heightCentimeters: heightCentimeters.present
        ? heightCentimeters.value
        : this.heightCentimeters,
    weightKilograms: weightKilograms.present
        ? weightKilograms.value
        : this.weightKilograms,
    maxHeartRate: maxHeartRate.present ? maxHeartRate.value : this.maxHeartRate,
    dailyStepGoal: dailyStepGoal.present
        ? dailyStepGoal.value
        : this.dailyStepGoal,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
  UserProfileRow copyWithCompanion(UserProfileCompanion data) {
    return UserProfileRow(
      id: data.id.present ? data.id.value : this.id,
      birthYear: data.birthYear.present ? data.birthYear.value : this.birthYear,
      sex: data.sex.present ? data.sex.value : this.sex,
      heightCentimeters: data.heightCentimeters.present
          ? data.heightCentimeters.value
          : this.heightCentimeters,
      weightKilograms: data.weightKilograms.present
          ? data.weightKilograms.value
          : this.weightKilograms,
      maxHeartRate: data.maxHeartRate.present
          ? data.maxHeartRate.value
          : this.maxHeartRate,
      dailyStepGoal: data.dailyStepGoal.present
          ? data.dailyStepGoal.value
          : this.dailyStepGoal,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserProfileRow(')
          ..write('id: $id, ')
          ..write('birthYear: $birthYear, ')
          ..write('sex: $sex, ')
          ..write('heightCentimeters: $heightCentimeters, ')
          ..write('weightKilograms: $weightKilograms, ')
          ..write('maxHeartRate: $maxHeartRate, ')
          ..write('dailyStepGoal: $dailyStepGoal, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    birthYear,
    sex,
    heightCentimeters,
    weightKilograms,
    maxHeartRate,
    dailyStepGoal,
    updatedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserProfileRow &&
          other.id == this.id &&
          other.birthYear == this.birthYear &&
          other.sex == this.sex &&
          other.heightCentimeters == this.heightCentimeters &&
          other.weightKilograms == this.weightKilograms &&
          other.maxHeartRate == this.maxHeartRate &&
          other.dailyStepGoal == this.dailyStepGoal &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class UserProfileCompanion extends UpdateCompanion<UserProfileRow> {
  final Value<int> id;
  final Value<int?> birthYear;
  final Value<String?> sex;
  final Value<double?> heightCentimeters;
  final Value<double?> weightKilograms;
  final Value<int?> maxHeartRate;
  final Value<int?> dailyStepGoal;
  final Value<int> updatedAtUtcMs;
  const UserProfileCompanion({
    this.id = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.sex = const Value.absent(),
    this.heightCentimeters = const Value.absent(),
    this.weightKilograms = const Value.absent(),
    this.maxHeartRate = const Value.absent(),
    this.dailyStepGoal = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
  });
  UserProfileCompanion.insert({
    this.id = const Value.absent(),
    this.birthYear = const Value.absent(),
    this.sex = const Value.absent(),
    this.heightCentimeters = const Value.absent(),
    this.weightKilograms = const Value.absent(),
    this.maxHeartRate = const Value.absent(),
    this.dailyStepGoal = const Value.absent(),
    required int updatedAtUtcMs,
  }) : updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<UserProfileRow> custom({
    Expression<int>? id,
    Expression<int>? birthYear,
    Expression<String>? sex,
    Expression<double>? heightCentimeters,
    Expression<double>? weightKilograms,
    Expression<int>? maxHeartRate,
    Expression<int>? dailyStepGoal,
    Expression<int>? updatedAtUtcMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (birthYear != null) 'birth_year': birthYear,
      if (sex != null) 'sex': sex,
      if (heightCentimeters != null) 'height_centimeters': heightCentimeters,
      if (weightKilograms != null) 'weight_kilograms': weightKilograms,
      if (maxHeartRate != null) 'max_heart_rate': maxHeartRate,
      if (dailyStepGoal != null) 'daily_step_goal': dailyStepGoal,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
    });
  }

  UserProfileCompanion copyWith({
    Value<int>? id,
    Value<int?>? birthYear,
    Value<String?>? sex,
    Value<double?>? heightCentimeters,
    Value<double?>? weightKilograms,
    Value<int?>? maxHeartRate,
    Value<int?>? dailyStepGoal,
    Value<int>? updatedAtUtcMs,
  }) {
    return UserProfileCompanion(
      id: id ?? this.id,
      birthYear: birthYear ?? this.birthYear,
      sex: sex ?? this.sex,
      heightCentimeters: heightCentimeters ?? this.heightCentimeters,
      weightKilograms: weightKilograms ?? this.weightKilograms,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (birthYear.present) {
      map['birth_year'] = Variable<int>(birthYear.value);
    }
    if (sex.present) {
      map['sex'] = Variable<String>(sex.value);
    }
    if (heightCentimeters.present) {
      map['height_centimeters'] = Variable<double>(heightCentimeters.value);
    }
    if (weightKilograms.present) {
      map['weight_kilograms'] = Variable<double>(weightKilograms.value);
    }
    if (maxHeartRate.present) {
      map['max_heart_rate'] = Variable<int>(maxHeartRate.value);
    }
    if (dailyStepGoal.present) {
      map['daily_step_goal'] = Variable<int>(dailyStepGoal.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserProfileCompanion(')
          ..write('id: $id, ')
          ..write('birthYear: $birthYear, ')
          ..write('sex: $sex, ')
          ..write('heightCentimeters: $heightCentimeters, ')
          ..write('weightKilograms: $weightKilograms, ')
          ..write('maxHeartRate: $maxHeartRate, ')
          ..write('dailyStepGoal: $dailyStepGoal, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }
}

class $ImportedSleepSessionsTable extends ImportedSleepSessions
    with TableInfo<$ImportedSleepSessionsTable, ImportedSleepSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedSleepSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtUtcMsMeta = const VerificationMeta(
    'importedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> importedAtUtcMs = GeneratedColumn<int>(
    'imported_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordId,
    source,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    importedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_sleep_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedSleepSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('imported_at_utc_ms')) {
      context.handle(
        _importedAtUtcMsMeta,
        importedAtUtcMs.isAcceptableOrUnknown(
          data['imported_at_utc_ms']!,
          _importedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordId};
  @override
  ImportedSleepSessionRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedSleepSessionRow(
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      importedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at_utc_ms'],
      )!,
    );
  }

  @override
  $ImportedSleepSessionsTable createAlias(String alias) {
    return $ImportedSleepSessionsTable(attachedDatabase, alias);
  }
}

class ImportedSleepSessionRow extends DataClass
    implements Insertable<ImportedSleepSessionRow> {
  final String recordId;
  final String source;
  final int startUtcMs;
  final int endUtcMs;
  final int offsetMinutes;
  final int importedAtUtcMs;
  const ImportedSleepSessionRow({
    required this.recordId,
    required this.source,
    required this.startUtcMs,
    required this.endUtcMs,
    required this.offsetMinutes,
    required this.importedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_id'] = Variable<String>(recordId);
    map['source'] = Variable<String>(source);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['imported_at_utc_ms'] = Variable<int>(importedAtUtcMs);
    return map;
  }

  ImportedSleepSessionsCompanion toCompanion(bool nullToAbsent) {
    return ImportedSleepSessionsCompanion(
      recordId: Value(recordId),
      source: Value(source),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
      offsetMinutes: Value(offsetMinutes),
      importedAtUtcMs: Value(importedAtUtcMs),
    );
  }

  factory ImportedSleepSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedSleepSessionRow(
      recordId: serializer.fromJson<String>(json['recordId']),
      source: serializer.fromJson<String>(json['source']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      importedAtUtcMs: serializer.fromJson<int>(json['importedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordId': serializer.toJson<String>(recordId),
      'source': serializer.toJson<String>(source),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'importedAtUtcMs': serializer.toJson<int>(importedAtUtcMs),
    };
  }

  ImportedSleepSessionRow copyWith({
    String? recordId,
    String? source,
    int? startUtcMs,
    int? endUtcMs,
    int? offsetMinutes,
    int? importedAtUtcMs,
  }) => ImportedSleepSessionRow(
    recordId: recordId ?? this.recordId,
    source: source ?? this.source,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    importedAtUtcMs: importedAtUtcMs ?? this.importedAtUtcMs,
  );
  ImportedSleepSessionRow copyWithCompanion(
    ImportedSleepSessionsCompanion data,
  ) {
    return ImportedSleepSessionRow(
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      source: data.source.present ? data.source.value : this.source,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      importedAtUtcMs: data.importedAtUtcMs.present
          ? data.importedAtUtcMs.value
          : this.importedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSleepSessionRow(')
          ..write('recordId: $recordId, ')
          ..write('source: $source, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('importedAtUtcMs: $importedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordId,
    source,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    importedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedSleepSessionRow &&
          other.recordId == this.recordId &&
          other.source == this.source &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.importedAtUtcMs == this.importedAtUtcMs);
}

class ImportedSleepSessionsCompanion
    extends UpdateCompanion<ImportedSleepSessionRow> {
  final Value<String> recordId;
  final Value<String> source;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> importedAtUtcMs;
  final Value<int> rowid;
  const ImportedSleepSessionsCompanion({
    this.recordId = const Value.absent(),
    this.source = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.importedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportedSleepSessionsCompanion.insert({
    required String recordId,
    required String source,
    required int startUtcMs,
    required int endUtcMs,
    required int offsetMinutes,
    required int importedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : recordId = Value(recordId),
       source = Value(source),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs),
       offsetMinutes = Value(offsetMinutes),
       importedAtUtcMs = Value(importedAtUtcMs);
  static Insertable<ImportedSleepSessionRow> custom({
    Expression<String>? recordId,
    Expression<String>? source,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? importedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordId != null) 'record_id': recordId,
      if (source != null) 'source': source,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (importedAtUtcMs != null) 'imported_at_utc_ms': importedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportedSleepSessionsCompanion copyWith({
    Value<String>? recordId,
    Value<String>? source,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? importedAtUtcMs,
    Value<int>? rowid,
  }) {
    return ImportedSleepSessionsCompanion(
      recordId: recordId ?? this.recordId,
      source: source ?? this.source,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      importedAtUtcMs: importedAtUtcMs ?? this.importedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (importedAtUtcMs.present) {
      map['imported_at_utc_ms'] = Variable<int>(importedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSleepSessionsCompanion(')
          ..write('recordId: $recordId, ')
          ..write('source: $source, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('importedAtUtcMs: $importedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportedSleepStagesTable extends ImportedSleepStages
    with TableInfo<$ImportedSleepStagesTable, ImportedSleepStageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedSleepStagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES imported_sleep_sessions (record_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SleepStage, String> stage =
      GeneratedColumn<String>(
        'stage',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SleepStage>($ImportedSleepStagesTable.$converterstage);
  @override
  List<GeneratedColumn> get $columns => [recordId, startUtcMs, endUtcMs, stage];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_sleep_stages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedSleepStageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordId, startUtcMs};
  @override
  ImportedSleepStageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedSleepStageRow(
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      stage: $ImportedSleepStagesTable.$converterstage.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}stage'],
        )!,
      ),
    );
  }

  @override
  $ImportedSleepStagesTable createAlias(String alias) {
    return $ImportedSleepStagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SleepStage, String, String> $converterstage =
      const EnumNameConverter<SleepStage>(SleepStage.values);
}

class ImportedSleepStageRow extends DataClass
    implements Insertable<ImportedSleepStageRow> {
  final String recordId;
  final int startUtcMs;
  final int endUtcMs;
  final SleepStage stage;
  const ImportedSleepStageRow({
    required this.recordId,
    required this.startUtcMs,
    required this.endUtcMs,
    required this.stage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_id'] = Variable<String>(recordId);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    {
      map['stage'] = Variable<String>(
        $ImportedSleepStagesTable.$converterstage.toSql(stage),
      );
    }
    return map;
  }

  ImportedSleepStagesCompanion toCompanion(bool nullToAbsent) {
    return ImportedSleepStagesCompanion(
      recordId: Value(recordId),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
      stage: Value(stage),
    );
  }

  factory ImportedSleepStageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedSleepStageRow(
      recordId: serializer.fromJson<String>(json['recordId']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      stage: $ImportedSleepStagesTable.$converterstage.fromJson(
        serializer.fromJson<String>(json['stage']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordId': serializer.toJson<String>(recordId),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'stage': serializer.toJson<String>(
        $ImportedSleepStagesTable.$converterstage.toJson(stage),
      ),
    };
  }

  ImportedSleepStageRow copyWith({
    String? recordId,
    int? startUtcMs,
    int? endUtcMs,
    SleepStage? stage,
  }) => ImportedSleepStageRow(
    recordId: recordId ?? this.recordId,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    stage: stage ?? this.stage,
  );
  ImportedSleepStageRow copyWithCompanion(ImportedSleepStagesCompanion data) {
    return ImportedSleepStageRow(
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      stage: data.stage.present ? data.stage.value : this.stage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSleepStageRow(')
          ..write('recordId: $recordId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('stage: $stage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(recordId, startUtcMs, endUtcMs, stage);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedSleepStageRow &&
          other.recordId == this.recordId &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.stage == this.stage);
}

class ImportedSleepStagesCompanion
    extends UpdateCompanion<ImportedSleepStageRow> {
  final Value<String> recordId;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<SleepStage> stage;
  final Value<int> rowid;
  const ImportedSleepStagesCompanion({
    this.recordId = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.stage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportedSleepStagesCompanion.insert({
    required String recordId,
    required int startUtcMs,
    required int endUtcMs,
    required SleepStage stage,
    this.rowid = const Value.absent(),
  }) : recordId = Value(recordId),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs),
       stage = Value(stage);
  static Insertable<ImportedSleepStageRow> custom({
    Expression<String>? recordId,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<String>? stage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordId != null) 'record_id': recordId,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (stage != null) 'stage': stage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportedSleepStagesCompanion copyWith({
    Value<String>? recordId,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<SleepStage>? stage,
    Value<int>? rowid,
  }) {
    return ImportedSleepStagesCompanion(
      recordId: recordId ?? this.recordId,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      stage: stage ?? this.stage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(
        $ImportedSleepStagesTable.$converterstage.toSql(stage.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSleepStagesCompanion(')
          ..write('recordId: $recordId, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('stage: $stage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HealthReadsTable extends HealthReads
    with TableInfo<$HealthReadsTable, HealthReadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HealthReadsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumnWithTypeConverter<HealthRecordKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<HealthRecordKind>($HealthReadsTable.$converterkind);
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastReadAtUtcMsMeta = const VerificationMeta(
    'lastReadAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> lastReadAtUtcMs = GeneratedColumn<int>(
    'last_read_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, enabled, lastReadAtUtcMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'health_reads';
  @override
  VerificationContext validateIntegrity(
    Insertable<HealthReadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('last_read_at_utc_ms')) {
      context.handle(
        _lastReadAtUtcMsMeta,
        lastReadAtUtcMs.isAcceptableOrUnknown(
          data['last_read_at_utc_ms']!,
          _lastReadAtUtcMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind};
  @override
  HealthReadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HealthReadRow(
      kind: $HealthReadsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      lastReadAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at_utc_ms'],
      ),
    );
  }

  @override
  $HealthReadsTable createAlias(String alias) {
    return $HealthReadsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<HealthRecordKind, String, String> $converterkind =
      const EnumNameConverter<HealthRecordKind>(HealthRecordKind.values);
}

class HealthReadRow extends DataClass implements Insertable<HealthReadRow> {
  final HealthRecordKind kind;
  final bool enabled;
  final int? lastReadAtUtcMs;
  const HealthReadRow({
    required this.kind,
    required this.enabled,
    this.lastReadAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    {
      map['kind'] = Variable<String>(
        $HealthReadsTable.$converterkind.toSql(kind),
      );
    }
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || lastReadAtUtcMs != null) {
      map['last_read_at_utc_ms'] = Variable<int>(lastReadAtUtcMs);
    }
    return map;
  }

  HealthReadsCompanion toCompanion(bool nullToAbsent) {
    return HealthReadsCompanion(
      kind: Value(kind),
      enabled: Value(enabled),
      lastReadAtUtcMs: lastReadAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAtUtcMs),
    );
  }

  factory HealthReadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HealthReadRow(
      kind: $HealthReadsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      enabled: serializer.fromJson<bool>(json['enabled']),
      lastReadAtUtcMs: serializer.fromJson<int?>(json['lastReadAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(
        $HealthReadsTable.$converterkind.toJson(kind),
      ),
      'enabled': serializer.toJson<bool>(enabled),
      'lastReadAtUtcMs': serializer.toJson<int?>(lastReadAtUtcMs),
    };
  }

  HealthReadRow copyWith({
    HealthRecordKind? kind,
    bool? enabled,
    Value<int?> lastReadAtUtcMs = const Value.absent(),
  }) => HealthReadRow(
    kind: kind ?? this.kind,
    enabled: enabled ?? this.enabled,
    lastReadAtUtcMs: lastReadAtUtcMs.present
        ? lastReadAtUtcMs.value
        : this.lastReadAtUtcMs,
  );
  HealthReadRow copyWithCompanion(HealthReadsCompanion data) {
    return HealthReadRow(
      kind: data.kind.present ? data.kind.value : this.kind,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      lastReadAtUtcMs: data.lastReadAtUtcMs.present
          ? data.lastReadAtUtcMs.value
          : this.lastReadAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HealthReadRow(')
          ..write('kind: $kind, ')
          ..write('enabled: $enabled, ')
          ..write('lastReadAtUtcMs: $lastReadAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, enabled, lastReadAtUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HealthReadRow &&
          other.kind == this.kind &&
          other.enabled == this.enabled &&
          other.lastReadAtUtcMs == this.lastReadAtUtcMs);
}

class HealthReadsCompanion extends UpdateCompanion<HealthReadRow> {
  final Value<HealthRecordKind> kind;
  final Value<bool> enabled;
  final Value<int?> lastReadAtUtcMs;
  final Value<int> rowid;
  const HealthReadsCompanion({
    this.kind = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastReadAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HealthReadsCompanion.insert({
    required HealthRecordKind kind,
    this.enabled = const Value.absent(),
    this.lastReadAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : kind = Value(kind);
  static Insertable<HealthReadRow> custom({
    Expression<String>? kind,
    Expression<bool>? enabled,
    Expression<int>? lastReadAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (enabled != null) 'enabled': enabled,
      if (lastReadAtUtcMs != null) 'last_read_at_utc_ms': lastReadAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HealthReadsCompanion copyWith({
    Value<HealthRecordKind>? kind,
    Value<bool>? enabled,
    Value<int?>? lastReadAtUtcMs,
    Value<int>? rowid,
  }) {
    return HealthReadsCompanion(
      kind: kind ?? this.kind,
      enabled: enabled ?? this.enabled,
      lastReadAtUtcMs: lastReadAtUtcMs ?? this.lastReadAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(
        $HealthReadsTable.$converterkind.toSql(kind.value),
      );
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (lastReadAtUtcMs.present) {
      map['last_read_at_utc_ms'] = Variable<int>(lastReadAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HealthReadsCompanion(')
          ..write('kind: $kind, ')
          ..write('enabled: $enabled, ')
          ..write('lastReadAtUtcMs: $lastReadAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportedWorkoutsTable extends ImportedWorkouts
    with TableInfo<$ImportedWorkoutsTable, ImportedWorkoutRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedWorkoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityTypeMeta = const VerificationMeta(
    'activityType',
  );
  @override
  late final GeneratedColumn<String> activityType = GeneratedColumn<String>(
    'activity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startUtcMsMeta = const VerificationMeta(
    'startUtcMs',
  );
  @override
  late final GeneratedColumn<int> startUtcMs = GeneratedColumn<int>(
    'start_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUtcMsMeta = const VerificationMeta(
    'endUtcMs',
  );
  @override
  late final GeneratedColumn<int> endUtcMs = GeneratedColumn<int>(
    'end_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMinutesMeta = const VerificationMeta(
    'offsetMinutes',
  );
  @override
  late final GeneratedColumn<int> offsetMinutes = GeneratedColumn<int>(
    'offset_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtUtcMsMeta = const VerificationMeta(
    'importedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> importedAtUtcMs = GeneratedColumn<int>(
    'imported_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordId,
    source,
    activityType,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    importedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_workouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedWorkoutRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('activity_type')) {
      context.handle(
        _activityTypeMeta,
        activityType.isAcceptableOrUnknown(
          data['activity_type']!,
          _activityTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityTypeMeta);
    }
    if (data.containsKey('start_utc_ms')) {
      context.handle(
        _startUtcMsMeta,
        startUtcMs.isAcceptableOrUnknown(
          data['start_utc_ms']!,
          _startUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUtcMsMeta);
    }
    if (data.containsKey('end_utc_ms')) {
      context.handle(
        _endUtcMsMeta,
        endUtcMs.isAcceptableOrUnknown(data['end_utc_ms']!, _endUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endUtcMsMeta);
    }
    if (data.containsKey('offset_minutes')) {
      context.handle(
        _offsetMinutesMeta,
        offsetMinutes.isAcceptableOrUnknown(
          data['offset_minutes']!,
          _offsetMinutesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_offsetMinutesMeta);
    }
    if (data.containsKey('imported_at_utc_ms')) {
      context.handle(
        _importedAtUtcMsMeta,
        importedAtUtcMs.isAcceptableOrUnknown(
          data['imported_at_utc_ms']!,
          _importedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordId};
  @override
  ImportedWorkoutRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedWorkoutRow(
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      activityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_type'],
      )!,
      startUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_utc_ms'],
      )!,
      endUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_utc_ms'],
      )!,
      offsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset_minutes'],
      )!,
      importedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at_utc_ms'],
      )!,
    );
  }

  @override
  $ImportedWorkoutsTable createAlias(String alias) {
    return $ImportedWorkoutsTable(attachedDatabase, alias);
  }
}

class ImportedWorkoutRow extends DataClass
    implements Insertable<ImportedWorkoutRow> {
  final String recordId;
  final String source;
  final String activityType;
  final int startUtcMs;
  final int endUtcMs;
  final int offsetMinutes;
  final int importedAtUtcMs;
  const ImportedWorkoutRow({
    required this.recordId,
    required this.source,
    required this.activityType,
    required this.startUtcMs,
    required this.endUtcMs,
    required this.offsetMinutes,
    required this.importedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_id'] = Variable<String>(recordId);
    map['source'] = Variable<String>(source);
    map['activity_type'] = Variable<String>(activityType);
    map['start_utc_ms'] = Variable<int>(startUtcMs);
    map['end_utc_ms'] = Variable<int>(endUtcMs);
    map['offset_minutes'] = Variable<int>(offsetMinutes);
    map['imported_at_utc_ms'] = Variable<int>(importedAtUtcMs);
    return map;
  }

  ImportedWorkoutsCompanion toCompanion(bool nullToAbsent) {
    return ImportedWorkoutsCompanion(
      recordId: Value(recordId),
      source: Value(source),
      activityType: Value(activityType),
      startUtcMs: Value(startUtcMs),
      endUtcMs: Value(endUtcMs),
      offsetMinutes: Value(offsetMinutes),
      importedAtUtcMs: Value(importedAtUtcMs),
    );
  }

  factory ImportedWorkoutRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedWorkoutRow(
      recordId: serializer.fromJson<String>(json['recordId']),
      source: serializer.fromJson<String>(json['source']),
      activityType: serializer.fromJson<String>(json['activityType']),
      startUtcMs: serializer.fromJson<int>(json['startUtcMs']),
      endUtcMs: serializer.fromJson<int>(json['endUtcMs']),
      offsetMinutes: serializer.fromJson<int>(json['offsetMinutes']),
      importedAtUtcMs: serializer.fromJson<int>(json['importedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordId': serializer.toJson<String>(recordId),
      'source': serializer.toJson<String>(source),
      'activityType': serializer.toJson<String>(activityType),
      'startUtcMs': serializer.toJson<int>(startUtcMs),
      'endUtcMs': serializer.toJson<int>(endUtcMs),
      'offsetMinutes': serializer.toJson<int>(offsetMinutes),
      'importedAtUtcMs': serializer.toJson<int>(importedAtUtcMs),
    };
  }

  ImportedWorkoutRow copyWith({
    String? recordId,
    String? source,
    String? activityType,
    int? startUtcMs,
    int? endUtcMs,
    int? offsetMinutes,
    int? importedAtUtcMs,
  }) => ImportedWorkoutRow(
    recordId: recordId ?? this.recordId,
    source: source ?? this.source,
    activityType: activityType ?? this.activityType,
    startUtcMs: startUtcMs ?? this.startUtcMs,
    endUtcMs: endUtcMs ?? this.endUtcMs,
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    importedAtUtcMs: importedAtUtcMs ?? this.importedAtUtcMs,
  );
  ImportedWorkoutRow copyWithCompanion(ImportedWorkoutsCompanion data) {
    return ImportedWorkoutRow(
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      source: data.source.present ? data.source.value : this.source,
      activityType: data.activityType.present
          ? data.activityType.value
          : this.activityType,
      startUtcMs: data.startUtcMs.present
          ? data.startUtcMs.value
          : this.startUtcMs,
      endUtcMs: data.endUtcMs.present ? data.endUtcMs.value : this.endUtcMs,
      offsetMinutes: data.offsetMinutes.present
          ? data.offsetMinutes.value
          : this.offsetMinutes,
      importedAtUtcMs: data.importedAtUtcMs.present
          ? data.importedAtUtcMs.value
          : this.importedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedWorkoutRow(')
          ..write('recordId: $recordId, ')
          ..write('source: $source, ')
          ..write('activityType: $activityType, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('importedAtUtcMs: $importedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordId,
    source,
    activityType,
    startUtcMs,
    endUtcMs,
    offsetMinutes,
    importedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedWorkoutRow &&
          other.recordId == this.recordId &&
          other.source == this.source &&
          other.activityType == this.activityType &&
          other.startUtcMs == this.startUtcMs &&
          other.endUtcMs == this.endUtcMs &&
          other.offsetMinutes == this.offsetMinutes &&
          other.importedAtUtcMs == this.importedAtUtcMs);
}

class ImportedWorkoutsCompanion extends UpdateCompanion<ImportedWorkoutRow> {
  final Value<String> recordId;
  final Value<String> source;
  final Value<String> activityType;
  final Value<int> startUtcMs;
  final Value<int> endUtcMs;
  final Value<int> offsetMinutes;
  final Value<int> importedAtUtcMs;
  final Value<int> rowid;
  const ImportedWorkoutsCompanion({
    this.recordId = const Value.absent(),
    this.source = const Value.absent(),
    this.activityType = const Value.absent(),
    this.startUtcMs = const Value.absent(),
    this.endUtcMs = const Value.absent(),
    this.offsetMinutes = const Value.absent(),
    this.importedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportedWorkoutsCompanion.insert({
    required String recordId,
    required String source,
    required String activityType,
    required int startUtcMs,
    required int endUtcMs,
    required int offsetMinutes,
    required int importedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : recordId = Value(recordId),
       source = Value(source),
       activityType = Value(activityType),
       startUtcMs = Value(startUtcMs),
       endUtcMs = Value(endUtcMs),
       offsetMinutes = Value(offsetMinutes),
       importedAtUtcMs = Value(importedAtUtcMs);
  static Insertable<ImportedWorkoutRow> custom({
    Expression<String>? recordId,
    Expression<String>? source,
    Expression<String>? activityType,
    Expression<int>? startUtcMs,
    Expression<int>? endUtcMs,
    Expression<int>? offsetMinutes,
    Expression<int>? importedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordId != null) 'record_id': recordId,
      if (source != null) 'source': source,
      if (activityType != null) 'activity_type': activityType,
      if (startUtcMs != null) 'start_utc_ms': startUtcMs,
      if (endUtcMs != null) 'end_utc_ms': endUtcMs,
      if (offsetMinutes != null) 'offset_minutes': offsetMinutes,
      if (importedAtUtcMs != null) 'imported_at_utc_ms': importedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportedWorkoutsCompanion copyWith({
    Value<String>? recordId,
    Value<String>? source,
    Value<String>? activityType,
    Value<int>? startUtcMs,
    Value<int>? endUtcMs,
    Value<int>? offsetMinutes,
    Value<int>? importedAtUtcMs,
    Value<int>? rowid,
  }) {
    return ImportedWorkoutsCompanion(
      recordId: recordId ?? this.recordId,
      source: source ?? this.source,
      activityType: activityType ?? this.activityType,
      startUtcMs: startUtcMs ?? this.startUtcMs,
      endUtcMs: endUtcMs ?? this.endUtcMs,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      importedAtUtcMs: importedAtUtcMs ?? this.importedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (activityType.present) {
      map['activity_type'] = Variable<String>(activityType.value);
    }
    if (startUtcMs.present) {
      map['start_utc_ms'] = Variable<int>(startUtcMs.value);
    }
    if (endUtcMs.present) {
      map['end_utc_ms'] = Variable<int>(endUtcMs.value);
    }
    if (offsetMinutes.present) {
      map['offset_minutes'] = Variable<int>(offsetMinutes.value);
    }
    if (importedAtUtcMs.present) {
      map['imported_at_utc_ms'] = Variable<int>(importedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedWorkoutsCompanion(')
          ..write('recordId: $recordId, ')
          ..write('source: $source, ')
          ..write('activityType: $activityType, ')
          ..write('startUtcMs: $startUtcMs, ')
          ..write('endUtcMs: $endUtcMs, ')
          ..write('offsetMinutes: $offsetMinutes, ')
          ..write('importedAtUtcMs: $importedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $RingDevicesTable ringDevices = $RingDevicesTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $SyncLocksTable syncLocks = $SyncLocksTable(this);
  late final $SyncRunsTable syncRuns = $SyncRunsTable(this);
  late final $ActivityBucketsTable activityBuckets = $ActivityBucketsTable(
    this,
  );
  late final $HrSamplesTable hrSamples = $HrSamplesTable(this);
  late final $Spo2SamplesTable spo2Samples = $Spo2SamplesTable(this);
  late final $StressSamplesTable stressSamples = $StressSamplesTable(this);
  late final $HrvSamplesTable hrvSamples = $HrvSamplesTable(this);
  late final $SleepSessionsTable sleepSessions = $SleepSessionsTable(this);
  late final $SleepSegmentsTable sleepSegments = $SleepSegmentsTable(this);
  late final $WorkoutsTable workouts = $WorkoutsTable(this);
  late final $WorkoutHrSamplesTable workoutHrSamples = $WorkoutHrSamplesTable(
    this,
  );
  late final $WorkoutRoutePointsTable workoutRoutePoints =
      $WorkoutRoutePointsTable(this);
  late final $WorkoutPausesTable workoutPauses = $WorkoutPausesTable(this);
  late final $HealthOutboxTable healthOutbox = $HealthOutboxTable(this);
  late final $SourcePrioritiesTable sourcePriorities = $SourcePrioritiesTable(
    this,
  );
  late final $UserProfileTable userProfile = $UserProfileTable(this);
  late final $ImportedSleepSessionsTable importedSleepSessions =
      $ImportedSleepSessionsTable(this);
  late final $ImportedSleepStagesTable importedSleepStages =
      $ImportedSleepStagesTable(this);
  late final $HealthReadsTable healthReads = $HealthReadsTable(this);
  late final $ImportedWorkoutsTable importedWorkouts = $ImportedWorkoutsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    ringDevices,
    syncCursors,
    syncLocks,
    syncRuns,
    activityBuckets,
    hrSamples,
    spo2Samples,
    stressSamples,
    hrvSamples,
    sleepSessions,
    sleepSegments,
    workouts,
    workoutHrSamples,
    workoutRoutePoints,
    workoutPauses,
    healthOutbox,
    sourcePriorities,
    userProfile,
    importedSleepSessions,
    importedSleepStages,
    healthReads,
    importedWorkouts,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workouts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('workout_hr_samples', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workouts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('workout_route_points', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'workouts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('workout_pauses', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'imported_sleep_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('imported_sleep_stages', kind: UpdateKind.delete)],
    ),
  ]);
}
