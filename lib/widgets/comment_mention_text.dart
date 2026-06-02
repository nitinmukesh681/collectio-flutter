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
    final mentionStyle = style.copyWith(
      color: widget.mentionColor ?? AppColors.primary,
      fontWeight: FontWeight.w700,
    );

    final usernameToUserId = {
      for (final mention in widget.mentions)
        if (mention.username.isNotEmpty && mention.userId.isNotEmpty)
          mention.username.toLowerCase(): mention.userId,
    };

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in CommentMentions.mentionPattern.allMatches(widget.text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: widget.text.substring(lastIndex, match.start), style: style));
      }

      final username = match.group(1)!;
      final userId = usernameToUserId[username.toLowerCase()];
      final mentionText = match.group(0)!;

      if (userId != null) {
        final recognizer = TapGestureRecognizer()..onTap = () => widget.onMentionTap(userId);
        _recognizers.add(recognizer);
        spans.add(TextSpan(text: mentionText, style: mentionStyle, recognizer: recognizer));
      } else {
        spans.add(TextSpan(text: mentionText, style: mentionStyle));
      }

      lastIndex = match.end;
    }

    if (lastIndex < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(lastIndex), style: style));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}
