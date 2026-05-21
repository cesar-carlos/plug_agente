class AgentActionSmtpProfile {
  const AgentActionSmtpProfile({
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.ssl = false,
    this.allowInsecure = false,
    this.ignoreBadCertificate = false,
  });

  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool ssl;
  final bool allowInsecure;
  final bool ignoreBadCertificate;
}
