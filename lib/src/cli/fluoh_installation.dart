/// Install methods that `fluoh upgrade` can reason about.
enum FluohInstallMethod { dartPubGlobal, homebrew, localSourceCheckout }

/// Detected installation information for the current executable.
class FluohInstallation {
  /// Creates an installation descriptor.
  const FluohInstallation({required this.method, required this.scriptPath});

  /// Detected install method.
  final FluohInstallMethod method;

  /// Script path used for detection.
  final String scriptPath;
}

/// Resolves the current fluoh install method from [scriptUri].
FluohInstallation resolveFluohInstallation(Uri scriptUri) {
  final scriptPath = _scriptPath(scriptUri);
  final normalized = _normalizePath(scriptPath);
  if (_isHomebrewInstall(normalized)) {
    return FluohInstallation(
      method: FluohInstallMethod.homebrew,
      scriptPath: scriptPath,
    );
  }

  if (_isLocalSourceCheckout(normalized)) {
    return FluohInstallation(
      method: FluohInstallMethod.localSourceCheckout,
      scriptPath: scriptPath,
    );
  }

  return FluohInstallation(
    method: FluohInstallMethod.dartPubGlobal,
    scriptPath: scriptPath,
  );
}

String _scriptPath(Uri scriptUri) {
  if (!scriptUri.isScheme('file')) {
    return scriptUri.toString();
  }
  return scriptUri.toFilePath();
}

bool _isHomebrewInstall(String normalizedPath) {
  return normalizedPath.contains('/Cellar/fluoh/') ||
      normalizedPath.contains('/Homebrew/Cellar/fluoh/');
}

bool _isLocalSourceCheckout(String normalizedPath) {
  if (normalizedPath.contains('/.pub-cache/') ||
      _isHomebrewInstall(normalizedPath)) {
    return false;
  }
  return normalizedPath.endsWith('/bin/fluoh.dart');
}

String _normalizePath(String path) => path.replaceAll(r'\', '/');
