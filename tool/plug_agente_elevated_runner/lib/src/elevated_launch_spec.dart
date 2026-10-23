class ElevatedLaunchSpec {
  const ElevatedLaunchSpec({
    required this.executable,
    required this.arguments,
    required this.commandPreview,
    this.workingDirectory,
    this.cpuLimitPercent = 0,
  });

  factory ElevatedLaunchSpec.fromJson(Map<String, dynamic> launch) {
    final executable = launch['executable'];
    final arguments = launch['arguments'];
    if (executable is! String ||
        executable.trim().isEmpty ||
        arguments is! List) {
      throw const FormatException(
        'Invalid elevated launch executable or arguments.',
      );
    }

    final cpuLimit = launch['cpuLimitPercent'] ?? 0;
    if (cpuLimit is! int || cpuLimit < 0 || cpuLimit > 100) {
      throw const FormatException('Invalid CPU limit; expected 0..100.');
    }
    return ElevatedLaunchSpec(
      cpuLimitPercent: cpuLimit,
      executable: executable.trim(),
      arguments: arguments
          .map((Object? value) => '$value')
          .toList(growable: false),
      workingDirectory: launch['workingDirectory'] as String?,
      commandPreview:
          (launch['commandPreview'] as String?)?.trim() ?? executable.trim(),
    );
  }

  final int cpuLimitPercent;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final String commandPreview;
}
