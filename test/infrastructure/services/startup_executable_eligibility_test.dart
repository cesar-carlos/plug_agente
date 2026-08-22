import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/startup_executable_eligibility.dart';

void main() {
  group('isNonProductionStartupExecutable', () {
    test('should detect Flutter Windows debug, profile, and release build-tree outputs', () {
      expect(
        isNonProductionStartupExecutable(
          r'D:\Developer\plug_agente\build\windows\x64\runner\Debug\plug_agente.exe',
        ),
        isTrue,
      );
      expect(
        isNonProductionStartupExecutable(
          'D:/Developer/plug_agente/build/windows/x64/runner/Profile/plug_agente.exe',
        ),
        isTrue,
      );
      expect(
        isNonProductionStartupExecutable(
          r'D:\Developer\plug_agente\build\windows\x64\runner\Release\plug_agente.exe',
        ),
        isTrue,
      );
    });

    test('should detect dart_tool and Flutter ephemeral layouts only', () {
      expect(
        isNonProductionStartupExecutable(
          r'D:\proj\.dart_tool\flutter_build\abc\plug_agente.exe',
        ),
        isTrue,
      );
      expect(
        isNonProductionStartupExecutable(
          r'D:\proj\windows\flutter\ephemeral\flutter_windows.dll',
        ),
        isTrue,
      );
      expect(
        isNonProductionStartupExecutable(
          r'C:\Users\me\AppData\Local\Temp\ephemeral\plug_agente.exe',
        ),
        isFalse,
      );
      expect(
        isNonProductionStartupExecutable(
          r'D:\Apps\ephemeral\PlugAgente\plug_agente.exe',
        ),
        isFalse,
      );
    });

    test('should allow installed Program Files and LocalAppData Programs paths', () {
      expect(
        isNonProductionStartupExecutable(r'C:\Program Files\Plug Agente\plug_agente.exe'),
        isFalse,
      );
      expect(
        isNonProductionStartupExecutable(
          r'C:\Users\cesar\AppData\Local\Programs\Plug Agente\plug_agente.exe',
        ),
        isFalse,
      );
    });
  });

  group('isStableInstalledStartupExecutable', () {
    test('should accept Program Files and LocalAppData Programs', () {
      expect(
        isStableInstalledStartupExecutable(r'C:\Program Files\Plug Agente\plug_agente.exe'),
        isTrue,
      );
      expect(
        isStableInstalledStartupExecutable(
          r'C:\Program Files (x86)\Plug Agente\plug_agente.exe',
        ),
        isTrue,
      );
      expect(
        isStableInstalledStartupExecutable(
          r'C:\Users\cesar\AppData\Local\Programs\Plug Agente\plug_agente.exe',
        ),
        isTrue,
      );
    });

    test('should reject build-tree and arbitrary folders', () {
      expect(
        isStableInstalledStartupExecutable(
          r'D:\Developer\plug_agente\build\windows\x64\runner\Release\plug_agente.exe',
        ),
        isFalse,
      );
      expect(
        isStableInstalledStartupExecutable(r'D:\Apps\plug_agente.exe'),
        isFalse,
      );
    });
  });

  group('canPersistStartupExecutable', () {
    test('should refuse build-tree paths', () {
      expect(
        canPersistStartupExecutable(
          r'D:\proj\build\windows\x64\runner\Debug\plug_agente.exe',
        ),
        isFalse,
      );
    });

    test('should allow mocked Program Files paths used by unit tests', () {
      expect(
        canPersistStartupExecutable(r'C:\Program Files\PlugAgente\plug_agente.exe'),
        isTrue,
      );
    });

    test('should allow a portable copy when no installed Run key exists', () {
      expect(
        canPersistStartupExecutable(r'D:\Apps\PlugAgente\plug_agente.exe'),
        isTrue,
      );
    });

    test('should refuse overwriting a stable installed Run key from another directory', () {
      expect(
        canPersistStartupExecutable(
          r'D:\Downloads\plug_agente.exe',
          existingHealthyExecutablePath: r'C:\Program Files\Plug Agente\plug_agente.exe',
        ),
        isFalse,
      );
    });

    test('should allow the same directory as an existing production Run key', () {
      expect(
        canPersistStartupExecutable(
          r'D:\Apps\PlugAgente\plug_agente.exe',
          existingHealthyExecutablePath: r'D:\Apps\PlugAgente\plug_agente.exe',
        ),
        isTrue,
      );
    });
  });
}
