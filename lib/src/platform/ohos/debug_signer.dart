import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import 'build_profile_signing.dart';
import 'ohos_toolchain.dart';
import 'permission_profile.dart';

const _openHarmonyPassword = '123456';
const _debugSigningPlainPassword = '123456';
const _signAlg = 'SHA256withECDSA';

/// Generated OHOS debug signing material for a package example.
class OhosDebugSigningMaterial {
  /// Creates debug signing material metadata.
  const OhosDebugSigningMaterial({
    required this.directory,
    required this.permissionProfile,
    required this.signingConfig,
  });

  /// Directory containing generated signing files.
  final io.Directory directory;

  /// Permission profile used to generate the signed profile.
  final OhosPermissionProfile permissionProfile;

  /// Build-profile signing config that references generated files.
  final OhosDebugSigningConfig signingConfig;
}

/// Exception thrown when OHOS signing tool execution fails.
class OhosSigningException implements Exception {
  /// Creates an OHOS signing exception.
  const OhosSigningException(this.message);

  /// User-facing failure message.
  final String message;

  @override
  String toString() => message;
}

/// Generates temporary OpenHarmony debug signing material.
Future<OhosDebugSigningMaterial> prepareOhosDebugSigning({
  required FluohEnvironment environment,
  required io.Directory ohosDirectory,
  required TerminalOutput output,
  String usage = '',
}) async {
  final toolchain = await locateOhosToolchain(
    environment: environment.processEnvironment,
    usage: usage,
  );
  final permissionProfile = await readOhosPermissionProfile(
    ohosDirectory: ohosDirectory,
    openHarmonySdk: toolchain.openHarmonySdk,
  );
  final directory = io.Directory(
    '${environment.ohosSigningDirectory.path}/'
    '${_safePathSegment(permissionProfile.bundleName)}',
  );
  await directory.create(recursive: true);

  final rootCa = io.File('${directory.path}/openharmony-root-ca.cer');
  final applicationCa = io.File(
    '${directory.path}/openharmony-application-ca.cer',
  );
  final appKeyStore = io.File('${directory.path}/app-keypair-v3.p12');
  final appCertificateChain = io.File(
    '${directory.path}/app-cert-chain-v3.cer',
  );
  final unsignedProfile = io.File('${directory.path}/debug-profile.json');
  final signedProfile = io.File('${directory.path}/debug-profile.p7b');
  final keyAlias = _keyAliasForBundle(permissionProfile.bundleName);

  await _exportCertificate(
    toolchain: toolchain,
    alias: 'openharmony application root ca',
    outFile: rootCa,
    operation: 'Export OpenHarmony application root CA',
  );
  await _exportCertificate(
    toolchain: toolchain,
    alias: 'openharmony application ca',
    outFile: applicationCa,
    operation: 'Export OpenHarmony application CA',
  );
  await _generateAppKeyPair(
    toolchain: toolchain,
    keyStore: appKeyStore,
    keyAlias: keyAlias,
  );
  await _generateAppCertificate(
    toolchain: toolchain,
    keyStore: appKeyStore,
    keyAlias: keyAlias,
    rootCa: rootCa,
    applicationCa: applicationCa,
    outFile: appCertificateChain,
  );
  await _writeUnsignedProfile(
    profile: permissionProfile,
    appCertificateChain: appCertificateChain,
    outFile: unsignedProfile,
  );
  await _signProfile(
    toolchain: toolchain,
    unsignedProfile: unsignedProfile,
    signedProfile: signedProfile,
  );
  final encryptedPassword = await _generateEncryptedPasswordMaterial(
    toolchain: toolchain,
    signingDirectory: directory,
    plainPassword: _debugSigningPlainPassword,
  );

  output.detail(
    'Prepared OHOS debug profile for ${permissionProfile.bundleName} '
    'with APL ${permissionProfile.apl}',
  );

  return OhosDebugSigningMaterial(
    directory: directory,
    permissionProfile: permissionProfile,
    signingConfig: OhosDebugSigningConfig(
      storeFile: appKeyStore.absolute.path,
      storePassword: encryptedPassword,
      keyAlias: keyAlias,
      keyPassword: encryptedPassword,
      signAlg: _signAlg,
      profile: signedProfile.absolute.path,
      certpath: appCertificateChain.absolute.path,
    ),
  );
}

