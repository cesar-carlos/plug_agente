/// Result of a single icacls invocation for global storage ACL normalization.
enum IcaclsGrantOutcomeKind {
  success,
  nonZeroExit,
  timeout,
  processFailed,
  skippedNonWindows,
}

class IcaclsGrantOutcome {
  const IcaclsGrantOutcome._({
    required this.kind,
    this.exitCode,
    this.stderr,
  });

  const IcaclsGrantOutcome.skippedNonWindows()
    : this._(kind: IcaclsGrantOutcomeKind.skippedNonWindows);

  const IcaclsGrantOutcome.success()
    : this._(kind: IcaclsGrantOutcomeKind.success);

  const IcaclsGrantOutcome.nonZeroExit({
    required int exitCode,
    String? stderr,
  }) : this._(
         kind: IcaclsGrantOutcomeKind.nonZeroExit,
         exitCode: exitCode,
         stderr: stderr,
       );

  const IcaclsGrantOutcome.timeout()
    : this._(kind: IcaclsGrantOutcomeKind.timeout);

  const IcaclsGrantOutcome.processFailed({String? stderr})
    : this._(kind: IcaclsGrantOutcomeKind.processFailed, stderr: stderr);

  final IcaclsGrantOutcomeKind kind;
  final int? exitCode;
  final String? stderr;

  bool get isSuccess =>
      kind == IcaclsGrantOutcomeKind.success || kind == IcaclsGrantOutcomeKind.skippedNonWindows;

  String get diagnosticName => kind.name;

  static IcaclsGrantOutcome worstOf(Iterable<IcaclsGrantOutcome> outcomes) {
    var worst = const IcaclsGrantOutcome.skippedNonWindows();
    for (final outcome in outcomes) {
      if (_severity(outcome.kind) > _severity(worst.kind)) {
        worst = outcome;
      }
    }
    return worst;
  }

  static int _severity(IcaclsGrantOutcomeKind kind) => switch (kind) {
    IcaclsGrantOutcomeKind.skippedNonWindows => 0,
    IcaclsGrantOutcomeKind.success => 0,
    IcaclsGrantOutcomeKind.nonZeroExit => 1,
    IcaclsGrantOutcomeKind.timeout => 2,
    IcaclsGrantOutcomeKind.processFailed => 3,
  };
}
