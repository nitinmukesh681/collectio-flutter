import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/comment_discussion_section.dart';

class CommentThreadScreen extends StatelessWidget {
  final String collectionId;
  final String currentUserId;
  final String rootCommentId;

  const CommentThreadScreen({
    super.key,
    required this.collectionId,
    required this.currentUserId,
    required this.rootCommentId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Thread',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: CommentDiscussionSection(
        collectionId: collectionId,
        currentUserId: currentUserId,
        threadRootId: rootCommentId,
        maxVisibleDepth: 999,
        collapseRepliesByDefault: false,
        showDiscussionHeader: false,
        showTopLevelComposer: true,
      ),
    );
  }
}
