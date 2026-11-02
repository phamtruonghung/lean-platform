/// One way to ask a pumped Screen where a keyboard can go (issue #401).
///
/// The focus policy in `docs/design-language.md` §8 makes four promises that a
/// test has to be able to check on any surface: the **first** thing `Tab`
/// reaches, the **last** one, that a dialog's **trap** holds, and that focus is
/// **restored** to the control that opened it. Six surfaces prove them —
/// a register, a detail, a form dialog, a confirm dialog, the Shell and the
/// sign-in Screen — and six hand-written walks would be six chances to check a
/// slightly different thing.
///
/// So this walks, and everything it reports is what a reader would be told: the
/// nearest `Key` above the focused control, the first word inside it, and
/// whether it is a text field. Nothing here reaches into a Bloc, a Screen's
/// state or a `FocusNode` the Screen owns — `FocusManager.instance.primaryFocus`
/// is the same reading a screen reader takes.
///
/// The stops are named by what is *painted*, never by a test-only marker: a
/// `Key` that only exists while a ring is drawn would remount the subtree under
/// it, so [FocusWalker.ringIsVisible] reads the decoration `AppFocusRing`
/// actually draws instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/theme.dart';
import 'package:lean_platform/widgets/app_focus_ring.dart';

/// Where focus landed, in the terms an assertion can name.
class FocusStop {
  const FocusStop({this.key, this.text, this.field = false});

  const FocusStop.nothing()
      : key = null,
        text = null,
        field = false;

  /// The nearest keyed widget above the focused control — a button's own key,
  /// a register row's, a Destination's.
  final Key? key;

  /// The first word inside the focused control (a button's label, a row's
  /// first cell). Null for a text field, whose value is the reader's, not the
  /// Screen's.
  final String? text;

  /// Whether the focus sits inside an `EditableText`.
  final bool field;

  bool get isNothing => key == null && text == null && !field;

  /// One line, for a failure message: what the reader would have been told.
  String describe() =>
      text ?? key?.toString() ?? (field ? 'a text field' : 'nothing');

  @override
  String toString() => describe();
}

class FocusWalker {
  FocusWalker(this.tester);

  final WidgetTester tester;

  /// Where focus is right now.
  FocusStop get now {
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    if (context == null) return const FocusStop.nothing();
    final element = context as Element;
    return FocusStop(
      key: _namedKey(element),
      text: _firstText(element),
      field: _isField(element),
    );
  }

  /// Presses `Tab` [count] times, returning the stop each press landed on.
  Future<List<FocusStop>> forward([int count = 1]) async {
    final stops = <FocusStop>[];
    for (var i = 0; i < count; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      stops.add(now);
    }
    return stops;
  }

  /// Presses `Shift+Tab` [count] times — the walk backwards, which is how a
  /// reader reaches the first stop of a region from inside it.
  Future<List<FocusStop>> backward([int count = 1]) async {
    final stops = <FocusStop>[];
    for (var i = 0; i < count; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      stops.add(now);
    }
    return stops;
  }

  /// Puts focus on the first control inside [subtree] that `Tab` would stop on,
  /// the way a reader arrives at a region (a register's rows, a Screen's page).
  ///
  /// Read off the scope's own `traversalDescendants` rather than by hunting for
  /// `Focus` widgets: a Material button keeps its focus node private to its
  /// state, so walking the widget tree finds the node of a plain `InkWell` and
  /// nothing else. Traversal order is the same order `Tab` walks.
  Future<FocusStop> enter(Finder subtree) async {
    final element = tester.element(subtree.first);
    final scope = FocusScope.of(element);
    // The **outermost** stop inside the subtree, not the first one the tree
    // lists: a register row wraps the buttons it holds, and the row is where a
    // keyboard reaches the record — the buttons are what `Tab` finds next.
    FocusNode? target;
    var bestDepth = 1 << 30;
    for (final node in scope.traversalDescendants) {
      final context = node.context;
      if (context is! Element) continue;
      if (!node.canRequestFocus || node.skipTraversal) continue;
      if (!_isInside(context, element)) continue;
      final depth = _depthInside(context, element);
      if (depth < bestDepth) {
        bestDepth = depth;
        target = node;
      }
    }

    final found = target;
    expect(found, isNotNull, reason: 'nothing focusable inside $subtree');
    found!.requestFocus();
    await tester.pump();
    expect(now.isNothing, isFalse, reason: 'focus did not land inside $subtree');
    return now;
  }

