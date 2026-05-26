class ElevatedLaunchSpec {
  const ElevatedLaunchSpec({
    required this.executable,
    required this.arguments,
    required this.commandPreview,
    this.workingDirectory,
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

    return ElevatedLaunchSpec(
      executable: executable.trim(),
      arguments: arguments
          .map((Object? value) => '$value')
          .toList(growable: false),
      workingDirectory: launch['workingDirectory'] as String?,
      commandPreview:
          (launch['commandPreview'] as String?)?.trim() ?? executable.trim(),
    );
  }

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final String commandPreview;
}
