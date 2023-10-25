// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import 'recorder.dart';

const String chars = '1234567890'
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '!@#%^&()[]{}<>,./?;:"`~-_=+|';

String _randomize(String text) {
  return text.replaceAllMapped(
    '*',
    // Passing a seed so the results are reproducible.
    (_) => chars[Random(0).nextInt(chars.length)],
  );
}

class ParagraphGenerator {
  int _counter = 0;

  /// Randomizes the given [text] and creates a paragraph with a unique
  /// font-size so that the engine doesn't reuse a cached ruler.
  ui.Paragraph generate(
    String text, {
    int maxLines,
    bool hasEllipsis = false,
  }) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: 'sans-serif',
      maxLines: maxLines,
      ellipsis: hasEllipsis ? '...' : null,
    ))
      // Start from a font-size of 8.0 and go up by 0.01 each time.
      ..pushStyle(ui.TextStyle(fontSize: 8.0 + _counter * 0.01))
      ..addText(_randomize(text));
    _counter++;
    return builder.build();
  }
}

/// Sends a platform message to the web engine to enable/disable the usage of
/// the new canvas-based text measurement implementation.
void _useCanvasText(bool useCanvasText) {
  js_util.callMethod(
    html.window,
    '_flutter_internal_update_experiment',
    <dynamic>['useCanvasText', useCanvasText],
  );
}

/// Repeatedly lays out a paragraph using the DOM measurement approach.
///
/// Creates a different paragraph each time in order to avoid hitting the cache.
class BenchTextLayout extends RawRecorder {
  BenchTextLayout({@required this.useCanvas})
      : super(name: useCanvas ? canvasBenchmarkName : domBenchmarkName);

  static const String domBenchmarkName = 'text_dom_layout';
  static const String canvasBenchmarkName = 'text_canvas_layout';

  final ParagraphGenerator generator = ParagraphGenerator();

  /// Whether to use the new canvas-based text measurement implementation.
  final bool useCanvas;

  static const String singleLineText = '*** ** ****';
  static const String multiLineText = '*** ****** **** *** ******** * *** '
      '******* **** ********** *** ******* '
      '**** ***** *** ******** *** ********* '
      '** * *** ******* ***********';

  @override
  void body(Profile profile) {
    _useCanvasText(useCanvas);

    recordParagraphOperations(
      profile: profile,
      paragraph: generator.generate(singleLineText),
      text: singleLineText,
      keyPrefix: 'single_line',
      maxWidth: 800.0,
    );

    recordParagraphOperations(
      profile: profile,
      paragraph: generator.generate(multiLineText),
      text: multiLineText,
      keyPrefix: 'multi_line',
      maxWidth: 200.0,
    );

    recordParagraphOperations(
      profile: profile,
      paragraph: generator.generate(multiLineText, maxLines: 2),
      text: multiLineText,
      keyPrefix: 'max_lines',
      maxWidth: 200.0,
    );

    recordParagraphOperations(
      profile: profile,
      paragraph: generator.generate(multiLineText, hasEllipsis: true),
      text: multiLineText,
      keyPrefix: 'ellipsis',
      maxWidth: 200.0,
    );

    _useCanvasText(null);
  }

  void recordParagraphOperations({
    @required Profile profile,
    @required ui.Paragraph paragraph,
    @required String text,
    @required String keyPrefix,
    @required double maxWidth,
  }) {
    profile.record('$keyPrefix.layout', () {
      paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
    }, reported: true);
    profile.record('$keyPrefix.getBoxesForRange', () {
      for (int start = 0; start < text.length; start += 3) {
        for (int end = start + 1; end < text.length; end *= 2) {
          paragraph.getBoxesForRange(start, end);
        }
      }
    }, reported: true);
    profile.record('$keyPrefix.getPositionForOffset', () {
      for (double dx = 0.0; dx < paragraph.width; dx += 10.0) {
        for (double dy = 0.0; dy < paragraph.height; dy += 10.0) {
          paragraph.getPositionForOffset(Offset(dx, dy));
        }
      }
    }, reported: true);
  }
}

/// Repeatedly lays out a paragraph using the DOM measurement approach.
///
/// Uses the same paragraph content to make sure we hit the cache. It doesn't
/// use the same paragraph instance because the layout method will shortcircuit
/// in that case.
class BenchTextCachedLayout extends RawRecorder {
  BenchTextCachedLayout({@required this.useCanvas})
      : super(name: useCanvas ? canvasBenchmarkName : domBenchmarkName);

