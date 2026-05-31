import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'username_utils.dart';

class CommentMention {
  final String userId;
  final String username;

  const CommentMention({
    required this.userId,
    required this.username,
  });

  factory CommentMention.fromMap(Map<String, dynamic> map) {
    return CommentMention(
      userId: map['userId'] as String? ?? '',
      username: UsernameUtils.normalize((map['username'] as String?) ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
    };
  }
}

class CommentMentions {
  CommentMentions._();

  static final RegExp mentionPattern = RegExp(r'@([a-zA-Z0-9_]+)');

  static List<String> extractUsernames(String text) {
    final usernames = <String>{};
    for (final match in mentionPattern.allMatches(text)) {
      final username = match.group(1)?.trim();
      if (username != null && username.isNotEmpty) {
        usernames.add(UsernameUtils.normalize(username));
      }
    }
    return usernames.toList();
  }

  static String? activeMentionQuery(String text, int cursorPosition) {
    if (cursorPosition < 0 || cursorPosition > text.length) return null;

    final beforeCursor = text.substring(0, cursorPosition);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex == -1) return null;

    final query = beforeCursor.substring(atIndex + 1);
    if (query.contains(' ') || query.contains('\n')) return null;
    if (!RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(query)) return null;
    return query;
  }

  static int? activeMentionStartIndex(String text, int cursorPosition) {
    if (activeMentionQuery(text, cursorPosition) == null) return null;

    final beforeCursor = text.substring(0, cursorPosition);
    return beforeCursor.lastIndexOf('@');
  }

  static TextSpan buildComposerTextSpan({
    required String text,
    required List<CommentMention> mentions,
    required TextStyle baseStyle,
    TextStyle? mentionStyle,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final styledMention = mentionStyle ??
        baseStyle.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        );

    final confirmedUsernames = {
      for (final mention in mentions)
        if (mention.username.isNotEmpty) mention.username.toLowerCase(),
    };

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in mentionPattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: baseStyle));
      }

      final username = match.group(1)!;
      final mentionText = match.group(0)!;
      final isConfirmed = confirmedUsernames.contains(username.toLowerCase());
      spans.add(
        TextSpan(
          text: mentionText,
          style: isConfirmed ? styledMention : baseStyle,
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: baseStyle));
    }

    return TextSpan(children: spans);
  }

  static TextSpan buildMentionTextSpan({
    required String text,
    required List<CommentMention> mentions,
    required void Function(String userId) onMentionTap,
    TextStyle? baseStyle,
  }) {
    final style = baseStyle ??
        GoogleFonts.plusJakartaSans(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.45,
        );
    final mentionStyle = style.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );

    final usernameToUserId = {
      for (final mention in mentions)
        if (mention.username.isNotEmpty && mention.userId.isNotEmpty)
          mention.username.toLowerCase(): mention.userId,
    };

    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in mentionPattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: style));
      }

      final username = match.group(1)!;
      final userId = usernameToUserId[username.toLowerCase()];
      final mentionText = match.group(0)!;

      if (userId != null) {
        spans.add(
          TextSpan(
            text: mentionText,
            style: mentionStyle,
            recognizer: TapGestureRecognizer()..onTap = () => onMentionTap(userId),
          ),
        );
      } else {
        spans.add(TextSpan(text: mentionText, style: mentionStyle));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: style));
    }

    return TextSpan(children: spans);
  }
}
