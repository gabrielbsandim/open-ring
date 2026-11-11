import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/today/presentation/readiness_verdict.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

void main() {
  final pt = lookupAppLocalizations(const Locale('pt'));

  test('each score reads as the word of its band', () {
    expect(readinessVerdict(pt, 85), 'Prontidão ótima');
    expect(readinessVerdict(pt, 78), 'Prontidão boa');
    expect(readinessVerdict(pt, 60), 'Prontidão moderada');
    expect(readinessVerdict(pt, 54), 'Prontidão baixa');
  });
}
