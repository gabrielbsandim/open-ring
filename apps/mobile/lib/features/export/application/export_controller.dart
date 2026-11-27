import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/export/application/export_providers.dart';
import 'package:open_ring/features/export/domain/data_exporter.dart';
import 'package:open_ring/features/export/domain/export_kind.dart';
import 'package:open_ring/features/export/domain/export_request.dart';
import 'package:open_ring/features/export/domain/file_sharer.dart';
import 'package:open_ring/features/export/infrastructure/share_plus_file_sharer.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

enum ExportRange { week, month, all }

enum ExportPhase { idle, running, done, failed }

final _allTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

// A kind that belongs to a module is offered only while that module is on.
const Map<ExportKind, ModuleId> _kindModule = {
  ExportKind.weighIns: ModuleId.body,
  ExportKind.dayTags: ModuleId.openScore,
};

bool _offered(ExportKind kind, Set<ModuleId> enabled) {
  final module = _kindModule[kind];
  return module == null || enabled.contains(module);
}

final exportKindsProvider = Provider<Set<ExportKind>>((ref) {
  final enabled = ref.watch(enabledModulesProvider).value ?? const {};
  return {
    for (final kind in ExportKind.values)
      if (_offered(kind, enabled)) kind,
  };
});

ExportRequest exportRequestFor(
  ExportState state,
  DateTime now, {
  Set<ExportKind>? offered,
}) {
  final to = now.add(const Duration(milliseconds: 1));
  final from = switch (state.range) {
    ExportRange.week => now.subtract(const Duration(days: 7)),
    ExportRange.month => now.subtract(const Duration(days: 30)),
    ExportRange.all => _allTime,
  };
  return ExportRequest(
    from: from,
    to: to,
    kinds: offered == null ? state.kinds : state.kinds.intersection(offered),
    format: state.format,
  );
}

String exportFileName(ExportFile file) =>
    file.path.split(RegExp(r'[/\\]')).last;

@immutable
final class ExportState {
  new({
    this.range = ExportRange.month,
    Set<ExportKind>? kinds,
    this.format = ExportFormat.csv,
    this.phase = ExportPhase.idle,
    this.result,
    this.shareFailed = false,
  }) : kinds = Set.unmodifiable(kinds ?? ExportKind.values);

  final ExportRange range;
  final Set<ExportKind> kinds;
  final ExportFormat format;
  final ExportPhase phase;
  final ExportResult? result;
  final bool shareFailed;

  bool get running => phase == ExportPhase.running;

  bool canRunWith(Set<ExportKind> offered) =>
      !running && kinds.any(offered.contains);

  ExportState withOptions({
    ExportRange? range,
    Set<ExportKind>? kinds,
    ExportFormat? format,
  }) {
    if (running) return this;
    return ExportState(
      range: range ?? this.range,
      kinds: kinds ?? this.kinds,
      format: format ?? this.format,
    );
  }

  ExportState _at(ExportPhase phase, {ExportResult? result, bool? share}) =>
      ExportState(
        range: range,
        kinds: kinds,
        format: format,
        phase: phase,
        result: result,
        shareFailed: share ?? false,
      );

  ExportState started() => _at(ExportPhase.running);

  ExportState completed(ExportResult result) =>
      _at(ExportPhase.done, result: result);

  ExportState failed() => _at(ExportPhase.failed);

  ExportState sharing({required bool failed}) =>
      _at(phase, result: result, share: failed);
}

final fileSharerProvider = Provider<FileSharer>(
  (ref) => const SharePlusFileSharer(),
);

final exportProvider = NotifierProvider<ExportController, ExportState>(
  ExportController.new,
);

class ExportController extends Notifier<ExportState> {
  @override
  ExportState build() => ExportState();

  void selectRange(ExportRange range) =>
      state = state.withOptions(range: range);

  void selectFormat(ExportFormat format) =>
      state = state.withOptions(format: format);

  void toggleKind(ExportKind kind) {
    final kinds = {...state.kinds};
    if (!kinds.remove(kind)) kinds.add(kind);
    state = state.withOptions(kinds: kinds);
  }

  Future<void> run() async {
    final offered = ref.read(exportKindsProvider);
    if (!state.canRunWith(offered)) return;
    final request = exportRequestFor(
      state,
      ref.read(clockProvider)(),
      offered: offered,
    );
    state = state.started();
    try {
      final result = await ref.read(dataExporterProvider).export(request);
      if (!ref.mounted) return;
      state = state.completed(result);
    } on Object {
      if (!ref.mounted) return;
      state = state.failed();
    }
  }

  Future<void> share() async {
    final result = state.result;
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(fileSharerProvider)
          .share(result.files, subject: exportFileName(result.files.first));
      if (!ref.mounted) return;
      state = state.sharing(failed: false);
    } on Object {
      if (!ref.mounted) return;
      state = state.sharing(failed: true);
    }
  }
}
