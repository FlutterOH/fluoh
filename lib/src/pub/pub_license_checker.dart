import 'dart:io';

Future<List<String>> pubLicenseWarnings({
  required Directory repository,
  required String? packagePath,
  required String packageName,
}) async {
  final license = await _findLicense(repository, packagePath);
  if (license == null) {
    return [
      'Warning: Missing LICENSE for $packageName. Preserve or add the upstream '
          'license before publishing the FlutterOH package.',
    ];
  }

  final content = await license.readAsString();
  final permission = _modifiedRedistributionPermission(content);
  return switch (permission) {
    _LicensePermission.allowed => const <String>[],
    _LicensePermission.disallowed => [
      'Warning: ${_displayPath(repository, license)} appears to disallow '
          'modified redistribution. Review the license before publishing the '
          'FlutterOH package.',
    ],
    _LicensePermission.unknown => [
      'Warning: ${_displayPath(repository, license)} could not be confirmed '
          'to allow modified redistribution. Review the license before '
          'publishing the FlutterOH package.',
    ],
  };
}

Future<File?> _findLicense(Directory repository, String? packagePath) async {
  final packageDirectory = _packageDirectory(repository, packagePath);
  final packageLicense = await _findLicenseInDirectory(packageDirectory);
  if (packageLicense != null) {
    return packageLicense;
  }

  if (packageDirectory.path == repository.path) {
    return null;
  }
  return _findLicenseInDirectory(repository);
}

Directory _packageDirectory(Directory repository, String? packagePath) {
  if (packagePath == null || packagePath.isEmpty || packagePath == '.') {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

Future<File?> _findLicenseInDirectory(Directory directory) async {
  for (final name in _licenseFileNames) {
    final file = File('${directory.path}/$name');
    if (await file.exists()) {
      return file;
    }
  }
  return null;
}

const _licenseFileNames = [
  'LICENSE',
  'LICENSE.md',
  'LICENSE.txt',
  'LICENCE',
  'LICENCE.md',
  'LICENCE.txt',
  'COPYING',
  'COPYING.md',
  'COPYING.txt',
];

_LicensePermission _modifiedRedistributionPermission(String content) {
  final normalized = _normalizeLicense(content);
  if (normalized.isEmpty) {
    return _LicensePermission.unknown;
  }

  if (_disallowsModifiedRedistribution(normalized)) {
    return _LicensePermission.disallowed;
  }
  if (_allowsModifiedRedistribution(normalized)) {
    return _LicensePermission.allowed;
  }
  if (normalized.contains('all rights reserved')) {
    return _LicensePermission.disallowed;
  }
  return _LicensePermission.unknown;
}

bool _allowsModifiedRedistribution(String license) {
  if (_containsLicenseId(license, 'mit') ||
      _containsLicenseId(license, 'bsd-2-clause') ||
      _containsLicenseId(license, 'bsd-3-clause') ||
      _containsLicenseId(license, 'apache-2.0') ||
      _containsLicenseId(license, 'mpl-2.0') ||
      _containsLicenseId(license, 'gpl-2.0') ||
      _containsLicenseId(license, 'gpl-3.0') ||
      _containsLicenseId(license, 'lgpl-2.1') ||
      _containsLicenseId(license, 'lgpl-3.0') ||
      _containsLicenseId(license, 'agpl-3.0')) {
    return true;
  }

  return license.contains(
        'redistribution and use in source and binary forms with or without '
        'modification are permitted',
      ) ||
      license.contains('permission is hereby granted') &&
          license.contains('to use copy modify merge publish distribute') ||
      license.contains('to reproduce prepare derivative works') ||
      license.contains('you may copy distribute and modify the software') ||
      license.contains('everyone is permitted to copy and distribute') &&
          license.contains('modify it');
}

bool _disallowsModifiedRedistribution(String license) {
  return license.contains('no derivative works') ||
      license.contains('no derivatives') ||
      license.contains('without derivatives') ||
      license.contains('not permitted to modify') ||
      license.contains('may not modify') ||
      license.contains('must not modify') ||
      license.contains('cannot modify') ||
      license.contains('cc-by-nd') ||
      license.contains('cc by-nd') ||
      license.contains('attribution-noderivatives');
}

bool _containsLicenseId(String license, String id) {
  final escaped = RegExp.escape(id);
  return RegExp('(^|[^a-z0-9.+-])$escaped([^a-z0-9.+-]|\$)').hasMatch(license);
}

String _normalizeLicense(String content) {
  return content.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.+-]+'), ' ').trim();
}

String _displayPath(Directory repository, File file) {
  final prefix = '${repository.path}/';
  if (file.path.startsWith(prefix)) {
    return file.path.substring(prefix.length);
  }
  return file.path;
}

enum _LicensePermission { allowed, disallowed, unknown }
