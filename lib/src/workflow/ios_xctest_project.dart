import 'dart:convert';
import 'dart:io';

/// Name of the generated iOS XCTest helper project.
const iosXCTestProjectName = 'FluohIosAutomation';

/// Shared scheme name for the generated iOS XCTest helper project.
const iosXCTestSchemeName = 'FluohIosAutomation';

/// Generated iOS XCTest helper project paths.
class IosXCTestProject {
  /// Creates generated project path metadata.
  const IosXCTestProject({
    required this.root,
    required this.projectFile,
    required this.derivedData,
  });

  /// Root directory containing the generated helper project.
  final Directory root;

  /// Generated `.xcodeproj` directory.
  final Directory projectFile;

  /// Derived data directory used by `xcodebuild`.
  final Directory derivedData;
}

/// Writes an ephemeral XCTest project that can tap a visible iOS permission
/// prompt through Apple's XCTest/XCUITest stack.
Future<IosXCTestProject> writeIosXCTestPermissionProject({
  required Directory cacheRoot,
  required String bundleId,
  required List<String> labels,
  required String match,
  required int timeoutSeconds,
  required bool allow,
}) async {
  return _writeIosXCTestProject(
    cacheRoot: cacheRoot,
    testSource: _permissionSwift(
      bundleId: bundleId,
      labels: labels,
      match: match,
      timeoutSeconds: timeoutSeconds,
      allow: allow,
    ),
  );
}

/// Writes an ephemeral XCTest project that can wait for, assert, or tap a
/// visible app UI element by label through Apple's XCTest/XCUITest stack.
Future<IosXCTestProject> writeIosXCTestTextActionProject({
  required Directory cacheRoot,
  required String bundleId,
  required List<String> labels,
  required String match,
  required int timeoutSeconds,
  required String action,
}) async {
  return _writeIosXCTestProject(
    cacheRoot: cacheRoot,
    testSource: _textActionSwift(
      bundleId: bundleId,
      labels: labels,
      match: match,
      timeoutSeconds: timeoutSeconds,
      action: action,
    ),
  );
}

/// Writes an ephemeral XCTest project that can run coordinate tap or swipe
/// gestures inside the target app through Apple's XCTest/XCUITest stack.
Future<IosXCTestProject> writeIosXCTestCoordinateActionProject({
  required Directory cacheRoot,
  required String bundleId,
  required int x,
  required int y,
  required int endX,
  required int endY,
  required int? durationMilliseconds,
  required String action,
}) async {
  return _writeIosXCTestProject(
    cacheRoot: cacheRoot,
    testSource: _coordinateActionSwift(
      bundleId: bundleId,
      x: x,
      y: y,
      endX: endX,
      endY: endY,
      durationMilliseconds: durationMilliseconds,
      action: action,
    ),
  );
}

Future<IosXCTestProject> _writeIosXCTestProject({
  required Directory cacheRoot,
  required String testSource,
}) async {
  final root = Directory('${cacheRoot.path}/ios-xctest');
  final projectFile = Directory('${root.path}/$iosXCTestProjectName.xcodeproj');
  final appDirectory = Directory('${root.path}/$iosXCTestProjectName');
  final testDirectory = Directory(
    '${root.path}/${iosXCTestProjectName}UITests',
  );
  final schemeDirectory = Directory(
    '${projectFile.path}/xcshareddata/xcschemes',
  );
  final derivedData = Directory('${root.path}/DerivedData');
  await appDirectory.create(recursive: true);
  await testDirectory.create(recursive: true);
  await schemeDirectory.create(recursive: true);
  await derivedData.create(recursive: true);

  await File('${projectFile.path}/project.pbxproj').writeAsString(_pbxproj());
  await File(
    '${schemeDirectory.path}/$iosXCTestSchemeName.xcscheme',
  ).writeAsString(_scheme());
  await File(
    '${appDirectory.path}/AppDelegate.swift',
  ).writeAsString(_appDelegateSwift());
  await File('${appDirectory.path}/Info.plist').writeAsString(_appInfoPlist());
  await File(
    '${testDirectory.path}/Info.plist',
  ).writeAsString(_bundleInfoPlist());
  await File(
    '${testDirectory.path}/PermissionPromptUITests.swift',
  ).writeAsString(testSource);

  return IosXCTestProject(
    root: root,
    projectFile: projectFile,
    derivedData: derivedData,
  );
}

