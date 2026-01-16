class AuthCredentials {
  final String username;
  final String password;

  AuthCredentials({required this.username, required this.password});

  bool get isValid => username.isNotEmpty && password.isNotEmpty;
}
