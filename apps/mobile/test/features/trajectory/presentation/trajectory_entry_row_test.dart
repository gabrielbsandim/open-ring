import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/features/body/application/hide_numbers_controller.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/settings/application/unit_format.dart';
import 'package:open_ring/features/settings/application/unit_system_controller.dart';
import 'package:open_ring/features/settings/domain/unit_system.dart';
import 'package:open_ring/features/trajectory/application/trajectory_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';
import 'package:open_ring/features/trajectory/presentation/trajectory_entry_row.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

import '../../../helpers/layout_harness.dart';
import 'trajectory_screen_fixtures.dart';

const _en = Locale('en');
const Set<ModuleId> _on = {ModuleId.body, ModuleId.trajectory};
const _building = TrajectoryBuilding(
  WeightRateBuilding(daysMissing: 6, spanMissing: 4),
);

AppLocalizations get _l10n => lookupAppLocalizations(_en);

UnitFormat _units(UnitSystem system) => UnitFormat(
  MetricFormat(lookupAppLocalizations(_en), _en.toString()),
  system,
);

class _Reads {
  int views = 0;
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required TrajectoryEntry from,
  TrajectoryView? view,
  Set<ModuleId> modules = _on,
  Future<TrajectoryView> Function()? load,
  _Reads? reads,
  bool hidden = false,
  UnitSystem units = UnitSystem.metric,
  double scale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = _en,
}) async {
  final router = stubRouter(
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: TrajectoryEntryRow(from: from),
      ),
    ),
  );
  await pumpScaled(
    tester,
    routerHost(router),
    textScaler: TextScaler.linear(scale),
    brightness: brightness,
    locale: locale,
    overrides: [
      moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
      trajectoryViewProvider.overrideWith((ref) {
        reads?.views++;
        return load?.call() ?? Future.value(view ?? readyView());
      }),
      unitSystemStoreProvider.overrideWithValue(InMemoryUnitSystemStore(units)),
      hideNumbersStoreProvider.overrideWithValue(
        InMemoryHideNumbersStore(hidden: hidden),
      ),
    ],
  );
  return router;
}

String _rowText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(TrajectoryEntryRow.rowKey),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('|');