/// Signs unsigned HAPs produced by the OHOS build.
Future<List<io.File>> signGeneratedUnsignedHaps({
  required FluohEnvironment environment,
  required io.Directory exampleDirectory,
  required OhosDebugSigningMaterial signingMaterial,
  required TerminalOutput output,
  DateTime? modifiedAfter,
  String usage = '',
}) async {
  final ohosDirectory = io.Directory('${exampleDirectory.path}/ohos');
  final unsignedHaps = await _findUnsignedHaps(
    ohosDirectory,
    modifiedAfter: modifiedAfter,
  );
  if (unsignedHaps.isEmpty) {
    return const [];
  }

  final toolchain = await locateOhosToolchain(
    environment: environment.processEnvironment,
    usage: usage,
  );
  final compatibleVersion = await _readCompatibleVersion(ohosDirectory);
  final signedDirectory = io.Directory(
    '${exampleDirectory.path}/build/ohos/hap',
  );
  await signedDirectory.create(recursive: true);
  final signedHaps = <io.File>[];

  for (final unsignedHap in unsignedHaps) {
    final fileName = _fileName(
      unsignedHap.path,
    ).replaceFirst('-unsigned.hap', '-signed.hap');
    final signedHap = io.File('${signedDirectory.path}/$fileName');
    if (await signedHap.exists()) {
      await signedHap.delete();
    }
    await _runHapSignTool(
      toolchain,
      [
        'sign-app',
        '-mode',
        'localSign',
        '-keyAlias',
        signingMaterial.signingConfig.keyAlias,
        '-keyPwd',
        _debugSigningPlainPassword,
        '-appCertFile',
        signingMaterial.signingConfig.certpath,
        '-profileFile',
        signingMaterial.signingConfig.profile,
        '-inFile',
        unsignedHap.path,
        '-signAlg',
        signingMaterial.signingConfig.signAlg,
        '-keystoreFile',
        signingMaterial.signingConfig.storeFile,
        '-keystorePwd',
        _debugSigningPlainPassword,
        '-outFile',
        signedHap.path,
        '-compatibleVersion',
        compatibleVersion,
        '-signCode',
        '1',
      ],
      workingDirectory: signedDirectory,
      operation: 'Sign generated OHOS HAP',
    );
    signedHaps.add(signedHap);
    output.detail('Signed ${_fileName(signedHap.path)}');
  }

  return signedHaps;
}

/// Finds OHOS HAP artifacts that can be installed from an example project.
Future<List<io.File>> findInstallableOhosHaps({
  required io.Directory exampleDirectory,
  DateTime? modifiedAfter,
}) async {
  final signedHaps = <io.File>[];
  final otherHaps = <io.File>[];
  final seen = <String>{};
  final roots = [
    io.Directory('${exampleDirectory.path}/build/ohos/hap'),
    io.Directory('${exampleDirectory.path}/ohos'),
  ];

  for (final root in roots) {
    if (!await root.exists()) {
      continue;
    }
    await for (final entity in root.list(recursive: true)) {
      if (entity is! io.File || !entity.path.endsWith('.hap')) {
        continue;
      }
      if (entity.path.endsWith('-unsigned.hap')) {
        continue;
      }
      final absolutePath = entity.absolute.path;
      if (!seen.add(absolutePath)) {
        continue;
      }
      if (modifiedAfter != null &&
          (await entity.lastModified()).isBefore(modifiedAfter)) {
        continue;
      }
      if (entity.path.endsWith('-signed.hap')) {
        signedHaps.add(entity);
      } else {
        otherHaps.add(entity);
      }
    }
  }

  signedHaps.sort((left, right) => left.path.compareTo(right.path));
  otherHaps.sort((left, right) => left.path.compareTo(right.path));
  return signedHaps.isNotEmpty ? signedHaps : otherHaps;
}