  static const String domBenchmarkName = 'text_dom_cached_layout';
  static const String canvasBenchmarkName = 'text_canvas_cached_layout';

  /// Whether to use the new canvas-based text measurement implementation.
  final bool useCanvas;

  final ui.ParagraphBuilder builder =
      ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'sans-serif'))
        ..pushStyle(ui.TextStyle(fontSize: 12.0))
        ..addText(
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit, '
          'sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
        );

  @override
  void body(Profile profile) {
    _useCanvasText(useCanvas);
    final ui.Paragraph paragraph = builder.build();
    profile.record('layout', () {
      paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    }, reported: true);
    _useCanvasText(null);
  }
}

/// Global counter incremented every time the benchmark is asked to
/// [createWidget].
///
/// The purpose of this counter is to make sure the rendered paragraphs on each
/// build are unique.
int _counter = 0;

/// Which mode to run [BenchBuildColorsGrid] in.
enum _TestMode {
  /// Uses the HTML rendering backend with the canvas 2D text layout.
  useCanvasTextLayout,

  /// Uses the HTML rendering backend with the DOM text layout.
  useDomTextLayout,

  /// Uses CanvasKit for everything.
  useCanvasKit,
}

/// Measures how expensive it is to construct a realistic text-heavy piece of UI.
///
/// The benchmark constructs a tabbed view, where each tab displays a list of
/// colors. Each color's description is made of several [Text] nodes.
class BenchBuildColorsGrid extends WidgetBuildRecorder {
  BenchBuildColorsGrid.canvas()
      : mode = _TestMode.useCanvasTextLayout, super(name: canvasBenchmarkName);
  BenchBuildColorsGrid.dom()
      : mode = _TestMode.useDomTextLayout, super(name: domBenchmarkName);
  BenchBuildColorsGrid.canvasKit()
      : mode = _TestMode.useCanvasKit, super(name: canvasKitBenchmarkName);

  /// Disables tracing for this benchmark.
  ///
  /// When tracing is enabled, DOM layout takes longer to complete. This has a
  /// significant effect on the benchmark since we do a lot of text layout
  /// operations that trigger synchronous DOM layout.
  ///
  /// Tracing has a negative effect only in [_TestMode.useDomTextLayout] mode.
  @override
  bool get isTracingEnabled => false;

  static const String domBenchmarkName = 'text_dom_color_grid';
  static const String canvasBenchmarkName = 'text_canvas_color_grid';
  static const String canvasKitBenchmarkName = 'text_canvas_kit_color_grid';

  /// Whether to use the new canvas-based text measurement implementation.
  final _TestMode mode;

  num _textLayoutMicros = 0;

  @override
  Future<void> setUpAll() async {
    if (mode == _TestMode.useCanvasTextLayout) {
      _useCanvasText(true);
    }
    if (mode == _TestMode.useDomTextLayout) {
      _useCanvasText(false);
    }
    registerEngineBenchmarkValueListener('text_layout', (num value) {
      _textLayoutMicros += value;
    });
  }

  @override
  Future<void> tearDownAll() async {
    _useCanvasText(null);
    stopListeningToEngineBenchmarkValues('text_layout');
  }

  @override
  void frameWillDraw() {
    super.frameWillDraw();
    _textLayoutMicros = 0;
  }

  @override
  void frameDidDraw() {
    // We need to do this before calling [super.frameDidDraw] because the latter
    // updates the value of [showWidget] in preparation for the next frame.
    // TODO(yjbanov): https://github.com/flutter/flutter/issues/53877
    if (showWidget && mode != _TestMode.useCanvasKit) {
      profile.addDataPoint(
        'text_layout',
        Duration(microseconds: _textLayoutMicros.toInt()),
        reported: true,
      );
    }
    super.frameDidDraw();
  }

  @override
  Widget createWidget() {
    _counter++;
    return MaterialApp(home: ColorsDemo());
  }
}

// The code below was copied from `colors_demo.dart` in the `flutter_gallery`
// example.

const double kColorItemHeight = 48.0;

class Palette {
  Palette({this.name, this.primary, this.accent, this.threshold = 900});

  final String name;
  final MaterialColor primary;
  final MaterialAccentColor accent;
  final int
      threshold; // titles for indices > threshold are white, otherwise black

  bool get isValid => primary != null;
}

