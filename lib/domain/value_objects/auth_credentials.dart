class AuthCredentials {
  AuthCredentials({
    required this.username,
    required this.password,
    required this.agentId,
  });

  /// Factory constructor for testing purposes
  factory AuthCredentials.test() {
    return AuthCredentials(
      username: 'test_user',
      password: 'test_password',
      agentId: '00000000-0000-0000-0000-000000000000',
    );
  }

  final String username;
  final String password;
  final String agentId;

  bool get isValid =>
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty &&
      agentId.trim().isNotEmpty;
}
