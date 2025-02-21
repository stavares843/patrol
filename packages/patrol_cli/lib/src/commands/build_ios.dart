import 'package:path/path.dart' show basename;
import 'package:patrol_cli/src/base/exceptions.dart';
import 'package:patrol_cli/src/base/extensions/core.dart';
import 'package:patrol_cli/src/base/logger.dart';
import 'package:patrol_cli/src/crossplatform/app_options.dart';
import 'package:patrol_cli/src/dart_defines_reader.dart';
import 'package:patrol_cli/src/ios/ios_test_backend.dart';
import 'package:patrol_cli/src/pubspec_reader.dart';
import 'package:patrol_cli/src/runner/patrol_command.dart';
import 'package:patrol_cli/src/test_finder.dart';

class BuildIOSCommand extends PatrolCommand {
  BuildIOSCommand({
    required TestFinder testFinder,
    required DartDefinesReader dartDefinesReader,
    required PubspecReader pubspecReader,
    required IOSTestBackend iosTestBackend,
    required Logger logger,
  })  : _testFinder = testFinder,
        _dartDefinesReader = dartDefinesReader,
        _pubspecReader = pubspecReader,
        _iosTestBackend = iosTestBackend,
        _logger = logger {
    usesTargetOption();
    usesBuildModeOption();
    usesFlavorOption();
    usesDartDefineOption();
    usesLabelOption();
    usesWaitOption();

    usesIOSOptions();
    argParser.addFlag(
      'simulator',
      help: 'Build for simulator instead of real device.',
    );
  }

  final TestFinder _testFinder;
  final DartDefinesReader _dartDefinesReader;
  final PubspecReader _pubspecReader;
  final IOSTestBackend _iosTestBackend;

  final Logger _logger;

  @override
  String get name => 'ios';

  @override
  String get description => 'Build app for integration testing on iOS.';

  @override
  Future<int> run() async {
    final targetArg = stringsArg('target');
    if (targetArg.isEmpty) {
      throwToolExit('No test target specified');
    } else if (targetArg.length > 1) {
      throwToolExit('Only one test target can be specified');
    }
    final target = _testFinder.findTest(targetArg.single);
    _logger.detail('Received test target: $target');

    final config = _pubspecReader.read();
    final flavor = stringArg('flavor') ?? config.ios.flavor;
    if (flavor != null) {
      _logger.detail('Received iOS flavor: $flavor');
    }

    final bundleId = stringArg('bundle-id') ?? config.ios.bundleId;

    final displayLabel = boolArg('label');

    final customDartDefines = {
      ..._dartDefinesReader.fromFile(),
      ..._dartDefinesReader.fromCli(args: stringsArg('dart-define')),
    };
    final internalDartDefines = {
      'PATROL_WAIT': defaultWait.toString(),
      'PATROL_APP_BUNDLE_ID': bundleId,
      'PATROL_IOS_APP_NAME': config.ios.appName,
      if (displayLabel) 'PATROL_TEST_LABEL': basename(target),
    }.withNullsRemoved();

    final dartDefines = {...customDartDefines, ...internalDartDefines};
    _logger.detail(
      'Received ${dartDefines.length} --dart-define(s) '
      '(${customDartDefines.length} custom, ${internalDartDefines.length} internal)',
    );
    for (final dartDefine in customDartDefines.entries) {
      _logger.detail('Received custom --dart-define: ${dartDefine.key}');
    }
    for (final dartDefine in internalDartDefines.entries) {
      _logger.detail(
        'Received internal --dart-define: ${dartDefine.key}=${dartDefine.value}',
      );
    }

    final flutterOpts = FlutterAppOptions(
      target: target,
      flavor: flavor,
      buildMode: buildMode,
      dartDefines: dartDefines,
    );

    final iosOpts = IOSAppOptions(
      flutter: flutterOpts,
      scheme: flutterOpts.buildMode.createScheme(flavor),
      configuration: flutterOpts.buildMode.createConfiguration(flavor),
      simulator: boolArg('simulator'),
    );

    try {
      await _iosTestBackend.build(iosOpts);
      _printBinaryPaths(
        simulator: iosOpts.simulator,
        buildMode: flutterOpts.buildMode.xcodeName,
      );
    } catch (err, st) {
      _logger
        ..err('$err')
        ..detail('$st')
        ..err(defaultFailureMessage);
      rethrow;
    }

    return 0;
  }

  void _printBinaryPaths({required bool simulator, required String buildMode}) {
    // print path for 2 apps that live in build/ios_integ/Build/Products

    final buildDir = simulator
        ? 'build/ios_integ/Build/Products/$buildMode-iphonesimulator'
        : 'build/ios_integ/Build/Products/$buildMode-iphoneos';

    final appPath = '$buildDir/Runner.app';
    final testAppPath = '$buildDir/RunnerUITests-Runner.app';

    _logger
      ..info('App path: $appPath')
      ..info('Test app path: $testAppPath');
  }
}
