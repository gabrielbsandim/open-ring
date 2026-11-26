import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/energy/application/energy_gate.dart';
import 'package:open_ring/features/trajectory/application/steps_what_if_providers.dart';
import 'package:open_ring/features/trajectory/domain/trajectory_view.dart';

import '../presentation/trajectory_screen_fixtures.dart';
import '../support/what_if_fixtures.dart';

Future<WhatIfView> _read(
  int extra, {
  double typical = 8700,
  TrajectoryView? view,
  EnergyGate gate = EnergyGate.on,
  bool hidden = false,
}) {
  final container = ProviderContainer(
    overrides: whatIfOverrides(
      view: view,
      typical: typical,
      gate: gate,
      hidden: hidden,
    ),
  );
  addTearDown(container.dispose);
  return container.read(whatIfProvider(extra).future);
}

WhatIfReady _ready(WhatIfView view) {
  expect(view, isA<WhatIfReady>());
  return view as WhatIfReady;
}

void main() {
  group('TR10b acceptance 1: +2000 steps at 178 cm, typical 8700', () {
    test('Ready scenario gives the prototype numbers', () async {
      final ready = _ready(await _read(2000));

      expect(ready.typical, 8700);
      expect(ready.toSteps, 10700);
      expect(ready.words, CohortWords.slightlyLower);
      expect(ready.clamped, isFalse);
      final weight = ready.weight!;
      expect(weight.kilometers, closeTo(1.48, 0.005));
      expect(weight.kgLess12, closeTo(0.49, 0.005));
      expect(weight.percentLower, closeTo(9.8, 0.05));
    });

    test('the family argument is the extra steps', () async {
      final one = _ready(await _read(1000));
      final three = _ready(await _read(3000));

      expect(one.toSteps, 9700);
      expect(three.toSteps, 11700);
      expect(one.weight!.kilometers, closeTo(0.74, 0.005));
      expect(three.weight!.kilometers, closeTo(2.22, 0.005));
    });
  });

  group('TR10b review focus: median steps not an integer', () {
    test('typical is the rounded trend median', () async {
      final up = _ready(await _read(2000, typical: 8699.6));
      final down = _ready(await _read(2000, typical: 8700.4));

      expect(up.typical, 8700);
      expect(down.typical, 8700);
      expect(up.toSteps, 10700);
    });
  });

  group('TR10b acceptance 2: hidden numbers', () {
    test('the provider still resolves a ready view with Energy on', () async {
      expect(await _read(2000, hidden: true), isA<WhatIfReady>());
    });
  });

  group('TR10b acceptance 3: refusals', () {
    for (final reason in TrajectoryRefusal.values) {
      test('${reason.name} gives WhatIfRefused with the reason', () async {
        final view = await _read(2000, view: TrajectoryRefused(reason));

        expect(view, isA<WhatIfRefused>());
        expect((view as WhatIfRefused).reason, reason);
      });
    }

    test('TrajectoryOff gives WhatIfOff', () async {
      expect(await _read(2000, view: const TrajectoryOff()), isA<WhatIfOff>());
    });

    test('TrajectoryError gives WhatIfError', () async {
      expect(
        await _read(2000, view: const TrajectoryError('boom')),
        isA<WhatIfError>(),
      );
    });
  });

  group('TR10b acceptance 4: Building and Guard', () {
    final views = <String, TrajectoryView>{
      'guard': guardView,
      'building': const TrajectoryBuilding(null),
    };
    for (final MapEntry(:key, :value) in views.entries) {
      test('$key keeps the cohort words and has no weight', () async {
        final ready = _ready(await _read(2000, view: value));

        expect(ready.weight, isNull);
        expect(ready.toSteps, 10700);
        expect(ready.words, CohortWords.slightlyLower);
      });
    }
  });

  group('TR10b acceptance 5: no steps trend', () {
    test('a null trend reports the valid day count', () async {
      final container = ProviderContainer(
        overrides: whatIfOverrides(levers: leversWith(validDays: 31)),
      );
      addTearDown(container.dispose);

      final view = await container.read(whatIfProvider(2000).future);

      expect(view, isA<WhatIfNoSteps>());
      expect((view as WhatIfNoSteps).validDays, 31);
    });

    test('zero valid days reports zero', () async {
      final container = ProviderContainer(
        overrides: whatIfOverrides(levers: leversWith(validDays: 0)),
      );
      addTearDown(container.dispose);

      final view = await container.read(whatIfProvider(2000).future);

      expect((view as WhatIfNoSteps).validDays, 0);
    });
  });

  group('TR10b acceptance 6: Energy gate never read for the weight', () {
    for (final gate in EnergyGate.values) {
      test('${gate.name} still gives the weight effect', () async {
        final ready = _ready(await _read(2000, gate: gate));

        expect(ready.weight!.kgLess12, closeTo(0.49, 0.005));
      });
    }
  });

  group('TR10b acceptance 7: clamped above the last Paluch anchor', () {
    test('typical 11500 is clamped', () async {
      final ready = _ready(await _read(2000, typical: 11500));

      expect(ready.clamped, isTrue);
      expect(ready.toSteps, 13500);
    });

    test('typical 9500 reaching 11500 is clamped by the destination', () async {
      final ready = _ready(await _read(2000, typical: 9500));

      expect(ready.toSteps, 11500);
      expect(ready.clamped, isTrue);
    });

    test('typical 8900 reaching 10900 is not clamped', () async {
      expect(_ready(await _read(2000, typical: 8900)).clamped, isFalse);
    });

    test('typical 8701 reaching 10701 is not clamped', () async {
      expect(_ready(await _read(2000, typical: 8701)).clamped, isFalse);
    });
  });
}
