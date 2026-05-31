import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_entity.dart';
import '../theme/app_theme.dart';
import 'avatar_fallback.dart';

class ProfileHeaderLayout extends StatelessWidget {
  final UserEntity user;
  final Widget? actionButton;
  final Widget statsRow;
  final bool showAvatarEditBadge;
  final VoidCallback? onAvatarTap;

  const ProfileHeaderLayout({
    super.key,
    required this.user,
    this.actionButton,
    required this.statsRow,
    this.showAvatarEditBadge = false,
    this.onAvatarTap,
  });

  static Widget buildOutlinedActionButton({
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
    bool filled = false,
  }) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: filled ? AppColors.primary : Colors.transparent,
          side: BorderSide(color: filled ? AppColors.primary : AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.textSecondary),
                ),
              )
            : Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: filled ? Colors.white : AppColors.textPrimary,
                ),
              ),
      ),
    );
  }

  static Widget buildStatsRow({
    required String collectionsCount,
    required String followersCount,
    required String followingCount,
    required VoidCallback onFollowersTap,
    required VoidCallback onFollowingTap,
  }) {
    Widget buildStatItem(String value, String label, [VoidCallback? onTap]) {
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );

      if (onTap != null) {
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: content,
        );
      }
      return content;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        buildStatItem(collectionsCount, 'collections'),
        Container(width: 1, height: 24, color: AppColors.divider),
        buildStatItem(followersCount, 'followers', onFollowersTap),
        Container(width: 1, height: 24, color: AppColors.divider),
        buildStatItem(followingCount, 'following', onFollowingTap),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            children: [
              ClipOval(
                child: (user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: user.avatarUrl!.trim(),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorWidget: (context, _, __) => AvatarFallback(name: user.displayName.isNotEmpty ? user.displayName : user.username, size: 96),
                      )
                    : AvatarFallback(name: user.displayName.isNotEmpty ? user.displayName : user.username, size: 96),
              ),
              if (showAvatarEditBadge)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Name & Username
        Text(
          user.displayName.isNotEmpty ? user.displayName : '@${user.username}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        if (user.displayName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '@${user.username}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        // Bio
        if (user.bio != null && user.bio!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              user.bio!.trim(),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.collectionDescription,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        // Stats
        statsRow,
        if (actionButton != null) ...[
          const SizedBox(height: 20),
          actionButton!,
        ],
      ],
    );
  }
}
