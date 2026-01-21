# Share App - Project Specifics

**Project Type**: Windows Desktop Application (File Sharing Utility)
**Architecture**: Simple (no Clean Architecture needed)

## Project Dependencies

### Core Dependencies

This project uses specific packages for Windows desktop file sharing:

- **share_plus** - File sharing functionality
- **file_selector** - File selection dialogs
- **image_picker** - Image selection from gallery/camera
- **path_provider** - File system path access
- **window_manager** - Desktop window management
- **process_run** - System process execution

### Dependency Usage Patterns

#### share_plus - File Sharing

```dart
import 'package:share_plus/share_plus.dart';

class ShareFileService {
  static Future<void> shareFiles(List<ShareFile> shareFiles) async {
    try {
      final xFiles = shareFiles
          .map((file) => XFile(file.fullPath, name: file.fileName))
          .toList();

      await Share.shareXFiles(
        xFiles,
        text: 'Share App',
      );
    } catch (e) {
      throw Exception('Error sharing files: $e');
    }
  }
}
```

#### window_manager - Window Management

```dart
import 'package:window_manager/window_manager.dart';

class WindowConfig {
  Future<void> config() async {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(400, 300),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
```

#### file_selector - File Selection

```dart
import 'package:file_selector/file_selector.dart';

Future<XFile?> selectFile() async {
  const XTypeGroup typeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['jpg', 'png', 'gif'],
  );

  final file = await openFile(
    acceptedTypeGroups: <XTypeGroup>[typeGroup],
  );

  return file;
}
```

## Project Architecture

### Simple Structure

This is a simple Windows desktop application. No complex layers or patterns needed.

```
lib/
├── main.dart                      # App entry point with window config
├── model/                         # Data models
│   ├── share_file.dart            # Shared file model
│   └── demo_args.dart             # Demo/test arguments
├── page/                          # UI pages
│   └── home_page.dart             # Main/home page
├── service/                       # Business logic
│   ├── share_file.service.dart    # File sharing operations
│   ├── args_decode.dart           # Command-line argument decoder
│   └── process_info.dart          # System process info
└── window.config/                 # Window management
    ├── window_config.dart         # Window initialization and setup
    └── window_event.dart          # Window event handlers
```

### Entry Point Pattern

```dart
// main.dart
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final String stringArgs = args.join('');

  await WindowConfig().config();
  runApp(MyApp(stringArgs));
}
```

### Model Layer

```dart
class ShareFile {
  final String fullPath;
  final String fileName;

  const ShareFile({
    required this.fullPath,
    required this.fileName,
  });

  ShareFile.fromPath(String path)
      : fullPath = path,
        fileName = path.split(Platform.pathSeparator).last;
}
```

### Page Layer

```dart
class HomePage extends StatefulWidget {
  final String arguments;

  const HomePage({super.key, required this.arguments});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late List<ShareFile> shareFiles;
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    shareFiles = ArgsDecode.exec(widget.arguments);
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(...);
  }
}
```

### Service Layer

```dart
class ShareFileService {
  static Future<void> shareImage(List<ShareFile> shareFiles) async {
    try {
      final xFiles = shareFiles
          .map((e) => XFile(e.fullPath, name: e.fileName))
          .toList();

      await Share.shareXFiles(
        text: 'Share App',
        xFiles,
      );
    } catch (e) {
      throw Exception('Error sharing image: $e');
    }
  }
}
```

## Desktop-Specific Considerations

### Windows Platform

- ✅ Use `exit(0)` to close the app
- ✅ Configure window before `runApp()`
- ✅ Consider keyboard shortcuts and focus behavior
- ✅ Handle window resizing and positioning

### Keyboard Events

```dart
RawKeyboardListener(
  focusNode: focusNode,
  onKey: (event) => exit(0),
  child: Container(...),
)
```

### Auto-Close Behavior

```dart
Future<void> onAutoClose() async {
  await Future.delayed(const Duration(seconds: 30));
  exit(0);
}
```

## Data Flow

```
1. main() receives command-line arguments
   ↓
2. WindowConfig.config() configures the window
   ↓
3. MyApp() runs with arguments
   ↓
4. HomePage() receives arguments via constructor
   ↓
5. initState() parses arguments with ArgsDecode
   ↓
6. User interacts (button press, keyboard)
   ↓
7. ShareFileService.shareImage() shares files
   ↓
8. App can be closed (exit(0) or timeout)
```

## Patterns Used

### Static Service Methods

```dart
class ShareFileService {
  static Future<void> shareImage(List<ShareFile> shareFiles) async { ... }
}
```

### Late Initialization

```dart
class _MyPageState extends State<MyPage> {
  late List<ShareFile> shareFiles;

  @override
  void initState() {
    super.initState();
    shareFiles = ArgsDecode.exec(widget.arguments);
  }
}
```

### Resource Disposal

```dart
@override
void dispose() {
  focusNode.dispose();
  super.dispose();
}
```

## Best Practices for This Project

### ✅ DO

- Use `StatefulWidget` when managing state
- Dispose all resources (FocusNode, controllers, streams)
- Handle errors in service methods
- Use `late` for data initialized in `initState`
- Configure window before `runApp()`
- Use `WidgetsFlutterBinding.ensureInitialized()` in `main()`

### ❌ DON'T

- Don't use complex state management for simple apps
- Don't create unnecessary abstractions
- Don't forget to dispose resources
- Don't configure window after `runApp()`
- Don't mix business logic with UI code

## When This Architecture Is Appropriate

This simple architecture is appropriate when:

- ✅ Small to medium-sized desktop apps
- ✅ Simple business logic
- ✅ Single-purpose applications
- ✅ No complex data flow
- ✅ Small team or solo developer

Consider Clean Architecture when:

- ❌ Large applications with many features
- ❌ Complex business logic
- ❌ Multiple platforms with different behaviors
- ❌ Large team requiring clear boundaries
