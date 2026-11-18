import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/workout/presentation/workout_notification_how_screen.dart';

import '../../../helpers/layout_harness.dart';
import '../../../helpers/settings_fakes.dart';

const _english = {
  'Title': 'Workout notification',
  'Lead':
      'The numbers are the ones on the workout screen, worked out the same '
      'way.',
  'Shows': 'What it shows',
  'Fields':
      'Time and heart rate. With GPS, also distance and current pace, or '
      'speed when cycling.',
  'Zone':
      'Zone: in the title, from the max heart rate in Profile, or 220 minus '
      'your age. With neither, no zone.',
  'Paused': 'Paused: the stopped time and the distance, with Resume and End.',
  'Lock':
      'Lock screen: everything, unless Heart rate on the lock screen is off; '
      'then no heart rate and no zone.',
  'Sources': 'Where each number comes from',
  'Time': 'Time: counted by the phone from the start, without the pauses.',
  'HeartRate':
      'Heart rate: from the ring. If readings stop for 30 s while running and '
      'the connection stays open, it shows -- bpm, the title says the ring is '
      'out of range and Reconnect appears.',
  'Gps':
      "Distance and pace: the phone's GPS. Current pace uses the last 30 s of "
      'movement. If GPS fails, GPS signal lost takes their place.',
  'Updates': 'When it updates',
  'Cadence':
      'The time moves every second, kept by Android. Heart rate, distance and '
      'pace change at most every 2 s with the screen on. With the screen off '
      'they wait until it turns on; a pause, the end question or a lost ring '
      'do not wait.',
  'Buttons': 'The buttons',
  'End':
      'End pauses and asks. Save keeps the workout; Continue goes back to how '
      'it was. Discarding is only in the app.',
  'After': 'After the workout',
  'Result':
      'Only the save result stays, for up to 1 hour. Opening the workout '
      'summary removes it.',
  'Closed':
      'Closing OpenRing from recent apps ends the workout without saving it.',
  'Never': 'What it never does',
  'Scores': 'No scores and no calories.',
  'Sound':
      'No sound. One short vibration when heart rate readings stop for 30 s, '
      'if Alert when the ring drops is on.',
};

const _portuguese = {
  'Title': 'Notificação do treino',
  'Lead': 'Os números são os da tela do treino, calculados do mesmo jeito.',
  'Shows': 'O que mostra',
  'Fields':
      'Tempo e FC. Com GPS, também distância e ritmo atual, ou velocidade no '
      'ciclismo.',
  'Zone':
      'Zona: no título, pela FC máxima em Perfil ou 220 menos a idade. Sem '
      'nenhuma das duas, não há zona.',
  'Paused': 'Pausado: o tempo parado e a distância, com Retomar e Encerrar.',
  'Lock':
      'Tela de bloqueio: tudo, a menos que FC na tela de bloqueio esteja '
      'desligada; aí sem FC e sem zona.',
  'Sources': 'De onde vem cada número',
  'Time': 'Tempo: o celular conta desde o início, sem as pausas.',
  'HeartRate':
      'FC: vem do anel. Se as leituras param por 30 s com o treino rodando e '
      'a conexão continua aberta, aparece -- bpm, o título diz que o anel '
      'está fora de alcance e surge Reconectar.',
  'Gps':
      'Distância e ritmo: o GPS do celular. O ritmo atual usa os últimos 30 s '
      'em movimento. Se o GPS falha, Sinal de GPS perdido fica no lugar.',
  'Updates': 'Quando atualiza',
  'Cadence':
      'O tempo anda a cada segundo, contado pelo próprio Android. FC, '
      'distância e ritmo mudam no máximo a cada 2 s com a tela acesa. Com a '
      'tela apagada, esperam até ela acender; uma pausa, a pergunta de '
      'encerrar ou o anel perdido não esperam.',
  'Buttons': 'Os botões',
  'End':
      'Encerrar pausa e pergunta. Salvar grava o treino; Continuar volta ao '
      'que era. Descartar só dentro do app.',
  'After': 'Depois do treino',
  'Result':
      'Fica só o resultado do salvamento, por até 1 hora. Abrir o resumo do '
      'treino o remove.',
  'Closed': 'Fechar o OpenRing nos apps recentes encerra o treino sem salvar.',
  'Never': 'O que nunca faz',
  'Scores': 'Nenhuma nota e nenhuma caloria.',
  'Sound':
      'Nenhum som. Uma vibração curta quando as leituras de FC param por 30 s, '
      'se Avisar quando o anel cair estiver ligado.',
};

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  Brightness brightness = Brightness.dark,
}) => pumpScaled(
  tester,
  screenHost(const WorkoutNotificationHowScreen()),
  textScaler: textScaler,
  brightness: brightness,
  locale: locale,
  overrides: settingsOverrides(),
);

void main() {
  test('the screen holds 21 strings in each checked language', () {
    expect(_english, hasLength(21));
    expect(_portuguese.keys, _english.keys);
  });

  group('3: the screen says what the notification does', () {
    for (final (locale, strings) in [
      (const Locale('en'), _english),
      (const Locale('pt'), _portuguese),
    ]) {
      final lines = strings.values.toList();

      testWidgets('in $locale it shows every line exactly', (tester) async {
        await _pump(tester, locale: locale);

        for (final line in lines) {
          await reveal(tester, find.text(line));
          expect(find.text(line), findsOneWidget, reason: line);
        }
      });

      testWidgets('in $locale each line sits under its heading', (
        tester,
      ) async {
        await _pump(tester, locale: locale);

        final shown = await shownTexts(tester);

        expect(shown.where(lines.contains).toList(), lines);
      });
    }
  });

  group('5: layout', () {
    for (final c in layoutMatrix()) {
      testWidgets('lays out at $c', (tester) async {
        await _pump(
          tester,
          locale: c.locale,
          textScaler: c.textScaler,
          brightness: c.brightness,
        );

        await scrollThrough(tester);
        expect(find.byType(WorkoutNotificationHowScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
