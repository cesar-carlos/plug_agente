/// Informações de versão do Windows.
class WindowsVersionInfo {
  const WindowsVersionInfo({
    required this.majorVersion,
    required this.minorVersion,
    required this.buildNumber,
    required this.isServer,
    this.productName,
  });

  final int majorVersion;
  final int minorVersion;
  final int buildNumber;
  final bool isServer;
  final String? productName;

  /// Windows 10 ou superior (versão 10.0+).
  bool get isWindows10OrLater => majorVersion >= 10;

  /// Windows 8 / Server 2012 (versão 6.2).
  bool get isWindows8OrServer2012 => majorVersion == 6 && minorVersion == 2;

  /// Windows 8.1 / Server 2012 R2 (versão 6.3).
  bool get isWindows81OrServer2012R2 => majorVersion == 6 && minorVersion == 3;

  /// Abaixo de Windows 8 / Server 2012.
  bool get isBelowWindows8 => majorVersion < 6 || (majorVersion == 6 && minorVersion < 2);

  String get versionString => '$majorVersion.$minorVersion.$buildNumber';

  @override
  String toString() {
    return 'WindowsVersionInfo('
        'version: $versionString, '
        'isServer: $isServer'
        '${productName != null ? ', product: $productName' : ''}'
        ')';
  }
}
