import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class WebSocketLogDeprecationSummaryCard extends StatelessWidget {
  const WebSocketLogDeprecationSummaryCard({
    required this.l10n,
    required this.count,
    super.key,
  });

  final AppLocalizations l10n;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.wsLogPreserveSqlDeprecatedUses,
            style: context.bodyMuted,
          ),
          Text(
            ': $count',
            style: context.bodyText.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class WebSocketLogAuthorizationSummaryCard extends StatelessWidget {
  const WebSocketLogAuthorizationSummaryCard({
    required this.l10n,
    required this.summary,
    super.key,
  });

  final AppLocalizations l10n;
  final AuthorizationMetricsSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final denialRate = (summary!.denialRate * 100).toStringAsFixed(1);
    final missingPermissionRate = (summary!.reasonRate('missing_permission') * 100).toStringAsFixed(1);
    final tokenNotFoundRate = (summary!.reasonRate('token_not_found') * 100).toStringAsFixed(1);
    final tokenRevokedRate = (summary!.reasonRate('token_revoked') * 100).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogAuthChecks,
            value: summary!.total.toString(),
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogAllowed,
            value: summary!.totalAuthorized.toString(),
            valueColor: colors.success,
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogDenied,
            value: summary!.totalDenied.toString(),
            valueColor: summary!.totalDenied > 0 ? colors.error : null,
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogDenialRate,
            value: '$denialRate%',
            valueColor: summary!.totalDenied > 0 ? colors.error : null,
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogP95Latency,
            value: _formatLatency(summary!.overallP95LatencyMs),
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogP99Latency,
            value: _formatLatency(summary!.overallP99LatencyMs),
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogAuthMissingPermission,
            value: '$missingPermissionRate%',
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogAuthTokenNotFound,
            value: '$tokenNotFoundRate%',
          ),
          WebSocketLogMetricsSummaryChip(
            label: l10n.wsLogAuthTokenRevoked,
            value: '$tokenRevokedRate%',
          ),
        ],
      ),
    );
  }

  String _formatLatency(int latencyMs) {
    if (latencyMs <= 0) {
      return 'n/a';
    }
    return '${latencyMs}ms';
  }
}

class WebSocketLogProtocolMetricsSummaryCard extends StatelessWidget {
  const WebSocketLogProtocolMetricsSummaryCard({
    required this.summary,
    super.key,
  });

  final ProtocolMetricsSummary? summary;

  @override
  Widget build(BuildContext context) {
    final current = summary;
    if (current == null || current.totalMessages == 0) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final saved = _formatBytes(current.totalBytesSaved);
    final efficiency = (current.compressionEfficiency * 100).toStringAsFixed(1);
    final successRate = (current.successRate * 100).toStringAsFixed(1);
    final p95Total = _formatMicros(current.totalDurationPercentiles.p95Us);
    final p95Encode = _formatMicros(current.encodeDurationPercentiles.p95Us);
    final p95Compress = _formatMicros(current.compressDurationPercentiles.p95Us);
    final p95Decode = _formatMicros(current.decodeDurationPercentiles.p95Us);
    final p95Sign = _formatMicros(current.signDurationPercentiles.p95Us);
    final p95Verify = _formatMicros(current.verifyDurationPercentiles.p95Us);
    final p95Canonicalize = _formatMicros(current.canonicalizeDurationPercentiles.p95Us);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          WebSocketLogMetricsSummaryChip(label: 'protocol messages', value: current.totalMessages.toString()),
          WebSocketLogMetricsSummaryChip(label: 'success', value: '$successRate%'),
          WebSocketLogMetricsSummaryChip(
            label: 'errors',
            value: current.errorCount.toString(),
            valueColor: current.errorCount > 0 ? colors.error : null,
          ),
          WebSocketLogMetricsSummaryChip(label: 'saved', value: '$saved ($efficiency%)'),
          WebSocketLogMetricsSummaryChip(label: 'p95 total', value: p95Total),
          WebSocketLogMetricsSummaryChip(label: 'p95 encode', value: p95Encode),
          WebSocketLogMetricsSummaryChip(label: 'p95 gzip', value: p95Compress),
          WebSocketLogMetricsSummaryChip(label: 'p95 decode', value: p95Decode),
          if (current.signDurationPercentiles.p95Us > 0)
            WebSocketLogMetricsSummaryChip(label: 'p95 sign', value: p95Sign),
          if (current.verifyDurationPercentiles.p95Us > 0)
            WebSocketLogMetricsSummaryChip(label: 'p95 verify', value: p95Verify),
          if (current.canonicalizeDurationPercentiles.p95Us > 0)
            WebSocketLogMetricsSummaryChip(label: 'p95 canonicalize', value: p95Canonicalize),
          WebSocketLogMetricsSummaryChip(label: 'isolates', value: current.totalIsolateOperations.toString()),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes.abs() >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes.abs() >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${bytes}B';
  }

  String _formatMicros(int micros) {
    if (micros <= 0) {
      return 'n/a';
    }
    if (micros >= 1000) {
      return '${(micros / 1000).toStringAsFixed(1)}ms';
    }
    return '${micros}us';
  }
}

class WebSocketLogMetricsSummaryChip extends StatelessWidget {
  const WebSocketLogMetricsSummaryChip({
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: context.bodyMuted),
        Text(
          value,
          style: context.bodyText.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
