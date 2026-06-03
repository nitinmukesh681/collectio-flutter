import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../utils/comment_mentions.dart';

class CommentMentionText extends StatefulWidget {
  final String text;
  final List<CommentMention> mentions;
  final void Function(String userId) onMentionTap;
  final TextStyle? style;
  final Color? mentionColor;

  const CommentMentionText({
    super.key,
    required this.text,
    required this.mentions,
    required this.onMentionTap,
    this.style,
    this.mentionColor,
  });

  @override
  State<CommentMentionText> createState() => _CommentMentionTextState();
}

class _CommentMentionTextState extends State<CommentMentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final style = widget.style ??
        GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.45,
        );

    final span = CommentMentions.buildMentionTextSpan(
      text: widget.text,
      mentions: widget.mentions,
      onMentionTap: widget.onMentionTap,
      baseStyle: style,
      mentionColor: widget.mentionColor ?? AppColors.primary,
      recognizers: _recognizers,
    );

    return RichText(text: span);
  }
}
