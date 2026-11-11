import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';

final _from = DateTime.utc(2026, 11);
final _to = DateTime.utc(2026, 11, 10);

void main() {
  test('kinds are deduplicated and kept in export order', () {
    final request = ExportRequest(
      from: _from,
      to: _to,
      kinds: const [ExportKind.workouts, ExportKind.sleep, ExportKind.sleep],
      format: ExportFormat.csv,
    );

    expect(request.kinds, [ExportKind.sleep, ExportKind.workouts]);
    expect(() => request.kinds.add(ExportKind.hrv), throwsUnsupportedError);
  });

  test('an empty or inverted range is rejected', () {
    expect(
      () => ExportRequest(
        from: _to,
        to: _from,
        kinds: const [ExportKind.sleep],
        format: ExportFormat.json,
      ),
      throwsArgumentError,
    );
    expect(
      () => ExportRequest(
        from: _from,
        to: _from,
        kinds: const [ExportKind.sleep],
        format: ExportFormat.json,
      ),
      throwsArgumentError,
    );
  });

  test('no kinds is rejected', () {
    expect(
      () => ExportRequest(
        from: _from,
        to: _to,
        kinds: const [],
        format: ExportFormat.csv,
      ),
      throwsArgumentError,
    );
  });

  test('column keys are unique per kind and file keys are unique', () {
    for (final kind in ExportKind.values) {
      expect(kind.columns.toSet(), hasLength(kind.columns.length));
    }
    expect(
      ExportKind.values.map((k) => k.key).toSet(),
      hasLength(ExportKind.values.length),
    );
  });
}
