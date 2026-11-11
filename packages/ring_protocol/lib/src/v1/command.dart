enum V1Command {
  setDateTime(0x01),
  battery(0x03),
  powerOff(0x08),
  heartRateLog(0x15),
  autoHeartRateSetting(0x16),
  continuousHeartRate(0x1E),
  autoSpo2Setting(0x2C),
  autoStressSetting(0x36),
  stressLog(0x37),
  autoHrvSetting(0x38),
  hrvLog(0x39),
  activityLog(0x43),
  legacySleep(0x44),
  todayActivity(0x48),
  findDevice(0x50),
  realTimeData(0x69),
  deviceNotify(0x73),
  bigData(0xBC),
  factoryReset(0xFF);

  new(this.id);

  final int id;

  static V1Command? fromId(int id) {
    for (final command in values) {
      if (command.id == id) return command;
    }
    return null;
  }
}

enum SettingAction {
  read(1),
  write(2),
  delete(3);

  new(this.id);

  final int id;
}

abstract final class BigDataId {
  static const temperature = 0x25;
  static const sleep = 0x27;
  static const spo2 = 0x2A;
}