final List<Palette> allPalettes = <Palette>[
  Palette(
      name: 'RED',
      primary: Colors.red,
      accent: Colors.redAccent,
      threshold: 300),
  Palette(
      name: 'PINK',
      primary: Colors.pink,
      accent: Colors.pinkAccent,
      threshold: 200),
  Palette(
      name: 'PURPLE',
      primary: Colors.purple,
      accent: Colors.purpleAccent,
      threshold: 200),
  Palette(
      name: 'DEEP PURPLE',
      primary: Colors.deepPurple,
      accent: Colors.deepPurpleAccent,
      threshold: 200),
  Palette(
      name: 'INDIGO',
      primary: Colors.indigo,
      accent: Colors.indigoAccent,
      threshold: 200),
  Palette(
      name: 'BLUE',
      primary: Colors.blue,
      accent: Colors.blueAccent,
      threshold: 400),
  Palette(
      name: 'LIGHT BLUE',
      primary: Colors.lightBlue,
      accent: Colors.lightBlueAccent,
      threshold: 500),
  Palette(
      name: 'CYAN',
      primary: Colors.cyan,
      accent: Colors.cyanAccent,
      threshold: 600),
  Palette(
      name: 'TEAL',
      primary: Colors.teal,
      accent: Colors.tealAccent,
      threshold: 400),
  Palette(
      name: 'GREEN',
      primary: Colors.green,
      accent: Colors.greenAccent,
      threshold: 500),
  Palette(
      name: 'LIGHT GREEN',
      primary: Colors.lightGreen,
      accent: Colors.lightGreenAccent,
      threshold: 600),
  Palette(
      name: 'LIME',
      primary: Colors.lime,
      accent: Colors.limeAccent,
      threshold: 800),
  Palette(name: 'YELLOW', primary: Colors.yellow, accent: Colors.yellowAccent),
  Palette(name: 'AMBER', primary: Colors.amber, accent: Colors.amberAccent),
  Palette(
      name: 'ORANGE',
      primary: Colors.orange,
      accent: Colors.orangeAccent,
      threshold: 700),
  Palette(
      name: 'DEEP ORANGE',
      primary: Colors.deepOrange,
      accent: Colors.deepOrangeAccent,
      threshold: 400),
  Palette(name: 'BROWN', primary: Colors.brown, threshold: 200),
  Palette(name: 'GREY', primary: Colors.grey, threshold: 500),
  Palette(name: 'BLUE GREY', primary: Colors.blueGrey, threshold: 500),
];

class ColorItem extends StatelessWidget {
  const ColorItem({
    Key key,
    @required this.index,
    @required this.color,
    this.prefix = '',
  })  : assert(color != null),
        super(key: key);

  final int index;
  final Color color;
  final String prefix;

  String colorString() =>
      "$_counter:#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}";

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        height: kColorItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        color: color,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text('$_counter:$prefix$index'),
              Text(colorString()),
            ],
          ),
        ),
      ),
    );
  }
}

class PaletteTabView extends StatelessWidget {
  PaletteTabView({
    Key key,
    @required this.colors,
  })  : assert(colors.isValid),
        super(key: key);

  final Palette colors;

  static const List<int> primaryKeys = <int>[
    50,
    100,
    200,
    300,
    400,
    500,
    600,
    700,
    800,
    900
  ];
  static const List<int> accentKeys = <int>[100, 200, 400, 700];

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle whiteTextStyle =
        textTheme.bodyText2.copyWith(color: Colors.white);
    final TextStyle blackTextStyle =
        textTheme.bodyText2.copyWith(color: Colors.black);
    return Scrollbar(
      child: ListView(
        itemExtent: kColorItemHeight,
        children: <Widget>[
          ...primaryKeys.map<Widget>((int index) {
            return DefaultTextStyle(
              style: index > colors.threshold ? whiteTextStyle : blackTextStyle,
              child: ColorItem(index: index, color: colors.primary[index]),
            );
          }),
          if (colors.accent != null)
            ...accentKeys.map<Widget>((int index) {
              return DefaultTextStyle(
                style:
                    index > colors.threshold ? whiteTextStyle : blackTextStyle,
                child: ColorItem(
                    index: index, color: colors.accent[index], prefix: 'A'),
              );
            }),
        ],
      ),
    );
  }
}

class ColorsDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: allPalettes.length,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0.0,
          title: const Text('Colors'),
          bottom: TabBar(
            isScrollable: true,
            tabs: allPalettes
                .map<Widget>(
                    (Palette swatch) => Tab(text: '$_counter:${swatch.name}'))
                .toList(),
          ),
        ),
        body: TabBarView(
          children: allPalettes.map<Widget>((Palette colors) {
            return PaletteTabView(colors: colors);
          }).toList(),
        ),
      ),
    );
  }
}