String _permissionSwift({
  required String bundleId,
  required List<String> labels,
  required String match,
  required int timeoutSeconds,
  required bool allow,
}) {
  final bundleIdLiteral = _swiftStringLiteral(bundleId);
  final labelsLiteral = _swiftStringLiteral(jsonEncode(labels));
  final matchLiteral = _swiftStringLiteral(match);
  final actionLiteral = _swiftStringLiteral(allow ? 'allow' : 'deny');
  return '''
import Foundation
import XCTest

final class PermissionPromptUITests: XCTestCase {
  private let targetBundleId = $bundleIdLiteral
  private let labelsJson = $labelsLiteral
  private let matchMode = $matchLiteral
  private let permissionAction = $actionLiteral
  private let timeoutSeconds: TimeInterval = $timeoutSeconds

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testTapPermissionPrompt() throws {
    let labelsData = Data(labelsJson.utf8)
    let labels = (try? JSONDecoder().decode([String].self, from: labelsData)) ?? []
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let target = XCUIApplication(bundleIdentifier: targetBundleId)

    addUIInterruptionMonitor(withDescription: "System Permission Prompt") { alert in
      if self.tapFirstMatchingButton(in: alert, labels: labels, matchMode: self.matchMode) {
        return true
      }
      return false
    }

    target.activate()
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    var lastSnapshot = ""
    while Date() < deadline {
      if tapFirstMatchingButton(in: springboard, labels: labels, matchMode: matchMode) {
        return
      }
      if tapFirstMatchingButton(in: target, labels: labels, matchMode: matchMode) {
        return
      }
      target.tap()
      lastSnapshot = springboard.debugDescription
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    XCTFail("No iOS permission prompt button matched action \\(permissionAction) labels \\(labels). SpringBoard snapshot: \\(lastSnapshot)")
  }

  private func tapFirstMatchingButton(
    in root: XCUIElement,
    labels: [String],
    matchMode: String
  ) -> Bool {
    for label in labels {
      let alertButton = root.alerts.buttons[label]
      if alertButton.exists {
        alertButton.tap()
        return true
      }
      let button = root.buttons[label]
      if button.exists {
        button.tap()
        return true
      }
    }

    guard matchMode != "exact" else {
      return false
    }

    for label in labels {
      let predicate: NSPredicate
      if matchMode == "regex" {
        predicate = NSPredicate(
          format: "label MATCHES %@ OR identifier MATCHES %@ OR value MATCHES %@",
          label,
          label,
          label
        )
      } else {
        predicate = NSPredicate(
          format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@ OR value CONTAINS[c] %@",
          label,
          label,
          label
        )
      }
      let alertButton = root.alerts.buttons.matching(predicate).firstMatch
      if alertButton.exists {
        alertButton.tap()
        return true
      }
      let button = root.buttons.matching(predicate).firstMatch
      if button.exists {
        button.tap()
        return true
      }
      let anyElement = root.descendants(matching: .any).matching(predicate).firstMatch
      if anyElement.exists {
        anyElement.tap()
        return true
      }
    }
    return false
  }
}
''';
}

