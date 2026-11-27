import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/app/l10n/app_locales.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/effort/presentation/effort_rating_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';
import 'package:open_ring/features/workout/domain/workout_type.dart';

import '../../helpers/ble_fakes.dart';
import '../../helpers/layout_harness.dart';
import '../../helpers/ring_fakes.dart';
import '../../helpers/workout_fakes.dart';
import '../../helpers/workout_rating_fakes.dart';
import '../workout/presentation/workout_scenarios.dart';

const _recordId = 'ride';
const _ratings = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

SavedWorkout _saved({int? rating}) {
  final run = savedRun();
  return SavedWorkout(
    id: run.id,
    workout: run.workout,
    utcOffset: run.utcOffset,
    health: run.health,
    rating: rating,
  );
}

ImportedWorkout _imported({int? rating}) => ImportedWorkout(
  recordId: _recordId,
  source: 'com.garmin.android.apps.connectmobile',
  type: WorkoutType.cycling,
  start: workoutStart,
  end: workoutStart.add(const Duration(minutes: 45)),
  utcOffset: Duration.zero,
  rating: rating,
);

MemoryRatings _memory({int? rating, int? importedRating}) => MemoryRatings(
  saved: [_saved(rating: rating)],
  imported: [_imported(rating: importedRating)],
);

Widget _recorded() => const EffortRatingCard.recorded(workoutId: savedRunId);

Widget _importedCard() => const EffortRatingCard.imported(recordId: _recordId);

List<Override> _overrides(MemoryRatings memory, Set<ModuleId> modules) => [
  ...bleOverrides(),
  ...ringOverrides(),
  moduleStoreProvider.overrideWithValue(InMemoryModuleStore(modules)),
  workoutHistoryReaderProvider.overrideWithValue(memory),
  importedWorkoutReaderProvider.overrideWithValue(ImportedRatings(memory)),
  workoutRatingStoreProvider.overrideWithValue(memory),
];

Future<void> _pump(
  WidgetTester tester,
  MemoryRatings memory, {
  Widget? card,
  Set<ModuleId> modules = const {ModuleId.effort},
  Locale locale = const Locale('en'),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  Size size = tallPhone,
}) => pumpScaled(
  tester,
  screenHost(Scaffold(body: SingleChildScrollView(child: card ?? _recorded()))),
  textScaler: TextScaler.linear(scale),
  brightness: brightness,
  locale: locale,
  size: size,
  overrides: _overrides(memory, modules),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(EffortRatingCard)));

int _revision(WidgetTester tester) =>
    _container(tester).read(dataRevisionProvider);

Finder _option(int rating) => find.byKey(EffortRatingKeys.option(rating));

Finder _key(Key key) => find.byKey(key);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Iterable<String> _texts(WidgetTester tester, Key key) sync* {
  final found = find.descendant(
    of: find.byKey(key),
    matching: find.byType(Text),
    matchRoot: true,
  );
  for (final text in tester.widgetList<Text>(found)) {
    yield text.data ?? text.textSpan?.toPlainText() ?? '';
  }
}

void _expectGrid(bool shown) {
  for (final rating in _ratings) {
    expect(
      _option(rating),
      shown ? findsOneWidget : findsNothing,
      reason: 'option $rating',
    );
  }
}

