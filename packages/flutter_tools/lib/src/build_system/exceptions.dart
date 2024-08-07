// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


import 'build_system.dart';

/// An exception thrown when a rule declares an input that does not exist on
/// disk.
class MissingInputException implements Exception {
  const MissingInputException(this.missing, this.target);

  /// The file or directory we expected to find.
  final List<File> missing;

  /// The name of the target this file should have been output from.
  final String target;

  @override
  String toString() {
    final String files = missing.map((File file) => file.path).join(', ');
    return '$files were declared as an inputs, but did not exist. '
        'Check the definition of target:$target for errors';
  }
}

/// An exception thrown if we detect a cycle in the dependencies of a target.
class CycleException implements Exception {
  CycleException(this.targets);

  final Set<Target> targets;

  @override
  String toString() => 'Dependency cycle detected in build: '
      '${targets.map((Target target) => target.name).join(' -> ')}';
}

/// An exception thrown when a pattern is invalid.
class InvalidPatternException implements Exception {
  InvalidPatternException(this.pattern);

  final String pattern;

  @override
  String toString() => 'The pattern "$pattern" is not valid';
}

/// An exception thrown when a rule declares an output that was not produced
/// by the invocation.
class MissingOutputException implements Exception {
  const MissingOutputException(this.missing, this.target);

  /// The files we expected to find.
  final List<File> missing;

  /// The name of the target this file should have been output from.
  final String target;

  @override
  String toString() {
    final String files = missing.map((File file) => file.path).join(', ');
    return '$files were declared as outputs, but were not generated by '
        'the action. Check the definition of target:$target for errors';
  }
}

/// An exception thrown when in output is placed outside of
/// [Environment.buildDir].
class MisplacedOutputException implements Exception {
  MisplacedOutputException(this.path, this.target);

  final String path;
  final String target;

  @override
  String toString() {
    return 'Target $target produced an output at $path'
        ' which is outside of the current build or project directory';
  }
}

/// An exception thrown if a build action is missing a required define.
class MissingDefineException implements Exception {
  MissingDefineException(this.define, this.target);

  final String define;
  final String target;

  @override
  String toString() {
    return 'Target $target required define $define '
        'but it was not provided';
  }
}