void main() {
  for (final from in TrajectoryEntry.values) {
    group('from ${from.name}', () {
      testWidgets('acceptance 7: Ready reads the 12 week low to high', (
        tester,
      ) async {
        final view = readyView();
        final units = _units(UnitSystem.metric);
        await _pump(tester, from: from, view: view);

        final text = _rowText(tester);
        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
        expect(text, contains(_l10n.trajectoryTitle));
        expect(text, contains(units.bodyWeightNumber(view.band.low)));
        expect(text, contains(units.bodyWeightNumber(view.band.high)));
        expect(text, contains('12'));
      });

      testWidgets('acceptance 7: imperial Ready reads pounds only', (
        tester,
      ) async {
        final view = readyView();
        final units = _units(UnitSystem.imperial);
        await _pump(tester, from: from, view: view, units: UnitSystem.imperial);

        final text = _rowText(tester);
        expect(text, contains(units.bodyWeightNumber(view.band.low)));
        expect(text, contains(units.bodyWeightNumber(view.band.high)));
        expect(text, contains('lb'));
        expect(text, isNot(contains('kg')));
      });

      testWidgets('acceptance 7: Ready with numbers hidden is generic', (
        tester,
      ) async {
        final view = readyView();
        final units = _units(UnitSystem.metric);
        await _pump(tester, from: from, view: view, hidden: true);

        final text = _rowText(tester);
        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
        expect(text, contains(_l10n.trajectoryTitle));
        expect(text, isNot(contains(units.bodyWeightNumber(view.band.low))));
        expect(text, isNot(contains(units.bodyWeightNumber(view.band.high))));
        expect(text, isNot(contains('kg')));
        expect(text, isNot(contains('lb')));
      });

      testWidgets('acceptance 7: every other state shares one generic '
          'subtitle', (tester) async {
        final generic = <String, String>{};
        final states = <String, TrajectoryView>{
          'hidden Ready': readyView(),
          'Building': _building,
          'Building none': const TrajectoryBuilding(null),
          'Guard': guardView,
          'Refused': const TrajectoryRefused(TrajectoryRefusal.noHeight),
          'Error': TrajectoryError(StateError('x')),
        };
        for (final MapEntry(:key, :value) in states.entries) {
          await tester.pumpWidget(const SizedBox());
          await _pump(
            tester,
            from: from,
            view: value,
            hidden: key == 'hidden Ready',
          );
          expect(
            find.byKey(TrajectoryEntryRow.rowKey),
            findsOneWidget,
            reason: key,
          );
          generic[key] = _rowText(tester);
        }

        expect(generic.values.toSet(), hasLength(1), reason: '$generic');
        final ready = readyView();
        final units = _units(UnitSystem.metric);
        final readyText = await _readyText(tester, from);
        expect(readyText, isNot(generic.values.first));
        expect(readyText, contains(units.bodyWeightNumber(ready.band.low)));
      });

      testWidgets('acceptance 7: a tap pushes the trajectory screen', (
        tester,
      ) async {
        final router = await _pump(tester, from: from);

        await tester.tap(find.byKey(TrajectoryEntryRow.rowKey));
        await tester.pumpAndSettle();

        expect(find.text(trajectoryStub), findsOneWidget);
        expect(router.canPop(), isTrue);
      });

      testWidgets('acceptance 7: a generic row also opens the screen', (
        tester,
      ) async {
        await _pump(tester, from: from, view: guardView);

        await tester.tap(find.byKey(TrajectoryEntryRow.rowKey));
        await tester.pumpAndSettle();

        expect(find.text(trajectoryStub), findsOneWidget);
      });

      testWidgets('the row is hidden on Off', (tester) async {
        await _pump(tester, from: from, view: const TrajectoryOff());

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
      });

      testWidgets('the row is hidden on an AsyncError of the view', (
        tester,
      ) async {
        await _pump(
          tester,
          from: from,
          load: () => Future.error(StateError('view')),
        );

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
      });

      testWidgets('the row is hidden while the view loads', (tester) async {
        final pending = Completer<TrajectoryView>();
        await _pump(tester, from: from, load: () => pending.future);

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
        pending.complete(readyView());
        await tester.pumpAndSettle();

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
      });

      testWidgets('acceptance 8: module off shows no row and never reads '
          'the view', (tester) async {
        final reads = _Reads();
        await _pump(
          tester,
          from: from,
          modules: const {ModuleId.body},
          reads: reads,
        );

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
        expect(reads.views, 0);
      });

      testWidgets('acceptance 8: no module on at all reads no view', (
        tester,
      ) async {
        final reads = _Reads();
        await _pump(tester, from: from, modules: const {}, reads: reads);

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsNothing);
        expect(reads.views, 0);
      });

      testWidgets('acceptance 8: module on reads the view', (tester) async {
        final reads = _Reads();
        await _pump(tester, from: from, reads: reads);

        expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
        expect(reads.views, greaterThan(0));
      });

      group('acceptance 9: no overflow', () {
        for (final layout in layoutMatrix()) {
          testWidgets('Ready at $layout', (tester) async {
            await _pump(
              tester,
              from: from,
              scale: layout.scale,
              brightness: layout.brightness,
              locale: layout.locale,
            );

            expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
          });

          testWidgets('generic at $layout', (tester) async {
            await _pump(
              tester,
              from: from,
              view: guardView,
              scale: layout.scale,
              brightness: layout.brightness,
              locale: layout.locale,
            );

            expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
          });

          testWidgets('hidden numbers at $layout', (tester) async {
            await _pump(
              tester,
              from: from,
              hidden: true,
              scale: layout.scale,
              brightness: layout.brightness,
              locale: layout.locale,
            );

            expect(find.byKey(TrajectoryEntryRow.rowKey), findsOneWidget);
          });
        }
      });
    });
  }
}

Future<String> _readyText(WidgetTester tester, TrajectoryEntry from) async {
  await tester.pumpWidget(const SizedBox());
  await _pump(tester, from: from);
  return _rowText(tester);
}
