enum FluohInstallMethod { dartPubGlobal, homebrew, localSourceCheckout }

class FluohInstallation {
  const FluohInstallation({required this.method, required this.scriptPath});

  final FluohInstallMethod method;
  final String scriptPath;
}

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
