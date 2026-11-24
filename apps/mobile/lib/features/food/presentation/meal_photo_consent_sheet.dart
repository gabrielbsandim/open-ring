import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/vision_probe_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/meal_photo_wire.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_store_providers.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class MealPhotoConsentKeys {
  static const sheet = Key('meal_photo_consent_sheet');
  static const how = Key('meal_photo_consent_how');
  static const unencrypted = Key('meal_photo_consent_unencrypted');
  static const tick = Key('meal_photo_consent_tick');
  static const proceed = Key('meal_photo_consent_continue');
  static const cancel = Key('meal_photo_consent_cancel');
  static const probing = Key('meal_photo_consent_probing');
  static const probeLine = Key('meal_photo_consent_probe_line');
  static const again = Key('meal_photo_consent_again');
  static const photos = Key('meal_photo_consent_photos');
}

/// True once photos may go: consent stored when the sheet asks for it, and
/// the photo model read the probe when it asks for that.
Future<bool> showMealPhotoConsentSheet(
  BuildContext context,
  MealPhotoConsentSheet sheet,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (_) => sheet,
    ) ??
    false;

class MealPhotoConsentSheet extends ConsumerStatefulWidget {
  const new({
    required this.config,
    required this.mealId,
    required this.consent,
    required this.probe,
    super.key,
  });

  final AiConfig config;
  final int mealId;
  final bool consent;
  final bool probe;

  @override
  ConsumerState<MealPhotoConsentSheet> createState() =>
      _MealPhotoConsentSheetState();
}

class _MealPhotoConsentSheetState extends ConsumerState<MealPhotoConsentSheet> {
  late final Future<WirePhoto?> _wire = _encode();
  late bool _probing = !widget.consent;
  var _ticked = false;
  var _busy = false;
  var _ran = false;

  String get _host => widget.config.normalizedUrl?.asciiHost ?? '';

  String get _model => aiPhotoTarget(widget.config);

