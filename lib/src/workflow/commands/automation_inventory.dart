part of 'workflow_commands.dart';

Future<_AutomationInventory> _automationInventory({
  required FluohEnvironment environment,
  required String? packageName,
}) async {
  final manifest = await _readOptionalPackageManifest(environment);
  if (manifest == null) {
    if (packageName != null) {
      return _AutomationInventory(
        status: 'unresolved',
        targetKind: 'package',
        targetName: packageName,
        rootPath: environment.workingDirectory.path,
        tests: const _AutomationTestInventory(
          packageTestRunner: 'flutter',
          publicLibraryFiles: 0,
          packageTestFiles: 0,
          packageIntegrationTestFiles: 0,
          exampleTestFiles: 0,
          exampleIntegrationTestFiles: 0,
        ),
        platforms: const [],
        capabilities: const [],
        manifestPermissions: const [],
        warnings: const [
          'Package inventory could not be resolved because fluoh.yaml is missing.',
        ],
      );
    }
    return _scanAutomationInventory(
      root: environment.workingDirectory,
      targetKind: 'project',
      targetName: await _pubspecPackageName(environment.workingDirectory),
    );
  }

  final PackageManifestPackage package;
  try {
    package = manifest.packageForName(packageName);
  } on Object catch (error) {
    return _AutomationInventory(
      status: 'unresolved',
      targetKind: 'package',
      targetName: packageName,
      rootPath: environment.workingDirectory.path,
      tests: const _AutomationTestInventory(
        packageTestRunner: 'flutter',
        publicLibraryFiles: 0,
        packageTestFiles: 0,
        packageIntegrationTestFiles: 0,
        exampleTestFiles: 0,
        exampleIntegrationTestFiles: 0,
      ),
      platforms: const [],
      capabilities: const [],
      manifestPermissions: const [],
      warnings: ['Package inventory could not be resolved: $error'],
    );
  }
  final root = _directoryInside(environment.workingDirectory, package.path);
  return _scanAutomationInventory(
    root: root,
    targetKind: 'package',
    targetName: package.name,
    packagePath: package.path,
  );
}

Future<_AutomationInventory> _scanAutomationInventory({
  required Directory root,
  required String targetKind,
  required String? targetName,
  String? packagePath,
}) async {
  final example = Directory('${root.path}/example');
  final exampleExists = await example.exists();
  final isFlutterPackage = await isFlutterPackageDirectory(root);
  final packageTestRunner = isFlutterPackage ? 'flutter' : 'dart';
  final publicLibraryFiles = await _dartFiles(Directory('${root.path}/lib'));
  final packageTestFiles = await _dartFiles(Directory('${root.path}/test'));
  final packageIntegrationTestFiles = await _dartFiles(
    Directory('${root.path}/integration_test'),
  );
  final exampleTestFiles = exampleExists
      ? await _dartFiles(Directory('${example.path}/test'))
      : const <File>[];
  final exampleIntegrationTestFiles = exampleExists
      ? await _dartFiles(Directory('${example.path}/integration_test'))
      : const <File>[];
  final missingPackageTests = _missingPackageTestsForLibraryFiles(
    root: root,
    libraryFiles: publicLibraryFiles,
    packageTestFiles: packageTestFiles,
    packageTestRunner: packageTestRunner,
  );
  final weakPackageTests = await _weakPackageTestsForLibraryFiles(
    root: root,
    libraryFiles: publicLibraryFiles,
    packageTestFiles: packageTestFiles,
    packageTestRunner: packageTestRunner,
  );
  final tests = _AutomationTestInventory(
    packageTestRunner: packageTestRunner,
    publicLibraryFiles: publicLibraryFiles.length,
    packageTestFiles: packageTestFiles.length,
    packageIntegrationTestFiles: packageIntegrationTestFiles.length,
    exampleTestFiles: exampleTestFiles.length,
    exampleIntegrationTestFiles: exampleIntegrationTestFiles.length,
    publicLibraryFilePaths: publicLibraryFiles
        .map((file) => file.path)
        .toList(),
    packageTestFilePaths: packageTestFiles.map((file) => file.path).toList(),
    missingPackageTests: missingPackageTests,
    weakPackageTests: weakPackageTests,
  );
  final platforms = [
    for (final platform in const [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      _AutomationPlatformInventory(
        platform: platform,
        packageDirectoryExists: await Directory(
          '${root.path}/$platform',
        ).exists(),
        exampleDirectoryExists: exampleExists
            ? await Directory('${example.path}/$platform').exists()
            : false,
      ),
  ];
  final permissions = await _manifestPermissions(
    root,
    example: exampleExists ? example : null,
  );
  final capabilities = await _automationCapabilities(
    root,
    example: exampleExists ? example : null,
  );
  return _AutomationInventory(
    status: 'ready',
    targetKind: targetKind,
    targetName: targetName,
    rootPath: root.path,
    packagePath: packagePath,
    examplePath: exampleExists ? example.path : null,
    tests: tests,
    platforms: platforms,
    capabilities: capabilities,
    manifestPermissions: permissions,
    warnings: [
      if (capabilities.isEmpty)
        'No public package capabilities were discovered; inspect public API and example entry points before reporting ready.',
      if (tests.totalTestFileCount == 0)
        'No Dart tests were found under test, integration_test, example/test, or example/integration_test.',
      if (tests.baselineStatus == 'needsPackageTests')
        'No package tests were found for public library files.',
      if (tests.baselineStatus == 'needsTestCoverageReview')
        'Package tests appear lower than the public library surface; inspect coverage before reporting ready.',
      if (permissions.isNotEmpty)
        'Manifest runtime permissions were found; ensure grant and denied/error behavior paths are covered.',
    ],
  );
}

Directory _directoryInside(Directory root, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '.') {
    return root;
  }
  return Directory('${root.path}/$trimmed');
}

Future<String?> _pubspecPackageName(Directory directory) async {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    return null;
  }
  try {
    final yaml = parseYamlMap(
      await pubspec.readAsString(),
      label: pubspec.path,
    );
    return optionalString(yaml, 'name');
  } on Object {
    return null;
  }
}
