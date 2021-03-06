// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:process/process.dart';

const LocalProcessManager processManager = LocalProcessManager();

/// Runs the Android SDK Lint tool on flutter/shell/platform/android.
///
/// This script scans the flutter/shell/platform/android directory for Java
/// files to build a `project.xml` file.  This file is then passed to the lint
/// tool and HTML output is reqeusted in the directory for the `--out`
/// parameter, which defaults to `lint_report`.
///
/// The `--in` parameter may be specified to force this script to scan a
/// specific location for the engine repository, and expects to be given the
/// `src` directory that contains both `third_party` and `flutter`.
///
/// At the time of this writing, the Android Lint tool doesn't work well with
/// Java > 1.8.  This script will print a warning if you are not running
/// Java 1.8.
Future<void> main(List<String> args) async {
  final ArgParser argParser = setupOptions();
  await checkJava1_8();
  final int exitCode = await runLint(argParser, argParser.parse(args));
  exit(exitCode);
}

Future<int> runLint(ArgParser argParser, ArgResults argResults) async {
  final Directory androidDir = Directory(path.join(
    argResults['in'],
    'flutter',
    'shell',
    'platform',
    'android',
  ));
  if (!androidDir.existsSync()) {
    print('This command must be run from the engine/src directory, '
        'or be passed that directory as the --in parameter.\n');
    print(argParser.usage);
    return -1;
  }

  final Directory androidSdkDir = Directory(
    path.join(argResults['in'], 'third_party', 'android_tools', 'sdk'),
  );

  if (!androidSdkDir.existsSync()) {
    print('The Android SDK for this engine is missing from the '
        'third_party/android_tools directory. Have you run gclient sync?\n');
    print(argParser.usage);
    return -1;
  }

  if (argResults['rebaseline']) {
    print('Removing previous baseline.xml...');
    final File baselineXml = File(baselineXmlPath);
    if (baselineXml.existsSync()) {
      await baselineXml.delete();
    }
  }
  print('Preparing projext.xml...');
  final IOSink projectXml = File(projectXmlPath).openWrite();
  projectXml.write(
      '''<!-- THIS FILE IS GENERATED. PLEASE USE THE INCLUDED DART PROGRAM  WHICH -->
<!-- WILL AUTOMATICALLY FIND ALL .java FILES AND INCLUDE THEM HERE       -->
<project>
  <sdk dir="${androidSdkDir.path}" />
  <module name="FlutterEngine" android="true" library="true" compile-sdk-version="android-P">
  <manifest file="${path.join(androidDir.path, 'AndroidManifest.xml')}" />
''');
  for (final FileSystemEntity entity in androidDir.listSync(recursive: true)) {
    if (!entity.path.endsWith('.java')) {
      continue;
    }
    projectXml.writeln('    <src file="${entity.path}" />');
  }

  projectXml.write('''  </module>
</project>
''');
  await projectXml.close();

  print('Wrote project.xml, starting lint...');
  final Process lintProcess = await processManager.start(
    <String>[
      path.join(androidSdkDir.path, 'tools', 'bin', 'lint'),
      '--project',
      projectXmlPath,
      '--html',
      argResults['out'],
      '--showall',
      '--exitcode', // Set non-zero exit code on errors
      '-Wall',
      '-Werror',
      '--baseline',
      baselineXmlPath,
    ],
  );
  lintProcess.stdout.pipe(stdout);
  lintProcess.stderr.pipe(stderr);
  return await lintProcess.exitCode;
}

/// Prepares an [ArgParser] for this script.
ArgParser setupOptions() {
  final ArgParser argParser = ArgParser();
  argParser
    ..addOption(
      'in',
      help: 'The path to `engine/src`.',
      defaultsTo: path.relative(
        path.join(
          projectDir,
          '..',
          '..',
          '..',
        ),
      ),
    )
    ..addOption(
      'out',
      help: 'The path to write the generated the HTML report to.',
      defaultsTo: path.join(projectDir, 'lint_report'),
    )
    ..addFlag(
      'help',
      help: 'Print usage of the command.',
      negatable: false,
      defaultsTo: false,
    )
    ..addFlag(
      'rebaseline',
      help: 'Recalculates the baseline for errors and warnings '
          'in this project.',
      negatable: false,
      defaultsTo: false,
    );

  return argParser;
}

/// Checks that `java` points to Java 1.8.
///
/// The SDK lint tool may not work with Java > 1.8.
Future<void> checkJava1_8() async {
  print('Checking Java version...');
  final ProcessResult javaResult = await processManager.run(
    <String>['java', '-version'],
  );
  if (javaResult.exitCode != 0) {
    print('Could not run "java -version". '
        'Ensure Java is installed and available on your path.');
    print(javaResult.stderr);
  }
  final String javaVersionStdout = javaResult.stdout;
  if (javaVersionStdout.contains('"1.8')) {
    print('The Android SDK tools may not work properly with your Java version. '
        'If this process fails, please retry using Java 1.8.');
  }
}

/// The root directory of this project.
String get projectDir => path.dirname(
      path.dirname(
        path.fromUri(Platform.script),
      ),
    );

/// The path to use for project.xml, which tells the linter where to find source
/// files.
String get projectXmlPath => path.join(projectDir, 'project.xml');

/// The path to use for baseline.xml, which tells the linter what errors or
/// warnings to ignore.
String get baselineXmlPath => path.join(projectDir, 'baseline.xml');
