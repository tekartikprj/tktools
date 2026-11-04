/// What a dart project can run or test (`lib/main*.dart`, example, bin,
/// tool, test, integration_test), whether it needs Flutter (its imports
/// followed up to a Flutter SDK library), where (the Dart VM, Chrome, Node,
/// Firefox, `flutter devices`, `flutter emulators`) and the command line.
library;

export 'src/dart_run/dart_import_scanner.dart'
    show
        DartImportScanner,
        dartSourceVmDirectiveUris,
        dartVmLibraries,
        flutterSdkPackageNames;
export 'src/dart_run/dart_run_command.dart'
    show
        DartRunTarget,
        DartRunTargetKind,
        dartRunCommandLine,
        dartRunIsFlutterRun,
        dartTestCommandLine;
export 'src/dart_run/dart_run_device.dart'
    show
        DartRunDevice,
        DartRunEmulator,
        dartRunHostOs,
        getDartRunDevices,
        getDartRunEmulators,
        launchDartRunEmulator,
        parseFlutterDevicesMachine,
        parseFlutterEmulators,
        tkFlutterDeviceIdEnvKey;
export 'src/dart_run/dart_run_entry.dart'
    show
        DartRunEntry,
        DartRunFolder,
        dartSourceDeclaresMain,
        dartRunEntryFromPath,
        dartRunProjectRoot,
        dartSourceWithoutComments,
        findDartRunEntries,
        findDartTestFiles;
export 'src/dart_run/dart_run_scan.dart'
    show DartRunProjectEntry, scanDartRunEntries;
