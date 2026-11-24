import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiModelsKeys {
  static const sheet = Key('ai_models_sheet');
  static const search = Key('ai_models_search');
  static const empty = Key('ai_models_empty');
  static const failure = Key('ai_models_failure');

  static Key model(String id) => Key('ai_models_item_$id');
}

/// Case insensitive substring match over the ids, sorted by id.
List<String> aiFilterModels(Iterable<String> ids, String query) {
  final needle = query.trim().toLowerCase();
  return ids.where((id) => id.toLowerCase().contains(needle)).toSet().toList()
    ..sort();
}

/// Pops the chosen model id, or null so the typed name stays as it is.
class AiModelsSheet extends ConsumerStatefulWidget {
  const new({required this.config, super.key});

  final AiConfig config;

  @override
  ConsumerState<AiModelsSheet> createState() => _AiModelsSheetState();
}

class _AiModelsSheetState extends ConsumerState<AiModelsSheet> {
  final _search = TextEditingController();
  List<String>? _models;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final model = await ref.read(analysisModelFactoryProvider)(widget.config);
      final ids = await model.listModels();
      if (mounted) setState(() => _models = ids);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final host = widget.config.normalizedUrl?.asciiHost ?? '';
    return SafeArea(
      key: AiModelsKeys.sheet,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.aiModelsTitle(host),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            CaptionText(l10n.aiModelsLead),
            const SizedBox(height: 12),
            TextField(
              key: AiModelsKeys.search,
              controller: _search,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: l10n.aiModelsSearch,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(child: _list(l10n, host)),
          ],
        ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n, String host) {
    final error = _error;
    if (error != null) {
      final message = error is AnalysisFailure
          ? aiTestFailureMessage(
              l10n,
              error,
              host: host,
              model: widget.config.trimmedModel,
              local: widget.config.preset.isLocal,
            )
          : null;
      return BodyText(
        key: AiModelsKeys.failure,
        message ?? l10n.metricLoadError,
      );
    }
    final models = _models;
    if (models == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final shown = aiFilterModels(models, _search.text);
    if (shown.isEmpty) {
      return BodyText(key: AiModelsKeys.empty, l10n.aiModelsEmpty);
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final id = shown[index];
        return ListTile(
          key: AiModelsKeys.model(id),
          contentPadding: EdgeInsets.zero,
          title: Text(id),
          selected: id == widget.config.trimmedModel,
          onTap: () => Navigator.of(context).pop(id),
        );
      },
    );
  }
}