Future<void> _exportCertificate({
  required OhosToolchain toolchain,
  required String alias,
  required io.File outFile,
  required String operation,
}) async {
  if (await outFile.exists()) {
    return;
  }
  await _runChecked(
    toolchain.keytool.path,
    [
      '-exportcert',
      '-rfc',
      '-alias',
      alias,
      '-keystore',
      toolchain.openHarmonyKeyStore.path,
      '-storepass',
      _openHarmonyPassword,
      '-storetype',
      'PKCS12',
      '-file',
      outFile.path,
    ],
    workingDirectory: outFile.parent,
    operation: operation,
  );
}

Future<void> _generateAppKeyPair({
  required OhosToolchain toolchain,
  required io.File keyStore,
  required String keyAlias,
}) async {
  if (await keyStore.exists()) {
    return;
  }
  await _runHapSignTool(
    toolchain,
    [
      'generate-keypair',
      '-keyAlias',
      keyAlias,
      '-keyPwd',
      _debugSigningPlainPassword,
      '-keyAlg',
      'ECC',
      '-keySize',
      'NIST-P-256',
      '-keystoreFile',
      keyStore.path,
      '-keystorePwd',
      _debugSigningPlainPassword,
    ],
    workingDirectory: keyStore.parent,
    operation: 'Generate OHOS debug application key pair',
  );
}

Future<void> _generateAppCertificate({
  required OhosToolchain toolchain,
  required io.File keyStore,
  required String keyAlias,
  required io.File rootCa,
  required io.File applicationCa,
  required io.File outFile,
}) async {
  if (await outFile.exists()) {
    return;
  }
  await _runHapSignTool(
    toolchain,
    [
      'generate-app-cert',
      '-keyAlias',
      keyAlias,
      '-keyPwd',
      _debugSigningPlainPassword,
      '-issuer',
      'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA',
      '-issuerKeyAlias',
      'openharmony application ca',
      '-issuerKeyPwd',
      _openHarmonyPassword,
      '-subject',
      'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=$keyAlias',
      '-validity',
      '3650',
      '-signAlg',
      _signAlg,
      '-keystoreFile',
      keyStore.path,
      '-keystorePwd',
      _debugSigningPlainPassword,
      '-outForm',
      'certChain',
      '-rootCaCertFile',
      rootCa.path,
      '-subCaCertFile',
      applicationCa.path,
      '-outFile',
      outFile.path,
      '-issuerKeystoreFile',
      toolchain.openHarmonyKeyStore.path,
      '-issuerKeystorePwd',
      _openHarmonyPassword,
    ],
    workingDirectory: outFile.parent,
    operation: 'Generate OHOS debug application certificate',
  );
}

Future<void> _writeUnsignedProfile({
  required OhosPermissionProfile profile,
  required io.File appCertificateChain,
  required io.File outFile,
}) async {
  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final profileJson = <String, Object?>{
    'version-name': '2.0.0',
    'version-code': 2,
    'uuid': _uuidV4(),
    'validity': {
      'not-before': nowSeconds - 3600,
      'not-after': nowSeconds + 3650 * 24 * 60 * 60,
    },
    'type': 'debug',
    'bundle-info': {
      'developer-id': 'OpenHarmony',
      'development-certificate': await _firstPemBlock(appCertificateChain),
      'bundle-name': profile.bundleName,
      'apl': profile.apl,
      'app-feature': 'hos_normal_app',
    },
    'acls': {'allowed-acls': <String>[]},
    'permissions': {'restricted-permissions': profile.restrictedPermissions},
    'debug-info': {
      'device-ids': ['*'],
      'device-id-type': 'udid',
    },
    'issuer': 'pki_internal',
  };
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(profileJson),
  );
}

