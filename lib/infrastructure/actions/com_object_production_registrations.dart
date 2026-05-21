import 'package:plug_agente/infrastructure/actions/actions.dart'
    show ComObjectInvocationBootstrap, RegisteredComObjectInvocation;

/// Site-specific COM handlers for production builds.
///
/// Register approved `ProgID` + member pairs here (one handler per pair).
/// Homologation may additionally enable `AGENT_ACTION_COM_STUB_*` via
/// [ComObjectInvocationBootstrap.buildStubRegistrationsFromEnvironment]; do not
/// register the same pair in both places.
List<RegisteredComObjectInvocation> buildComObjectProductionRegistrations() {
  return const <RegisteredComObjectInvocation>[
    // Example (keep commented until a real handler is approved):
    // RegisteredComObjectInvocation(
    //   progId: 'Vendor.Component',
    //   memberName: 'Run',
    //   handler: VendorComponentRunHandler(),
    // ),
  ];
}
