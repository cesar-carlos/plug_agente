class AuthCredentials {
  AuthCredentials({required this.username, required this.password});

  /// Factory constructor for testing purposes
  factory AuthCredentials.test() {
    return AuthCredentials(
      username: 'test_user',
      password: 'test_password',
    );
  }

  final String username;
  final String password;

  bool get isValid => username.isNotEmpty && password.isNotEmpty;
}