Future<void> _signProfile({
  required OhosToolchain toolchain,
  required io.File unsignedProfile,
  required io.File signedProfile,
}) async {
  await _runHapSignTool(
    toolchain,
    [
      'sign-profile',
      '-mode',
      'localSign',
      '-keyAlias',
      'openharmony application profile debug',
      '-keyPwd',
      _openHarmonyPassword,
      '-profileCertFile',
      toolchain.openHarmonyProfileDebug.path,
      '-inFile',
      unsignedProfile.path,
      '-signAlg',
      _signAlg,
      '-keystoreFile',
      toolchain.openHarmonyKeyStore.path,
      '-keystorePwd',
      _openHarmonyPassword,
      '-outFile',
      signedProfile.path,
    ],
    workingDirectory: signedProfile.parent,
    operation: 'Sign OHOS debug profile',
  );
}

Future<String> _generateEncryptedPasswordMaterial({
  required OhosToolchain toolchain,
  required io.Directory signingDirectory,
  required String plainPassword,
}) async {
  final materialDirectory = io.Directory('${signingDirectory.path}/material');
  if (await materialDirectory.exists()) {
    await materialDirectory.delete(recursive: true);
  }
  final result = await io.Process.run(toolchain.node.path, [
    '-e',
    _passwordMaterialScript,
    signingDirectory.path,
    plainPassword,
  ], workingDirectory: signingDirectory.path);
  if (result.exitCode != 0) {
    throw OhosSigningException(
      'Generate OHOS encrypted signing password failed with exit code '
      '${result.exitCode}.\n'
      '${_trimProcessOutput(result.stdout)}'
      '${_trimProcessOutput(result.stderr)}',
    );
  }
  final encryptedPassword = result.stdout.toString().trim();
  if (!RegExp(r'^[0-9a-fA-F]{32,}$').hasMatch(encryptedPassword) ||
      encryptedPassword.length.isOdd) {
    throw const OhosSigningException(
      'Generated OHOS encrypted signing password has invalid format.',
    );
  }
  await io.File(
    '${signingDirectory.path}/encrypted-password.txt',
  ).writeAsString(encryptedPassword);
  return encryptedPassword;
}

Future<void> _runHapSignTool(
  OhosToolchain toolchain,
  List<String> arguments, {
  required io.Directory workingDirectory,
  required String operation,
}) async {
  await _runChecked(
    toolchain.java.path,
    ['-jar', toolchain.hapSignTool.path, ...arguments],
    workingDirectory: workingDirectory,
    operation: operation,
  );
}

const _passwordMaterialScript = r'''
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = process.argv[1];
const plain = process.argv[2];
const material = path.join(root, 'material');
const component = Buffer.from([
  49, 243, 9, 115, 214, 175, 91, 184,
  211, 190, 177, 88, 101, 131, 192, 119,
]);

function randomName() {
  return crypto.randomUUID().replace(/-/g, '');
}

function writeOne(directory, bytes) {
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, randomName()), bytes);
}

function xor(buffers) {
  const out = Buffer.alloc(16);
  for (const buffer of buffers) {
    if (buffer.length !== 16) {
      throw new Error('material component must be 16 bytes');
    }
    for (let index = 0; index < 16; index += 1) {
      out[index] ^= buffer[index];
    }
  }
  return out;
}

function encrypt(key, bytes) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
  const tag = cipher.getAuthTag();
  const size = Buffer.alloc(4);
  size.writeUInt32BE(encrypted.length + tag.length);
  return Buffer.concat([size, iv, encrypted, tag]);
}

fs.rmSync(material, { recursive: true, force: true });
const fd0 = crypto.randomBytes(16);
const fd1 = crypto.randomBytes(16);
const fd2 = crypto.randomBytes(16);
const salt = crypto.randomBytes(16);
const workKey = crypto.randomBytes(16);
const rootMaterial = xor([fd0, fd1, fd2, component]);
const rootMaterialText = Buffer.from(rootMaterial).toString();
const rootKey = crypto.pbkdf2Sync(
  rootMaterialText,
  salt,
  10000,
  16,
  'sha256',
);

writeOne(path.join(material, 'fd', '0'), fd0);
writeOne(path.join(material, 'fd', '1'), fd1);
writeOne(path.join(material, 'fd', '2'), fd2);
writeOne(path.join(material, 'ac'), salt);
writeOne(path.join(material, 'ce'), encrypt(rootKey, workKey));
process.stdout.write(encrypt(workKey, Buffer.from(plain, 'utf8')).toString('hex'));
''';