String _textActionSwift({
  required String bundleId,
  required List<String> labels,
  required String match,
  required int timeoutSeconds,
  required String action,
}) {
  final bundleIdLiteral = _swiftStringLiteral(bundleId);
  final labelsLiteral = _swiftStringLiteral(jsonEncode(labels));
  final matchLiteral = _swiftStringLiteral(match);
  final actionLiteral = _swiftStringLiteral(action);
  return '''
import Foundation
import XCTest

final class TextActionUITests: XCTestCase {
  private let targetBundleId = $bundleIdLiteral
  private let labelsJson = $labelsLiteral
  private let matchMode = $matchLiteral
  private let textAction = $actionLiteral
  private let timeoutSeconds: TimeInterval = $timeoutSeconds

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testRunTextAction() throws {
    let labelsData = Data(labelsJson.utf8)
    let labels = (try? JSONDecoder().decode([String].self, from: labelsData)) ?? []
    let target = XCUIApplication(bundleIdentifier: targetBundleId)

    target.activate()
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    var lastSnapshot = ""
    while Date() < deadline {
      if let element = firstMatchingElement(in: target, labels: labels, matchMode: matchMode) {
        if textAction == "tapText" {
          element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return
      }
      lastSnapshot = target.debugDescription
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    XCTFail("No iOS UI element matched action \\(textAction) labels \\(labels). Target snapshot: \\(lastSnapshot)")
  }

  private func firstMatchingElement(
    in root: XCUIElement,
    labels: [String],
    matchMode: String
  ) -> XCUIElement? {
    let query = root.descendants(matching: .any)

    for label in labels {
      let exact = query.matching(
        NSPredicate(
          format: "label == %@ OR identifier == %@ OR value == %@",
          label,
          label,
          label
        )
      ).firstMatch
      if exact.exists {
        return exact
      }
    }

    guard matchMode != "exact" else {
      return nil
    }

    for label in labels {
      let predicate: NSPredicate
      if matchMode == "regex" {
        predicate = NSPredicate(
          format: "label MATCHES %@ OR identifier MATCHES %@ OR value MATCHES %@",
          label,
          label,
          label
        )
      } else {
        predicate = NSPredicate(
          format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@ OR value CONTAINS[c] %@",
          label,
          label,
          label
        )
      }
      let element = query.matching(predicate).firstMatch
      if element.exists {
        return element
      }
    }
    return nil
  }
}
''';
}

String _coordinateActionSwift({
  required String bundleId,
  required int x,
  required int y,
  required int endX,
  required int endY,
  required int? durationMilliseconds,
  required String action,
}) {
  final bundleIdLiteral = _swiftStringLiteral(bundleId);
  final actionLiteral = _swiftStringLiteral(action);
  final durationSeconds = ((durationMilliseconds ?? 300) / 1000).toString();
  return '''
import Foundation
import XCTest

final class CoordinateActionUITests: XCTestCase {
  private let targetBundleId = $bundleIdLiteral
  private let gestureAction = $actionLiteral

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testRunCoordinateAction() throws {
    let target = XCUIApplication(bundleIdentifier: targetBundleId)
    target.activate()

    let base = target.windows.firstMatch.exists ? target.windows.firstMatch : target
    let origin = base.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
    let start = origin.withOffset(CGVector(dx: $x, dy: $y))

    if gestureAction == "tap" {
      start.tap()
      return
    }

    let end = origin.withOffset(CGVector(dx: $endX, dy: $endY))
    start.press(forDuration: $durationSeconds, thenDragTo: end)
  }
}
''';
}

