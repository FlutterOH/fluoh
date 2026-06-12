part of 'workflow_commands.dart';

class _AutomationInventory {
  const _AutomationInventory({
    required this.status,
    required this.targetKind,
    required this.rootPath,
    required this.tests,
    required this.platforms,
    required this.capabilities,
    required this.manifestPermissions,
    this.targetName,
    this.packagePath,
    this.examplePath,
    this.warnings = const [],
  });

  final String status;
  final String targetKind;
  final String? targetName;
  final String rootPath;
  final String? packagePath;
  final String? examplePath;
  final _AutomationTestInventory tests;
  final List<_AutomationPlatformInventory> platforms;
  final List<_AutomationCapability> capabilities;
  final List<_AutomationManifestPermission> manifestPermissions;
  final List<String> warnings;

  int get totalTestFileCount => tests.totalTestFileCount;

  int get manifestPermissionCount => manifestPermissions.length;

  int get capabilityCount => capabilities.length;

  Map<String, Object?> toJson() {
    return {
      'schema': 1,
      'status': status,
      'targetKind': targetKind,
      if (targetName != null) 'targetName': targetName,
      'rootPath': rootPath,
      if (packagePath != null) 'packagePath': packagePath,
      if (examplePath != null) 'examplePath': examplePath,
      'tests': tests.toJson(),
      'platforms': platforms.map((platform) => platform.toJson()).toList(),
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(),
      'manifestPermissions': manifestPermissions
          .map((permission) => permission.toJson())
          .toList(),
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }
}

class _AutomationCapability {
  const _AutomationCapability({
    required this.category,
    required this.item,
    required this.path,
    required this.source,
  });

  final String category;
  final String item;
  final String path;
  final String source;

  String get coverageItem => item;

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      'coverageItem': coverageItem,
      'path': path,
      'source': source,
    };
  }
}

class _AutomationTestInventory {
  const _AutomationTestInventory({
    required this.packageTestRunner,
    required this.publicLibraryFiles,
    required this.packageTestFiles,
    required this.packageIntegrationTestFiles,
    required this.exampleTestFiles,
    required this.exampleIntegrationTestFiles,
    this.publicLibraryFilePaths = const [],
    this.packageTestFilePaths = const [],
    this.missingPackageTests = const [],
    this.weakPackageTests = const [],
  });

  final String packageTestRunner;
  final int publicLibraryFiles;
  final int packageTestFiles;
  final int packageIntegrationTestFiles;
  final int exampleTestFiles;
  final int exampleIntegrationTestFiles;
  final List<String> publicLibraryFilePaths;
  final List<String> packageTestFilePaths;
  final List<_AutomationMissingPackageTest> missingPackageTests;
  final List<_AutomationWeakPackageTest> weakPackageTests;

  int get totalTestFileCount =>
      packageTestFiles +
      packageIntegrationTestFiles +
      exampleTestFiles +
      exampleIntegrationTestFiles;

  int get integrationTestFileCount =>
      packageIntegrationTestFiles + exampleIntegrationTestFiles;

  int get missingPackageTestFileCount {
    if (missingPackageTests.isNotEmpty) {
      return missingPackageTests.length;
    }
    final missing = publicLibraryFiles - packageTestFiles;
    return missing > 0 ? missing : 0;
  }

  int get weakPackageTestFileCount => weakPackageTests.length;

  String get baselineStatus {
    if (totalTestFileCount == 0) {
      return 'needsTests';
    }
    if (publicLibraryFiles > 0 && packageTestFiles == 0) {
      return 'needsPackageTests';
    }
    if (missingPackageTestFileCount > 0) {
      return 'needsTestCoverageReview';
    }
    if (weakPackageTestFileCount > 0) {
      return 'needsTestCoverageReview';
    }
    return 'readyForReview';
  }