  @override
  void initState() {
    super.initState();
    if (_probing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_probe()));
    }
  }

  // Encoded off the UI isolate; the consent lines show before it lands.
  Future<WirePhoto?> _encode() async {
    final meal = await ref.read(mealStoreProvider).byId(widget.mealId);
    final name = meal?.photo;
    if (name == null) return null;
    final stored = await ref.read(photoStoreProvider).read(name);
    if (stored == null) return null;
    return await ref.read(wirePhotoEncoderProvider)(stored);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final probe = ref.watch(visionProbeControllerProvider);
    return SafeArea(
      key: MealPhotoConsentKeys.sheet,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _probing ? _probeStep(l10n, probe) : _consentStep(l10n),
        ),
      ),
    );
  }

  List<Widget> _consentStep(AppLocalizations l10n) {
    final colors = AppColors.of(context);
    final cleartext = widget.config.normalizedUrl?.isCleartext ?? false;
    return [
      CaptionText(l10n.foodAiConsentFirst),
      const SizedBox(height: 4),
      _title(l10n.foodAiConsentTitle(_host)),
      const SizedBox(height: 8),
      FutureBuilder<WirePhoto?>(
        future: _wire,
        builder: (context, snap) {
          final wire = snap.data;
          if (wire == null) return const SizedBox.shrink();
          final kb = (wire.bytes.length / 1024).ceil();
          return CaptionText(
            key: MealPhotoConsentKeys.how,
            l10n.foodAiConsentHow(wire.width, wire.height, kb),
          );
        },
      ),
      const SizedBox(height: 6),
      _line(l10n.foodAiConsentWhat),
      _line(l10n.foodAiConsentShows),
      _line(aiConsentWhereLine(l10n, widget.config)),
      _line(l10n.foodAiConsentAfter(_host)),
      _line(l10n.foodAiConsentRough),
      if (cleartext)
        _line(
          l10n.foodAiConsentUnencrypted,
          key: MealPhotoConsentKeys.unencrypted,
          icon: Icon(Icons.lock_open_rounded, color: colors.heart),
        ),
      CheckboxListTile(
        key: MealPhotoConsentKeys.tick,
        value: _ticked,
        onChanged: (v) => setState(() => _ticked = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.foodAiConsentTick(_host)),
      ),
      const SizedBox(height: 8),
      _buttons(
        l10n,
        FilledButton(
          key: MealPhotoConsentKeys.proceed,
          onPressed: _ticked && !_busy ? () => unawaited(_grant()) : null,
          child: Text(l10n.onboardingContinue),
        ),
      ),
      const SizedBox(height: 12),
      CaptionText(l10n.foodAiConsentScope),
    ];
  }

  List<Widget> _probeStep(AppLocalizations l10n, VisionProbeState probe) {
    if (!_ran || probe.running) {
      return [
        Row(
          key: MealPhotoConsentKeys.probing,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: BodyText(l10n.foodAiProbeRunning(_model))),
          ],
        ),
        const SizedBox(height: 12),
        _cancel(l10n),
      ];
    }
    if (probe.result == AiVisionSupport.no) {
      return [
        BodyText(
          key: MealPhotoConsentKeys.probeLine,
          l10n.foodAiProbeTextOnly(_model),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: MealPhotoConsentKeys.photos,
          onPressed: _openPhotos,
          child: Text(l10n.foodAiOpenPhotos),
        ),
      ];
    }
    return [
      BodyText(key: MealPhotoConsentKeys.probeLine, _probeFailure(l10n, probe)),
      const SizedBox(height: 12),
      _buttons(
        l10n,
        FilledButton(
          key: MealPhotoConsentKeys.again,
          onPressed: () => unawaited(_probe()),
          child: Text(l10n.aiTestAgain),
        ),
      ),
    ];
  }

  String _probeFailure(AppLocalizations l10n, VisionProbeState probe) {
    final failure = probe.failure;
    final target = widget.config.copyWith(model: _model);
    final line = failure == null
        ? null
        : aiFailureMessage(l10n, failure, target);
    return line ?? l10n.aiPhotosVisionUnreadable;
  }

  Widget _title(String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _line(String text, {Key? key, Widget? icon}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon ??
            Icon(
              Icons.check_rounded,
              size: 20,
              color: AppColors.of(context).textLabel,
            ),
        const SizedBox(width: 12),
        Expanded(child: BodyText(text)),
      ],
    ),
  );

  Widget _buttons(AppLocalizations l10n, Widget primary) => Row(
    children: [
      Expanded(child: _cancel(l10n)),
      const SizedBox(width: 12),
      Expanded(child: primary),
    ],
  );

  Widget _cancel(AppLocalizations l10n) => OutlinedButton(
    key: MealPhotoConsentKeys.cancel,
    onPressed: () {
      ref.read(visionProbeControllerProvider.notifier).cancel();
      Navigator.of(context).pop(false);
    },
    child: Text(l10n.settingsDeleteCancel),
  );

  void _openPhotos() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop(false);
    unawaited(router?.push(AppPaths.settingsAiPhotos));
  }

  Future<void> _grant() async {
    final host = widget.config.hostKey;
    if (host == null) return;
    setState(() => _busy = true);
    final at = ref.read(clockProvider)();
    final consent = AiMealPhotoConsent(
      consentedAtUtcMs: at.toUtc().millisecondsSinceEpoch,
      policyEffectiveDate: aiCurrentPolicyEffectiveDate,
      hostKey: host,
    );
    try {
      await ref.read(aiConfigProvider.notifier).recordMealPhotoConsent(consent);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (widget.probe) return await _probe();
    Navigator.of(context).pop(true);
  }

  Future<void> _probe() async {
    setState(() {
      _probing = true;
      _ran = false;
    });
    final controller = ref.read(visionProbeControllerProvider.notifier);
    await controller.run();
    if (!mounted) return;
    final seen = ref.read(visionProbeControllerProvider).result;
    if (seen != AiVisionSupport.yes) {
      setState(() => _ran = true);
      return;
    }
    Navigator.of(context).pop(true);
  }
}
