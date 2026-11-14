/// `NoticeText`: a Bloc-held message, resolved for the reader and rendered
/// (ADR-0062).
///
/// **Why a widget and not a bare `Text`.** A Bloc has no `BuildContext`, so the
/// copy it holds travels as a code (`notices.dart`, `BlocNotice.sessionEnded`).
/// The Screen that renders it is the only place a language exists — so the
/// render itself resolves the code. Every surface that prints a Bloc-held
/// message does it through this widget, which is what makes "no `notice:` code
/// reaches a `Text`" a property of the tree rather than a habit.
///
/// A message that is already prose (a server's own sentence,
/// `PeopleApiException.message`) passes through [noticeText] untouched, so this
/// is a drop-in for `Text` everywhere, not only where a code is expected.
library;

import 'package:flutter/material.dart';

import '../l10n/notices.dart';

class NoticeText extends StatelessWidget {
  const NoticeText(
    this.message, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  /// The Bloc-held code or the prose, exactly as the state carries it.
  final String message;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Text(
        noticeTextFor(context, message),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        semanticsLabel: semanticsLabel,
      );
}