/// Exposes the password material generator for regression tests.
String get debugSigningPasswordMaterialScriptForTesting =>
    _passwordMaterialScript;

Future<void> _runChecked(
  String executable,
  List<String> arguments, {
  required io.Directory workingDirectory,
  required String operation,
}) async {
  final result = await io.Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode == 0) {
    return;
  }
  throw OhosSigningException(
    '$operation failed with exit code ${result.exitCode}.\n'
    '${_trimProcessOutput(result.stdout)}'
    '${_trimProcessOutput(result.stderr)}',
  );
}

Future<String> _firstPemBlock(io.File certificateChain) async {
  final content = await certificateChain.readAsString();
  final match = RegExp(
    r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----',
  ).firstMatch(content);
  if (match == null) {
    throw const FormatException('Generated OHOS app certificate is not PEM.');
  }
  return '${match.group(0)!}\n';
}

Future<List<io.File>> _findUnsignedHaps(
  io.Directory ohosDirectory, {
  DateTime? modifiedAfter,
}) async {
  if (!await ohosDirectory.exists()) {
    return const [];
  }
  final haps = <io.File>[];
  await for (final entity in ohosDirectory.list(recursive: true)) {
    if (entity is io.File && entity.path.endsWith('-unsigned.hap')) {
      if (modifiedAfter != null &&
          (await entity.lastModified()).isBefore(modifiedAfter)) {
        continue;
      }
      haps.add(entity);
    }
  }
  haps.sort((left, right) => left.path.compareTo(right.path));
  return haps;
}

Future<String> _readCompatibleVersion(io.Directory ohosDirectory) async {
  final buildProfile = io.File('${ohosDirectory.path}/build-profile.json5');
  if (!await buildProfile.exists()) {
    return '18';
  }
  final content = await buildProfile.readAsString();
  final match = RegExp(
    r'"compatibleSdkVersion"\s*:\s*(?:"[^"(]*\((\d+)\)"|(\d+))',
  ).firstMatch(content);
  return match?.group(1) ?? match?.group(2) ?? '18';
}

String _fileName(String path) {
  return path.replaceAll('\\', '/').split('/').last;
}

String _safePathSegment(String value) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'app' : safe;
}

String _keyAliasForBundle(String bundleName) {
  final safe = _safePathSegment(bundleName).replaceAll('.', '_');
  final truncated = safe.length <= 48 ? safe : safe.substring(0, 48);
  return 'fluoh_${truncated}_debug';
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  final text = bytes.map(hex).join();
  return [
    text.substring(0, 8),
    text.substring(8, 12),
    text.substring(12, 16),
    text.substring(16, 20),
    text.substring(20),
  ].join('-');
}

String _trimProcessOutput(Object? output) {
  final text = output?.toString().trim();
  if (text == null || text.isEmpty) {
    return '';
  }
  const limit = 3000;
  final trimmed = text.length <= limit
      ? text
      : text.substring(text.length - limit);
  return '$trimmed\n';
}
