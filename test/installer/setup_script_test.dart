import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('installer setup script', () {
    test('keeps admin as default and allows command-line privilege override', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains('PrivilegesRequired=admin'));
      expect(setupScript, contains('PrivilegesRequiredOverridesAllowed=commandline'));
    });

    test('declares and installs native update helper', () {
      final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
      final helperCmake = File('windows/update_helper/CMakeLists.txt').readAsStringSync();
      final installPrefixIndex = windowsCmake.indexOf(r'set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}"');
      final helperSubdirectoryIndex = windowsCmake.indexOf('add_subdirectory("update_helper")');

      expect(windowsCmake, contains('add_subdirectory("update_helper")'));
      expect(installPrefixIndex, isNonNegative);
      expect(helperSubdirectoryIndex, greaterThan(installPrefixIndex));
      expect(helperCmake, contains('add_executable(plug_update_helper'));
      expect(helperCmake, contains('install(TARGETS plug_update_helper'));
    });

    test('installer build preflight requires update helper in bundle', () {
      final buildScript = File('installer/build_installer.py').readAsStringSync();

      expect(buildScript, contains('plug_update_helper.exe'));
      expect(buildScript, contains('helper de update'));
    });

    test('installer build preflight requires elevated action runner in bundle', () {
      final buildScript = File('installer/build_installer.py').readAsStringSync();

      expect(buildScript, contains('plug_agente_elevated_runner.exe'));
      expect(buildScript, contains('build_elevated_runner.py'));
    });

    test('elevated runner build uses dart build cli for sqlite3 native hooks', () {
      final buildScript = File('tool/elevated/build_elevated_runner.py').readAsStringSync();

      expect(buildScript, contains('resolve_dart_sdk_executable'));
      expect(buildScript, contains('"build"'));
      expect(buildScript, contains('"cli"'));
    });

    test('installer build injects auto update channel and signature defines', () {
      final buildScript = File('installer/build_installer.py').readAsStringSync();

      expect(buildScript, contains('AUTO_UPDATE_FEED_URL'));
      expect(buildScript, contains('AUTO_UPDATE_CHANNEL'));
      expect(buildScript, contains('AUTO_UPDATE_REQUIRE_VALID_SIGNATURE'));
      expect(buildScript, contains('--dart-define='));
    });

    test('uses canonical autostart argument without embedding separators in the constant', () {
      final canonical = File('constants/autostart_arg.txt').readAsStringSync().trim();
      final constantsScript = File('installer/constants.iss').readAsStringSync();
      final setupScript = File('installer/setup.iss').readAsStringSync();
      final defineMatch = RegExp(r'#define\s+AutostartArg\s+"([^"]+)"').firstMatch(constantsScript);

      expect(defineMatch, isNotNull);
      expect(defineMatch!.group(1), canonical);
      expect(defineMatch.group(1), isNot(startsWith(' ')));
      expect(defineMatch.group(1), isNot(endsWith(' ')));
      expect(
        setupScript,
        contains(
          r"AddQuotes(ExpandConstant('{app}\{#MyAppExeName}')) + ' ' + AddQuotes('{#AutostartArg}')",
        ),
      );
    });

    test('silent-update contract keeps MERGETASKS startup skip and launches via LAUNCHAFTERUPDATE', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();
      final helperSource = File('windows/update_helper/main.cpp').readAsStringSync();

      expect(setupScript, contains('ShouldLaunchAfterSilentUpdate'));
      expect(setupScript, contains("ExpandConstant('{param:LAUNCHAFTERUPDATE|0}') = '1'"));
      expect(setupScript, contains('/MERGETASKS="!desktopicon,!startup"'));
      expect(helperSource, contains(r'/MERGETASKS=\"!desktopicon,!startup\"'));
      expect(helperSource, contains('/LAUNCHAFTERUPDATE=1'));
      expect(helperSource, contains('/FORCECLOSEAPPLICATIONS'));
      expect(helperSource, isNot(contains('/RESTARTAPPLICATIONS')));
    });

    test('prevents concurrent setup and force-closes the running app during file replace', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains('SetupMutex=PlugAgenteSetup'));
      expect(setupScript, contains('CloseApplications=force'));
      expect(setupScript, contains('CloseApplicationsFilter=plug_agente.exe'));
    });

    test('localizes startup task copy and removes staged update artifacts on uninstall', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains('{cm:StartWithWindows}'));
      expect(setupScript, contains('{cm:StartupOptionsGroup}'));
      expect(setupScript, contains('english.StartWithWindows=Start with Windows'));
      expect(setupScript, contains(r'{commonappdata}\PlugAgente\updates'));
      expect(setupScript, contains('{#AutostartRequestMarker}'));
    });

    test('uses Unicode Portuguese in custom messages instead of preprocessor escapes', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();
      final customMessages = setupScript.split('[CustomMessages]').last.split('[Tasks]').first;

      expect(customMessages, contains('Opções de Inicialização'));
      expect(customMessages, contains('Não foi possível baixar'));
      expect(customMessages, isNot(contains(r'#$00')));
      expect(setupScript, contains('function PrepareToInstall'));
      expect(setupScript, contains("CustomMessage('VCRedistDownloadFailed')"));
      expect(setupScript, contains('#define VCRedistUrl "https://aka.ms/vs/17/release/vc_redist.x64.exe"'));
    });

    test('localizes the Start Menu uninstall shortcut', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains(r'{group}\{cm:UninstallProgram,{#MyAppName}}'));
      expect(setupScript, isNot(contains(r'{group}\Desinstalar')));
    });

    test('writes autostart for the logged-on user instead of elevated HKCU', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains('runasoriginaluser'));
      expect(setupScript, contains("WizardIsTaskSelected('startup')"));
      expect(setupScript, contains('WriteAutostartRequestMarker'));
      expect(setupScript, isNot(contains('WriteLoggedOnUserAutostartRunKey')));
      expect(setupScript, contains('[UninstallRun]'));
      expect(setupScript, contains(r'reg delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"'));
      expect(
        setupScript,
        isNot(
          contains(
            'Root: HKCU; Subkey: "Software\\Microsoft\\Windows\\CurrentVersion\\Run"',
          ),
        ),
      );
    });

    test('registers the plugdb URL protocol for uninstallable HKLM classes', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();

      expect(setupScript, contains('Software\\Classes\\plugdb'));
      expect(setupScript, contains('URL Protocol'));
      expect(setupScript, contains(r'""{app}\{#MyAppExeName}"" ""%1""'));
      expect(setupScript, contains('Flags: uninsdeletekey'));
    });

    test('uses Portuguese fallback, branded wizard, and lzma2 compression', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();
      final languages = setupScript.split('[Languages]').last.split('[CustomMessages]').first;

      expect(languages.indexOf('brazilianportuguese'), lessThan(languages.indexOf('Name: "english"')));
      expect(setupScript, contains('#define MyAppPublisher "Se7e Sistemas"'));
      expect(setupScript, contains('DisableWelcomePage=yes'));
      expect(setupScript, contains(r'VersionInfoVersion={#MyAppVersion}.0'));
      expect(setupScript, contains('Compression=lzma2/ultra64'));
      expect(setupScript, contains(r'WizardImageFile=wizard\wizard-image.png'));
      expect(setupScript, contains(r'WizardSmallImageFile=wizard\wizard-small-image.png'));
      expect(File('installer/wizard/wizard-image.png').existsSync(), isTrue);
      expect(File('installer/wizard/wizard-small-image.png').existsSync(), isTrue);
    });

    test('skips release payload when compiling script-only and signs via ISCC when configured', () {
      final setupScript = File('installer/setup.iss').readAsStringSync();
      final buildScript = File('installer/build_installer.py').readAsStringSync();

      expect(setupScript, contains('#ifndef COMPILE_SCRIPT_ONLY'));
      expect(setupScript, contains('#ifdef SIGN_INSTALLER'));
      expect(setupScript, contains('SignedUninstaller=yes'));
      expect(buildScript, contains('/DSIGN_INSTALLER'));
      expect(buildScript, contains('/Smysigntool='));
      expect(buildScript, contains('build_iscc_command'));
    });
  });
}