  /// The stops inside [region], in the order `Tab` reaches them, up to the
  /// first stop that is outside it. This is how a Screen's own run in the tab
  /// order is read: where it starts, what it contains, and where it ends.
  Future<List<FocusStop>> within(Finder region, {int limit = 30}) async {
    final regionElement = tester.element(region.first);
    final stops = <FocusStop>[];
    for (var i = 0; i < limit; i++) {
      await forward();
      final focused = FocusManager.instance.primaryFocus?.context as Element?;
      if (focused == null || !_isInside(focused, regionElement)) return stops;
      stops.add(now);
    }
    return stops;
  }

  /// Whether every stop [tabs] `Tab` presses reach stays inside [region] — the
  /// dialog trap, stated as the promise rather than as the mechanism.
  Future<bool> staysInside(Finder region, {int tabs = 12}) async {
    final regionElement = tester.element(region.first);
    for (var i = 0; i < tabs; i++) {
      await forward();
      final focused = FocusManager.instance.primaryFocus?.context as Element?;
      if (focused == null) return false;
      var inside = false;
      focused.visitAncestorElements((ancestor) {
        if (identical(ancestor, regionElement)) {
          inside = true;
          return false;
        }
        return true;
      });
      if (!inside) return false;
    }
    return true;
  }

  /// Whether the drawn ring is on screen: `AppFocusRing`'s own 2px decoration in
  /// `focusRing`, read off the painted `DecoratedBox` rather than a marker.
  bool get ringIsVisible {
    final palette = AppColors.of(_paletteSurface);
    for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
      if (box.position == DecorationPosition.foreground &&
          AppFocusRing.isRing(box.decoration, palette.focusRing)) {
        return true;
      }
    }
    return false;
  }

  Element get _paletteSurface {
    final scaffold = find.byType(Scaffold);
    if (scaffold.evaluate().isNotEmpty) return tester.element(scaffold.first);
    return tester.element(find.byType(Overlay).first);
  }
}

/// The first `Text` inside [element], which is what a control is announced as.
/// Bounded, because a focused control's subtree is a button, a row or a tile —
/// never a page.
String? _firstText(Element element, [int depth = 0]) {
  if (depth > 8) return null;
  String? found;
  element.visitChildElements((child) {
    if (found != null) return;
    final widget = child.widget;
    if (widget is Text) {
      found = widget.data;
      return;
    }
    if (widget is RichText) {
      found = widget.text.toPlainText();
      return;
    }
    found = _firstText(child, depth + 1);
  });
  return found;
}

/// The nearest key above [element] that a test could have written — a
/// `ValueKey` or a `GlobalKey` a Screen names — skipping the framework's own
/// anonymous render keys, which say nothing about which control the reader is
/// on.
Key? _namedKey(Element element) {
  Key? fallback;
  Key? named;
  element.visitAncestorElements((ancestor) {
    final candidate = ancestor.widget.key;
    if (candidate == null) return true;
    if (candidate is GlobalKey) {
      fallback ??= candidate;
      return true;
    }
    named = candidate;
    return false;
  });
  return named ?? fallback;
}

/// How many levels [element] sits below [region] (0 when it is [region]).
int _depthInside(Element element, Element region) {
  var depth = 0;
  var found = identical(element, region);
  element.visitAncestorElements((ancestor) {
    depth++;
    if (identical(ancestor, region)) {
      found = true;
      return false;
    }
    return true;
  });
  return found ? depth : 1 << 30;
}

/// Whether [element] sits inside [region].
bool _isInside(Element element, Element region) {
  if (identical(element, region)) return true;
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (identical(ancestor, region)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// Whether the focus sits in a text field.
bool _isField(Element element) {
  if (element.widget is EditableText) return true;
  var field = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is EditableText) {
      field = true;
      return false;
    }
    return true;
  });
  return field;
}
