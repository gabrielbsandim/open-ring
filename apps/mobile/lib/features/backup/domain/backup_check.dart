enum BackupProblem {
  notZip,
  missingManifest,
  foreignApp,
  unsupportedFormat,
  newerSchema,
  notSqlite,
  corrupt,
  unsafePath,
}

final class BackupCheck {
  const new ok(int this.schemaVersion) : problem = null;

  const new rejected(BackupProblem this.problem, {this.schemaVersion});

  final BackupProblem? problem;
  final int? schemaVersion;

  bool get ok => problem == null;
}

sealed class RestoreOutcome {
  const new();
}

final class Restored extends RestoreOutcome {
  const new(this.fromSchemaVersion);

  final int fromSchemaVersion;
}

final class Rejected extends RestoreOutcome {
  const new(this.check);

  final BackupCheck check;
}
