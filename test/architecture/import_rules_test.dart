// Architecture test: the import graph of lib/ is a DAG with a fixed layer
// order (architecture.md §5 and §18.2).
//
// This file is checked in before any application code so that the first
// import that breaks the layering fails CI. Adding a layer or a services
// sub-package means editing the rank tables below in the same pull request.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dart package name, as declared in pubspec.yaml.
const packageName = 'ketoclub';

/// Top-level layers under lib/, lowest first. A file may import only files
/// whose layer rank is less than or equal to its own.
const layerRank = <String, int>{
  'models': 0,
  'l10n': 0,
  'utils': 1,
  'services': 2,
  'state': 3,
  'widgets': 4,
  'screens': 5,
};

/// Files that live directly under lib/ (not in a layer directory).
const rootFileRank = <String, int>{'app.dart': 6, 'di.dart': 7, 'main.dart': 7};

/// Sub-packages under lib/services/. A sub-package may import only
/// sub-packages of equal or lower rank. Cycles within one sub-package are
/// still caught by the cycle test.
const serviceRank = <String, int>{
  'platform': 0,
  'storage': 0,
  'llm': 0,
  'location': 0,
  'venue': 0,
  'menu': 1,
  'classifier': 1,
};

/// Layers that must not import Flutter beyond foundation.dart.
const pureDartLayers = <String>{'models', 'utils', 'services'};

/// The only Flutter import allowed in the pure-Dart layers.
const allowedFlutterImport = 'package:flutter/foundation.dart';

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// A file under lib/, identified by its path relative to lib/ using `/`.
class _LibFile {
  new(this.relativePath, this.imports);

  final String relativePath;
  final List<String> imports;

  String get layer {
    final slash = relativePath.indexOf('/');
    return slash == -1 ? '' : relativePath.substring(0, slash);
  }

  /// The services sub-package, or null when not under services/.
  String? get servicePackage {
    if (layer != 'services') return null;
    final parts = relativePath.split('/');
    return parts.length >= 3 ? parts[1] : null;
  }

  int? get rank =>
      layer.isEmpty ? rootFileRank[relativePath] : layerRank[layer];

  /// A short label for messages: the layer, or the file name at lib/ root.
  String get label => layer.isEmpty ? relativePath : layer;
}

/// Reads every .dart file under lib/ and resolves the imports that point
/// inside this package to lib-relative paths. Imports of other packages and
/// of dart: libraries are dropped.
Map<String, _LibFile> _readLib() {
  final lib = Directory('lib');
  if (!lib.existsSync()) return <String, _LibFile>{};

  final dartFiles =
      lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final files = <String, _LibFile>{};
  for (final file in dartFiles) {
    final relative = _toLibRelative(file.path);
    final source = file.readAsStringSync();
    final resolved = <String>[];
    for (final m in _directive.allMatches(source)) {
      final target = m.group(1);
      if (target == null) continue;
      final path = _resolve(target, relative);
      if (path != null) resolved.add(path);
    }
    files[relative] = _LibFile(relative, resolved);
  }
  return files;
}

String _toLibRelative(String path) {
  final normalised = path.replaceAll(r'\', '/');
  final idx = normalised.indexOf('lib/');
  return normalised.substring(idx + 'lib/'.length);
}

/// Resolves an import URI to a lib-relative path, or null if it is not part
/// of this package.
String? _resolve(String uri, String importerRelative) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    const prefix = 'package:$packageName/';
    return uri.startsWith(prefix) ? uri.substring(prefix.length) : null;
  }
  // Relative import: resolve against the importer's directory.
  final base = importerRelative.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (base.isEmpty) return null; // escapes lib/
      base.removeLast();
    } else {
      base.add(segment);
    }
  }
  return base.join('/');
}

/// Raw (unresolved) Flutter imports of a file, for the pure-Dart check.
List<String> _flutterImportsOf(String relativePath) {
  final source = File('lib/$relativePath').readAsStringSync();
  return _directive
      .allMatches(source)
      .map((m) => m.group(1) ?? '')
      .where((uri) => uri.startsWith('package:flutter/'))
      .toList();
}

/// Finds one cycle in the graph, or null if the graph is acyclic.
List<String>? _findCycle(Map<String, _LibFile> files) {
  const white = 0;
  const grey = 1;
  const black = 2;
  final colour = <String, int>{};
  final stack = <String>[];

  List<String>? visit(String node) {
    colour[node] = grey;
    stack.add(node);
    final file = files[node];
    if (file != null) {
      for (final next in file.imports) {
        final c = colour[next] ?? white;
        if (c == grey) {
          return stack.sublist(stack.indexOf(next))..add(next);
        }
        if (c == white) {
          final found = visit(next);
          if (found != null) return found;
        }
      }
    }
    stack.removeLast();
    colour[node] = black;
    return null;
  }

  for (final node in files.keys) {
    if ((colour[node] ?? white) == white) {
      final found = visit(node);
      if (found != null) return found;
    }
  }
  return null;
}

void main() {
  final files = _readLib();

  test('every file under lib/ is in a known layer', () {
    final unknown = files.values
        .where((f) => f.rank == null)
        .map((f) => f.relativePath)
        .toList();
    expect(
      unknown,
      isEmpty,
      reason:
          'Files outside the layer tables in import_rules_test.dart: '
          '$unknown. Add the layer to architecture.md §5 and to this test.',
    );
  });

  test('every services sub-package has a rank', () {
    final unknown = files.values
        .where((f) => f.layer == 'services')
        .where((f) => !serviceRank.containsKey(f.servicePackage))
        .map((f) => f.relativePath)
        .toList();
    expect(
      unknown,
      isEmpty,
      reason:
          'Files under lib/services/ must live in a ranked sub-package: '
          '$unknown. See architecture.md §5.',
    );
  });

  test('imports only point to the same or a lower layer', () {
    final violations = <String>[];
    for (final importer in files.values) {
      final from = importer.rank;
      if (from == null) continue;
      for (final target in importer.imports) {
        final importee = files[target];
        final to = importee?.rank;
        if (importee == null || to == null) continue; // reported above
        if (to > from) {
          violations.add(
            '${importer.relativePath} -> $target '
            '(${importer.label} may not import ${importee.label})',
          );
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('services sub-packages import only equal or lower ranked ones', () {
    final violations = <String>[];
    for (final importer in files.values) {
      final fromPkg = importer.servicePackage;
      if (fromPkg == null) continue;
      final from = serviceRank[fromPkg] ?? -1;
      for (final target in importer.imports) {
        final toPkg = files[target]?.servicePackage;
        if (toPkg == null) continue;
        final to = serviceRank[toPkg] ?? -1;
        if (to > from) {
          violations.add(
            '${importer.relativePath} -> $target '
            '(services/$fromPkg may not import services/$toPkg)',
          );
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('models, utils and services do not import Flutter widgets', () {
    final violations = <String>[];
    for (final f in files.values) {
      if (!pureDartLayers.contains(f.layer)) continue;
      for (final uri in _flutterImportsOf(f.relativePath)) {
        if (uri != allowedFlutterImport) {
          violations.add('${f.relativePath} imports $uri');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Only $allowedFlutterImport is allowed below state/:\n'
          '${violations.join('\n')}',
    );
  });

  test('the import graph of lib/ has no cycles', () {
    final cycle = _findCycle(files);
    expect(cycle, isNull, reason: 'Import cycle: ${cycle?.join(' -> ')}');
  });
}