  Map<String, Object?> get coverageBaseline {
    return {
      'status': baselineStatus,
      'packageTestRunner': packageTestRunner,
      'focusedPackageTestCommandPattern': '$packageTestRunner test <path>',
      'publicLibraryFiles': publicLibraryFiles,
      'packageTestFiles': packageTestFiles,
      'packageIntegrationTestFiles': packageIntegrationTestFiles,
      'exampleTestFiles': exampleTestFiles,
      'exampleIntegrationTestFiles': exampleIntegrationTestFiles,
      'totalTestFiles': totalTestFileCount,
      'integrationTestFiles': integrationTestFileCount,
      'minimumPackageTestFiles': publicLibraryFiles,
      'missingPackageTestFiles': missingPackageTestFileCount,
      'weakPackageTestFiles': weakPackageTestFileCount,
      if (publicLibraryFilePaths.isNotEmpty)
        'publicLibraryFilePaths': publicLibraryFilePaths,
      if (packageTestFilePaths.isNotEmpty)
        'packageTestFilePaths': packageTestFilePaths,
      if (missingPackageTests.isNotEmpty)
        'missingPackageTests': missingPackageTests
            .map((target) => target.toJson())
            .toList(),
      if (weakPackageTests.isNotEmpty)
        'weakPackageTests': weakPackageTests
            .map((target) => target.toJson())
            .toList(),
      'repair':
          'Add or expand package tests for public library files, then add integration_test or scenario evidence for device-facing behavior.',
    };
  }

  Map<String, Object?> toJson() {
    return {
      'packageTestRunner': packageTestRunner,
      'publicLibraryFiles': publicLibraryFiles,
      'packageTestFiles': packageTestFiles,
      'packageIntegrationTestFiles': packageIntegrationTestFiles,
      'exampleTestFiles': exampleTestFiles,
      'exampleIntegrationTestFiles': exampleIntegrationTestFiles,
      'totalTestFiles': totalTestFileCount,
      'coverageBaseline': coverageBaseline,
    };
  }
}

class _AutomationMissingPackageTest {
  const _AutomationMissingPackageTest({
    required this.libraryPath,
    required this.expectedTestPath,
    required this.acceptedTestPaths,
    required this.testCommand,
    required this.acceptedTestCommands,
  });

  final String libraryPath;
  final String expectedTestPath;
  final List<String> acceptedTestPaths;
  final String testCommand;
  final List<String> acceptedTestCommands;

  Map<String, Object?> toJson() {
    return {
      'libraryPath': libraryPath,
      'expectedTestPath': expectedTestPath,
      'acceptedTestPaths': acceptedTestPaths,
      'testCommand': testCommand,
      'acceptedTestCommands': acceptedTestCommands,
      'repair':
          'Add a focused package test for this library file, or add equivalent integration/scenario evidence and mark the coverage row explicitly.',
    };
  }
}

class _AutomationWeakPackageTest {
  const _AutomationWeakPackageTest({
    required this.libraryPath,
    required this.testPath,
    required this.publicDeclarations,
    required this.exercisedDeclarations,
    required this.missingDeclarations,
    required this.testCommand,
  });

  final String libraryPath;
  final String testPath;
  final List<String> publicDeclarations;
  final List<String> exercisedDeclarations;
  final List<String> missingDeclarations;
  final String testCommand;

  Map<String, Object?> toJson() {
    return {
      'libraryPath': libraryPath,
      'testPath': testPath,
      'publicDeclarationCount': publicDeclarations.length,
      'exercisedDeclarationCount': exercisedDeclarations.length,
      'missingDeclarationCount': missingDeclarations.length,
      'publicDeclarations': publicDeclarations,
      'exercisedDeclarations': exercisedDeclarations,
      'missingDeclarations': missingDeclarations,
      'testCommand': testCommand,
      'repair':
          'Expand this package test so it exercises every public declaration from the library file, or move non-runtime behavior to an explicit scenario/integration coverage row.',
    };
  }
}

class _AutomationPlatformInventory {
  const _AutomationPlatformInventory({
    required this.platform,
    required this.packageDirectoryExists,
    required this.exampleDirectoryExists,
  });

  final String platform;
  final bool packageDirectoryExists;
  final bool exampleDirectoryExists;

  Map<String, Object?> toJson() {
    return {
      'platform': platform,
      'packageDirectoryExists': packageDirectoryExists,
      'exampleDirectoryExists': exampleDirectoryExists,
    };
  }
}

class _AutomationManifestPermission {
  const _AutomationManifestPermission({
    required this.platform,
    required this.name,
    required this.path,
    required this.source,
  });

  final String platform;
  final String name;
  final String path;
  final String source;

  String get coverageItem => _permissionCoverageItem(platform, name);

  Map<String, Object?> toJson() {
    return {
      'platform': platform,
      'name': name,
      'coverageItem': coverageItem,
      'path': path,
      'source': source,
    };
  }
}