String _swiftStringLiteral(String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x08:
        buffer.write(r'\b');
      case 0x09:
        buffer.write(r'\t');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0C:
        buffer.write(r'\f');
      case 0x0D:
        buffer.write(r'\r');
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      default:
        if (rune >= 0x20 && rune <= 0x7E) {
          buffer.writeCharCode(rune);
        } else {
          buffer
            ..write(r'\u{')
            ..write(rune.toRadixString(16))
            ..write('}');
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

String _appDelegateSwift() {
  return '''
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let viewController = UIViewController()
    viewController.view.backgroundColor = .systemBackground
    window.rootViewController = viewController
    window.makeKeyAndVisible()
    self.window = window
    return true
  }
}
''';
}

String _appInfoPlist() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>\$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>\$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
</dict>
</plist>
''';
}

String _bundleInfoPlist() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>\$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>\$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
''';
}

String _scheme() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="111111111111111111111111" BuildableName="$iosXCTestProjectName.app" BlueprintName="$iosXCTestProjectName" ReferencedContainer="container:$iosXCTestProjectName.xcodeproj">
        </BuildableReference>
      </BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="222222222222222222222222" BuildableName="${iosXCTestProjectName}UITests.xctest" BlueprintName="${iosXCTestProjectName}UITests" ReferencedContainer="container:$iosXCTestProjectName.xcodeproj">
        </BuildableReference>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>
      <TestableReference skipped="NO">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="222222222222222222222222" BuildableName="${iosXCTestProjectName}UITests.xctest" BlueprintName="${iosXCTestProjectName}UITests" ReferencedContainer="container:$iosXCTestProjectName.xcodeproj">
        </BuildableReference>
      </TestableReference>
    </Testables>
    <MacroExpansion>
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="111111111111111111111111" BuildableName="$iosXCTestProjectName.app" BlueprintName="$iosXCTestProjectName" ReferencedContainer="container:$iosXCTestProjectName.xcodeproj">
      </BuildableReference>
    </MacroExpansion>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="111111111111111111111111" BuildableName="$iosXCTestProjectName.app" BlueprintName="$iosXCTestProjectName" ReferencedContainer="container:$iosXCTestProjectName.xcodeproj">
      </BuildableReference>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="111111111111111111111111" BuildableName="$iosXCTestProjectName.app" BlueprintName="$iosXCTestProjectName" ReferencedContainer="container:$iosXCTestProjectName.xcodeproj">
      </BuildableReference>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug">
  </AnalyzeAction>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
  </ArchiveAction>
</Scheme>
''';
}

String _pbxproj() {
  return '''
// !\$*UTF8*\$!
{
  archiveVersion = 1;
  classes = {
  };
  objectVersion = 56;
  objects = {
    AAAAAAAAAAAAAAAAAAAAAA01 = {isa = PBXBuildFile; fileRef = AAAAAAAAAAAAAAAAAAAAAA11; };
    AAAAAAAAAAAAAAAAAAAAAA02 = {isa = PBXBuildFile; fileRef = AAAAAAAAAAAAAAAAAAAAAA12; };
    AAAAAAAAAAAAAAAAAAAAAA03 = {isa = PBXContainerItemProxy; containerPortal = 333333333333333333333333; proxyType = 1; remoteGlobalIDString = 111111111111111111111111; remoteInfo = $iosXCTestProjectName; };
    AAAAAAAAAAAAAAAAAAAAAA04 = {isa = PBXTargetDependency; target = 111111111111111111111111; targetProxy = AAAAAAAAAAAAAAAAAAAAAA03; };
    AAAAAAAAAAAAAAAAAAAAAA11 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA12 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PermissionPromptUITests.swift; sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA13 = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA14 = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA15 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = $iosXCTestProjectName.app; sourceTree = BUILT_PRODUCTS_DIR; };
    AAAAAAAAAAAAAAAAAAAAAA16 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ${iosXCTestProjectName}UITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
    AAAAAAAAAAAAAAAAAAAAAA21 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    AAAAAAAAAAAAAAAAAAAAAA22 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    444444444444444444444444 = {isa = PBXGroup; children = (AAAAAAAAAAAAAAAAAAAAAA31, AAAAAAAAAAAAAAAAAAAAAA32, AAAAAAAAAAAAAAAAAAAAAA33,); sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA31 = {isa = PBXGroup; children = (AAAAAAAAAAAAAAAAAAAAAA11, AAAAAAAAAAAAAAAAAAAAAA13,); path = $iosXCTestProjectName; sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA32 = {isa = PBXGroup; children = (AAAAAAAAAAAAAAAAAAAAAA12, AAAAAAAAAAAAAAAAAAAAAA14,); path = ${iosXCTestProjectName}UITests; sourceTree = "<group>"; };
    AAAAAAAAAAAAAAAAAAAAAA33 = {isa = PBXGroup; children = (AAAAAAAAAAAAAAAAAAAAAA15, AAAAAAAAAAAAAAAAAAAAAA16,); name = Products; sourceTree = "<group>"; };
    111111111111111111111111 = {isa = PBXNativeTarget; buildConfigurationList = AAAAAAAAAAAAAAAAAAAAAA41; buildPhases = (AAAAAAAAAAAAAAAAAAAAAA51, AAAAAAAAAAAAAAAAAAAAAA21, AAAAAAAAAAAAAAAAAAAAAA52,); buildRules = (); dependencies = (); name = $iosXCTestProjectName; productName = $iosXCTestProjectName; productReference = AAAAAAAAAAAAAAAAAAAAAA15; productType = "com.apple.product-type.application"; };
    222222222222222222222222 = {isa = PBXNativeTarget; buildConfigurationList = AAAAAAAAAAAAAAAAAAAAAA42; buildPhases = (AAAAAAAAAAAAAAAAAAAAAA53, AAAAAAAAAAAAAAAAAAAAAA22, AAAAAAAAAAAAAAAAAAAAAA54,); buildRules = (); dependencies = (AAAAAAAAAAAAAAAAAAAAAA04,); name = ${iosXCTestProjectName}UITests; productName = ${iosXCTestProjectName}UITests; productReference = AAAAAAAAAAAAAAAAAAAAAA16; productType = "com.apple.product-type.bundle.ui-testing"; };
    333333333333333333333333 = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {111111111111111111111111 = {CreatedOnToolsVersion = 16.0; }; 222222222222222222222222 = {CreatedOnToolsVersion = 16.0; TestTargetID = 111111111111111111111111; }; }; }; buildConfigurationList = AAAAAAAAAAAAAAAAAAAAAA43; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = 444444444444444444444444; productRefGroup = AAAAAAAAAAAAAAAAAAAAAA33; projectDirPath = ""; projectRoot = ""; targets = (111111111111111111111111, 222222222222222222222222,); };
    AAAAAAAAAAAAAAAAAAAAAA52 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    AAAAAAAAAAAAAAAAAAAAAA54 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
    AAAAAAAAAAAAAAAAAAAAAA51 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (AAAAAAAAAAAAAAAAAAAAAA01,); runOnlyForDeploymentPostprocessing = 0; };
    AAAAAAAAAAAAAAAAAAAAAA53 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (AAAAAAAAAAAAAAAAAAAAAA02,); runOnlyForDeploymentPostprocessing = 0; };
    AAAAAAAAAAAAAAAAAAAAAA61 = {isa = XCBuildConfiguration; buildSettings = {ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; GCC_C_LANGUAGE_STANDARD = gnu17; GCC_NO_COMMON_BLOCKS = YES; IPHONEOS_DEPLOYMENT_TARGET = 15.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; }; name = Debug; };
    AAAAAAAAAAAAAAAAAAAAAA62 = {isa = XCBuildConfiguration; buildSettings = {ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; GCC_C_LANGUAGE_STANDARD = gnu17; GCC_NO_COMMON_BLOCKS = YES; IPHONEOS_DEPLOYMENT_TARGET = 15.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; }; name = Release; };
    AAAAAAAAAAAAAAAAAAAAAA63 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGNING_ALLOWED = NO; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = $iosXCTestProjectName/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 15.0; PRODUCT_BUNDLE_IDENTIFIER = org.flutteroh.fluoh.iosautomation; PRODUCT_NAME = "\$(TARGET_NAME)"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; }; name = Debug; };
    AAAAAAAAAAAAAAAAAAAAAA64 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGNING_ALLOWED = NO; CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = $iosXCTestProjectName/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 15.0; PRODUCT_BUNDLE_IDENTIFIER = org.flutteroh.fluoh.iosautomation; PRODUCT_NAME = "\$(TARGET_NAME)"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; }; name = Release; };
    AAAAAAAAAAAAAAAAAAAAAA65 = {isa = XCBuildConfiguration; buildSettings = {ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES; CODE_SIGNING_ALLOWED = NO; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ${iosXCTestProjectName}UITests/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 15.0; PRODUCT_BUNDLE_IDENTIFIER = org.flutteroh.fluoh.iosautomation.uitests; PRODUCT_NAME = "\$(TARGET_NAME)"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = $iosXCTestProjectName; WRAPPER_EXTENSION = xctest; }; name = Debug; };
    AAAAAAAAAAAAAAAAAAAAAA66 = {isa = XCBuildConfiguration; buildSettings = {ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES; CODE_SIGNING_ALLOWED = NO; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ${iosXCTestProjectName}UITests/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 15.0; PRODUCT_BUNDLE_IDENTIFIER = org.flutteroh.fluoh.iosautomation.uitests; PRODUCT_NAME = "\$(TARGET_NAME)"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = $iosXCTestProjectName; WRAPPER_EXTENSION = xctest; }; name = Release; };
    AAAAAAAAAAAAAAAAAAAAAA41 = {isa = XCConfigurationList; buildConfigurations = (AAAAAAAAAAAAAAAAAAAAAA63, AAAAAAAAAAAAAAAAAAAAAA64,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    AAAAAAAAAAAAAAAAAAAAAA42 = {isa = XCConfigurationList; buildConfigurations = (AAAAAAAAAAAAAAAAAAAAAA65, AAAAAAAAAAAAAAAAAAAAAA66,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    AAAAAAAAAAAAAAAAAAAAAA43 = {isa = XCConfigurationList; buildConfigurations = (AAAAAAAAAAAAAAAAAAAAAA61, AAAAAAAAAAAAAAAAAAAAAA62,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
  };
  rootObject = 333333333333333333333333;
}
''';
}
