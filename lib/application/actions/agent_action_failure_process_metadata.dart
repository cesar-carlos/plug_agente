/// Process snapshot fields carried in failure context maps by subprocess runners.
class AgentActionFailureProcessMetadata {
  const AgentActionFailureProcessMetadata({
    this.processExecutable,
    this.processArgumentCount,
    this.processCommandPreview,
  });

  final String? processExecutable;
  final int? processArgumentCount;
  final String? processCommandPreview;

  bool get isEmpty =>
      (processExecutable == null || processExecutable!.trim().isEmpty) &&
      processArgumentCount == null &&
      (processCommandPreview == null || processCommandPreview!.trim().isEmpty);

  static AgentActionFailureProcessMetadata fromFailureContext(
    Map<String, Object?> context,
  ) {
    final executable = context['executable'];
    final preview = context['command_preview'];
    final argumentCount = context['argument_count'];

    return AgentActionFailureProcessMetadata(
      processExecutable: executable is String && executable.trim().isNotEmpty ? executable.trim() : null,
      processArgumentCount: argumentCount is int
          ? argumentCount
          : argumentCount is num
          ? argumentCount.toInt()
          : null,
      processCommandPreview: preview is String && preview.trim().isNotEmpty ? preview.trim() : null,
    );
  }
}