bool _selected(WidgetTester tester, int rating) =>
    tester.getSemantics(_option(rating)).flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  group('the gate', () {
    testWidgets('module off: a recorded workout shows no card', (tester) async {
      await _pump(tester, _memory(), modules: const {ModuleId.openScore});

      expect(_key(EffortRatingKeys.card), findsNothing);
      _expectGrid(false);
    });

    testWidgets('module off: an imported workout shows no card', (
      tester,
    ) async {
      await _pump(
        tester,
        _memory(),
        card: _importedCard(),
        modules: const {ModuleId.openScore},
      );

      expect(_key(EffortRatingKeys.card), findsNothing);
      _expectGrid(false);
    });

    testWidgets('a recorded workout that is not stored shows no card', (
      tester,
    ) async {
      await _pump(tester, MemoryRatings());

      expect(_key(EffortRatingKeys.card), findsNothing);
    });

    testWidgets('an imported workout that is not stored shows no card', (
      tester,
    ) async {
      await _pump(tester, MemoryRatings(), card: _importedCard());

      expect(_key(EffortRatingKeys.card), findsNothing);
    });

    testWidgets('module on: the card asks with the ten options', (
      tester,
    ) async {
      await _pump(tester, _memory());

      expect(_key(EffortRatingKeys.card), findsOneWidget);
      _expectGrid(true);
      expect(_key(EffortRatingKeys.skip), findsOneWidget);
      expect(_key(EffortRatingKeys.value), findsNothing);
      expect(_key(EffortRatingKeys.change), findsNothing);
      expect(_key(EffortRatingKeys.failed), findsNothing);
    });

    testWidgets('turning the module off hides a card that was showing', (
      tester,
    ) async {
      await _pump(tester, _memory());
      expect(_key(EffortRatingKeys.card), findsOneWidget);

      await _container(tester)
          .read(enabledModulesProvider.notifier)
          .disable(ModuleId.effort);
      await tester.pumpAndSettle();

      expect(_key(EffortRatingKeys.card), findsNothing);
    });
  });

  group('rating a workout', () {
    testWidgets('tapping 7 stores 7, bumps the revision once, shows it', (
      tester,
    ) async {
      final memory = _memory();
      await _pump(tester, memory);
      final before = _revision(tester);

      await _tap(tester, _option(7));

      expect(memory.recorded, [(savedRunId, 7)]);
      expect(memory.ratingOfSaved(savedRunId), 7);
      expect(_revision(tester), before + 1);
      expect(_texts(tester, EffortRatingKeys.value), contains(contains('7')));
      expect(_key(EffortRatingKeys.change), findsOneWidget);
      expect(_key(EffortRatingKeys.failed), findsNothing);
      _expectGrid(false);
    });

    testWidgets('the lowest and the highest rating are stored as they are', (
      tester,
    ) async {
      final memory = _memory();
      await _pump(tester, memory);
      await _tap(tester, _option(1));
      expect(memory.recorded.last, (savedRunId, 1));

      await _tap(tester, _key(EffortRatingKeys.change));
      await _tap(tester, _option(10));
      expect(memory.recorded.last, (savedRunId, 10));
      expect(_texts(tester, EffortRatingKeys.value), contains(contains('10')));
    });

    testWidgets('an imported workout stores through the imported path', (
      tester,
    ) async {
      final memory = _memory();
      await _pump(tester, memory, card: _importedCard());
      final before = _revision(tester);

      await _tap(tester, _option(4));

      expect(memory.importedWrites, [(_recordId, 4)]);
      expect(memory.recorded, isEmpty);
      expect(_revision(tester), before + 1);
      expect(_texts(tester, EffortRatingKeys.value), contains(contains('4')));
      expect(_key(EffortRatingKeys.change), findsOneWidget);
    });

    testWidgets('a rating already stored shows its value and Change', (
      tester,
    ) async {
      await _pump(tester, _memory(rating: 5));

      expect(_texts(tester, EffortRatingKeys.value), contains(contains('5')));
      expect(_key(EffortRatingKeys.change), findsOneWidget);
      expect(_key(EffortRatingKeys.skip), findsNothing);
      _expectGrid(false);
    });

    testWidgets('an imported rating already stored shows its value', (
      tester,
    ) async {
      await _pump(tester, _memory(importedRating: 9), card: _importedCard());

      expect(_texts(tester, EffortRatingKeys.value), contains(contains('9')));
      _expectGrid(false);
    });

    testWidgets('a second tap while the write is pending stores once', (
      tester,
    ) async {
      final memory = _memory()..hold = Completer<void>();
      await _pump(tester, memory);
      final before = _revision(tester);

      await tester.tap(_option(7));
      await tester.pump();
      await tester.tap(_option(8), warnIfMissed: false);
      await tester.pump();
      memory.hold!.complete();
      await tester.pumpAndSettle();

      expect(memory.recorded, [(savedRunId, 7)]);
      expect(_revision(tester), before + 1);
    });
  });

  group('the grid', () {
    testWidgets('a screen reader tap on an option rates', (tester) async {
      final memory = _memory();
      await _pump(tester, memory);
      final handle = tester.ensureSemantics();

      final node = tester.getSemantics(_option(7));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byPredicate((n) => n.id == node.id));
      await tester.pumpAndSettle();

      expect(memory.recorded, [(savedRunId, 7)]);
      handle.dispose();
    });

    testWidgets('wraps above text scale 1.3 and keeps the text scale', (
      tester,
    ) async {
      await _pump(tester, _memory(), scale: 2);

      expect(
        find.descendant(
          of: _key(EffortRatingKeys.card),
          matching: find.byType(Wrap),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key(EffortRatingKeys.card),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps 48 dp options on a 320 dp wide screen', (tester) async {
      await _pump(tester, _memory(), size: const Size(320, 800));

      for (final rating in _ratings) {
        final size = tester.getSize(_option(rating));
        expect(size.width, greaterThanOrEqualTo(48), reason: '$rating');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$rating');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a write that ends after the card left still bumps', (
      tester,
    ) async {
      final memory = _memory()..hold = Completer<void>();
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await _pump(
        tester,
        memory,
        card: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, visible, _) =>
              visible ? _recorded() : const SizedBox.shrink(),
        ),
      );
      final container = _container(tester);
      final before = container.read(dataRevisionProvider);

      await tester.tap(_option(7));
      await tester.pump();
      shown.value = false;
      await tester.pump();
      expect(find.byType(EffortRatingCard), findsNothing);
      memory.hold!.complete();
      await tester.pumpAndSettle();

      expect(memory.ratingOfSaved(savedRunId), 7);
      expect(container.read(dataRevisionProvider), before + 1);
    });
  });

  group('skipping', () {
    testWidgets('writes nothing and offers to rate it now', (tester) async {
      final memory = _memory();
      await _pump(tester, memory);
      final before = _revision(tester);

      await _tap(tester, _key(EffortRatingKeys.skip));

      expect(memory.recorded, isEmpty);
      expect(memory.importedWrites, isEmpty);
      expect(_revision(tester), before);
      expect(_key(EffortRatingKeys.card), findsOneWidget);
      expect(_key(EffortRatingKeys.rateNow), findsOneWidget);
      expect(_key(EffortRatingKeys.skip), findsNothing);
      expect(_key(EffortRatingKeys.value), findsNothing);
      _expectGrid(false);
    });

    testWidgets('Rate it now brings the grid back, still nothing stored', (
      tester,
    ) async {
      final memory = _memory();
      await _pump(tester, memory);
      await _tap(tester, _key(EffortRatingKeys.skip));

      await _tap(tester, _key(EffortRatingKeys.rateNow));

      _expectGrid(true);
      expect(memory.recorded, isEmpty);
    });

    testWidgets('survives a revision bump that rebuilds the screen', (
      tester,
    ) async {
      await _pump(tester, _memory());
      await _tap(tester, _key(EffortRatingKeys.skip));

      _container(tester).read(dataRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();

      expect(_key(EffortRatingKeys.rateNow), findsOneWidget);
      _expectGrid(false);
    });

    testWidgets('survives being scrolled far out of a lazy list', (
      tester,
    ) async {
      await pumpScaled(
        tester,
        screenHost(
          Scaffold(
            body: ListView(
              children: [const SizedBox(height: 4000), _recorded()],
            ),
          ),
        ),
        textScaler: TextScaler.noScaling,
        brightness: Brightness.dark,
        locale: const Locale('en'),
        size: tallPhone,
        overrides: _overrides(_memory(), const {ModuleId.effort}),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      await _tap(tester, _key(EffortRatingKeys.skip));

      await tester.drag(find.byType(ListView), const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(_key(EffortRatingKeys.rateNow), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(_key(EffortRatingKeys.rateNow), findsOneWidget);
      _expectGrid(false);
    });

    testWidgets('a fresh visit asks again', (tester) async {
      final memory = _memory();
      await _pump(tester, memory);
      await _tap(tester, _key(EffortRatingKeys.skip));
      expect(_key(EffortRatingKeys.rateNow), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, memory);

      _expectGrid(true);
      expect(_key(EffortRatingKeys.skip), findsOneWidget);
      expect(_key(EffortRatingKeys.rateNow), findsNothing);
      expect(memory.recorded, isEmpty);
    });

    testWidgets('an imported workout skips the same way', (tester) async {
      final memory = _memory();
      await _pump(tester, memory, card: _importedCard());

      await _tap(tester, _key(EffortRatingKeys.skip));

      expect(memory.importedWrites, isEmpty);
      expect(_key(EffortRatingKeys.rateNow), findsOneWidget);
    });
  });

  group('changing and removing', () {
    testWidgets('Change opens the grid with the current value selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _memory(rating: 7));

      await _tap(tester, _key(EffortRatingKeys.change));

      _expectGrid(true);
      expect(_key(EffortRatingKeys.clear), findsOneWidget);
      for (final rating in _ratings) {
        expect(_selected(tester, rating), rating == 7, reason: '$rating');
      }
      handle.dispose();
    });

    testWidgets('choosing another option stores it and closes the grid', (
      tester,
    ) async {
      final memory = _memory(rating: 7);
      await _pump(tester, memory);
      await _tap(tester, _key(EffortRatingKeys.change));
      final before = _revision(tester);

      await _tap(tester, _option(3));

      expect(memory.recorded, [(savedRunId, 3)]);
      expect(memory.ratingOfSaved(savedRunId), 3);
      expect(_revision(tester), before + 1);
      expect(_texts(tester, EffortRatingKeys.value), contains(contains('3')));
      _expectGrid(false);
    });

    testWidgets('Remove rating writes null and the card asks again', (
      tester,
    ) async {
      final memory = _memory(rating: 7);
      await _pump(tester, memory);
      await _tap(tester, _key(EffortRatingKeys.change));
      final before = _revision(tester);

      await _tap(tester, _key(EffortRatingKeys.clear));

      expect(memory.recorded, [(savedRunId, null)]);
      expect(memory.ratingOfSaved(savedRunId), isNull);
      expect(_revision(tester), before + 1);
      expect(_key(EffortRatingKeys.value), findsNothing);
      expect(_key(EffortRatingKeys.change), findsNothing);
      _expectGrid(true);
      expect(_key(EffortRatingKeys.skip), findsOneWidget);
      expect(_key(EffortRatingKeys.clear), findsNothing);
    });

    testWidgets('Remove rating on an imported workout writes null', (
      tester,
    ) async {
      final memory = _memory(importedRating: 6);
      await _pump(tester, memory, card: _importedCard());
      await _tap(tester, _key(EffortRatingKeys.change));

      await _tap(tester, _key(EffortRatingKeys.clear));

      expect(memory.importedWrites, [(_recordId, null)]);
      expect(memory.ratingOfImported(_recordId), isNull);
      _expectGrid(true);
    });

    testWidgets('an unrated card offers no Remove rating', (tester) async {
      await _pump(tester, _memory());

      expect(_key(EffortRatingKeys.clear), findsNothing);
    });
  });

  group('a write that fails', () {
    testWidgets('is said and leaves the card as it was', (tester) async {
      final memory = _memory()..failure = StateError('disk full');
      await _pump(tester, memory);
      final before = _revision(tester);

      await _tap(tester, _option(7));

      expect(memory.recorded, [(savedRunId, 7)]);
      expect(memory.ratingOfSaved(savedRunId), isNull);
      expect(_key(EffortRatingKeys.failed), findsOneWidget);
      expect(_key(EffortRatingKeys.value), findsNothing);
      expect(_key(EffortRatingKeys.change), findsNothing);
      expect(_revision(tester), before);
      _expectGrid(true);
    });

    testWidgets('keeps the previous rating when a change fails', (
      tester,
    ) async {
      final memory = _memory(rating: 7);
      await _pump(tester, memory);
      await _tap(tester, _key(EffortRatingKeys.change));
      memory.failure = StateError('disk full');

      await _tap(tester, _option(3));

      expect(memory.ratingOfSaved(savedRunId), 7);
      expect(_key(EffortRatingKeys.failed), findsOneWidget);
      expect(
        _texts(tester, EffortRatingKeys.value),
        isNot(contains(contains('3'))),
      );
    });

    testWidgets('a failed removal keeps the stored rating and says so', (
      tester,
    ) async {
      final memory = _memory(rating: 7);
      await _pump(tester, memory);
      await _tap(tester, _key(EffortRatingKeys.change));
      memory.failure = StateError('disk full');

      await _tap(tester, _key(EffortRatingKeys.clear));

      expect(memory.ratingOfSaved(savedRunId), 7);
      expect(_key(EffortRatingKeys.failed), findsOneWidget);
    });

    testWidgets('an imported write that fails is said too', (tester) async {
      final memory = _memory()..failure = StateError('disk full');
      await _pump(tester, memory, card: _importedCard());

      await _tap(tester, _option(2));

      expect(_key(EffortRatingKeys.failed), findsOneWidget);
      expect(memory.ratingOfImported(_recordId), isNull);
    });

    testWidgets('the next write that works clears the failure', (tester) async {
      final memory = _memory()..failure = StateError('disk full');
      await _pump(tester, memory);
      await _tap(tester, _option(7));
      expect(_key(EffortRatingKeys.failed), findsOneWidget);

      memory.failure = null;
      await _tap(tester, _option(7));

      expect(_key(EffortRatingKeys.failed), findsNothing);
      expect(memory.ratingOfSaved(savedRunId), 7);
      expect(_key(EffortRatingKeys.change), findsOneWidget);
    });
  });

  group('the write functions', () {
    late WidgetRef captured;

    Future<void> pumpRef(WidgetTester tester, MemoryRatings memory) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(memory, const {ModuleId.effort}),
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    testWidgets('rateRecordedWorkout writes, then bumps the revision once', (
      tester,
    ) async {
      final memory = _memory();
      await pumpRef(tester, memory);
      final before = captured.read(dataRevisionProvider);

      final done = await rateRecordedWorkout(captured, savedRunId, 8);

      expect(done, isTrue);
      expect(memory.recorded, [(savedRunId, 8)]);
      expect(captured.read(dataRevisionProvider), before + 1);
    });

    testWidgets('rateImportedWorkout writes, then bumps the revision once', (
      tester,
    ) async {
      final memory = _memory();
      await pumpRef(tester, memory);
      final before = captured.read(dataRevisionProvider);

      final done = await rateImportedWorkout(captured, _recordId, null);

      expect(done, isTrue);
      expect(memory.importedWrites, [(_recordId, null)]);
      expect(captured.read(dataRevisionProvider), before + 1);
    });

    testWidgets('a workout that is gone is reported as not written', (
      tester,
    ) async {
      final memory = MemoryRatings();
      await pumpRef(tester, memory);

      expect(await rateRecordedWorkout(captured, 99, 5), isFalse);
      expect(await rateImportedWorkout(captured, 'gone', 5), isFalse);
    });
  });

  group('the options are targets people can use', () {
    for (final scale in layoutScales) {
      testWidgets('each option is 48 dp with a label at $scale', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, _memory(), scale: scale);

        for (final rating in _ratings) {
          final size = tester.getSize(_option(rating));
          expect(size.width, greaterThanOrEqualTo(48), reason: '$rating');
          expect(size.height, greaterThanOrEqualTo(48), reason: '$rating');
          expect(
            tester.getSemantics(_option(rating)).label,
            contains('$rating'),
            reason: '$rating',
          );
        }
        handle.dispose();
      });
    }

    testWidgets('at scale 1 the ten options sit in two rows of five', (
      tester,
    ) async {
      await _pump(tester, _memory());

      final tops = {
        for (final rating in _ratings)
          rating: tester.getTopLeft(_option(rating)),
      };
      for (final rating in [2, 3, 4, 5]) {
        expect(tops[rating]!.dy, tops[1]!.dy, reason: 'row one, $rating');
        expect(tops[rating]!.dx, greaterThan(tops[rating - 1]!.dx));
      }
      for (final rating in [7, 8, 9, 10]) {
        expect(tops[rating]!.dy, tops[6]!.dy, reason: 'row two, $rating');
      }
      expect(tops[6]!.dy, greaterThan(tops[1]!.dy));
      expect(tops[6]!.dx, tops[1]!.dx);
    });

    testWidgets('a grid at scale 2 stays inside the screen', (tester) async {
      await _pump(tester, _memory(), scale: 2, locale: const Locale('de'));

      for (final rating in _ratings) {
        final box = tester.getRect(_option(rating));
        expect(box.left, greaterThanOrEqualTo(0), reason: '$rating');
        expect(
          box.right,
          lessThanOrEqualTo(phoneSize.width),
          reason: '$rating',
        );
      }
    });
  });

  group('layout in every locale', () {
    for (final locale in AppLocales.supported) {
      for (final scale in layoutScales) {
        for (final brightness in layoutBrightnesses) {
          final name = '$locale ${scale}x ${brightness.name}';

          testWidgets('the grid fits at $name', (tester) async {
            await _pump(
              tester,
              _memory(),
              locale: locale,
              scale: scale,
              brightness: brightness,
              size: phoneSize,
            );

            expect(_key(EffortRatingKeys.card), findsOneWidget);
            _expectGrid(true);
            expect(tester.takeException(), isNull);
          });

          testWidgets('the rated card fits at $name', (tester) async {
            await _pump(
              tester,
              _memory(rating: 7),
              locale: locale,
              scale: scale,
              brightness: brightness,
              size: phoneSize,
            );

            expect(_key(EffortRatingKeys.value), findsOneWidget);
            expect(_key(EffortRatingKeys.change), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }

      testWidgets('the failure, the skip and Change fit at $locale 2x', (
        tester,
      ) async {
        final memory = _memory()..failure = StateError('disk full');
        await _pump(tester, memory, locale: locale, scale: 2, size: phoneSize);
        await _tap(tester, _option(7));
        expect(_key(EffortRatingKeys.failed), findsOneWidget);

        memory.failure = null;
        await _tap(tester, _key(EffortRatingKeys.skip));
        expect(_key(EffortRatingKeys.rateNow), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
