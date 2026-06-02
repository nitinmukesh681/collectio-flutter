import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_entity.dart';
import '../theme/app_theme.dart';
import 'avatar_fallback.dart';

/// Centered profile header: avatar, identity, bio, stats, action button.
class ProfileHeaderLayout extends StatelessWidget {
  // Reference-matched profile chrome
  static const Color hairline = AppColors.divider;
  static const Color statLabelColor = AppColors.textMuted;

  static const double avatarSize = 100;
  static const double spacingAvatarToName = 28;
  static const double spacingNameToUsername = 4;
  static const double spacingUsernameToBio = 18;
  static const double spacingBioToStats = 28;
  static const double statsBandPadding = 12;
  static const double statsBandPaddingLarge = 16;
  static const double spacingStatsToButton = 12;

  final UserEntity user;
  final Widget? actionButton;
  final Widget statsRow;
  final bool showAvatarEditBadge;
  final bool emphasizeStats;
  final VoidCallback? onAvatarTap;

  const ProfileHeaderLayout({
    super.key,
    required this.user,
    required this.statsRow,
    this.actionButton,
    this.showAvatarEditBadge = false,
    this.emphasizeStats = false,
    this.onAvatarTap,
  });

  static Widget hairlineDivider() {
    return Container(
      width: double.infinity,
      height: 1,
      color: hairline,
    );
  }

  /// Pill-shaped outlined action button (Edit Profile / Follow).
  static Widget buildOutlinedActionButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool filled = false,
    bool expandWidth = false,
    bool compact = false,
  }) {
    final button = OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: filled ? AppColors.primary : Colors.white,
        foregroundColor: filled ? Colors.white : AppColors.textPrimary,
        side: BorderSide(
          color: filled ? AppColors.primary : hairline,
        ),
        padding: EdgeInsets.symmetric(
          vertical: compact ? 8 : 14,
          horizontal: compact ? 16 : 24,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: compact ? 16 : 20,
              height: compact ? 16 : 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: filled ? Colors.white : AppColors.primary,
              ),
            )
          : Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : 15,
                letterSpacing: compact ? 0.5 : 0,
              ),
            ),
    );

    if (expandWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return SizedBox(width: compact ? 150 : 220, child: button);
  }

  /// Follow / following control for other-user profile top bars.
  static Widget buildProfileFollowButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool filled = false,
  }) {
    final textColor = filled ? Colors.white : AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled ? AppColors.primary : hairline,
            ),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: textColor,
                    ),
                  )
                : Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.5,
                      height: 1.0,
                      color: textColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAvatarSection(),
        const SizedBox(height: spacingAvatarToName),
        _buildDisplayName(),
        const SizedBox(height: spacingNameToUsername),
        _buildUsername(),
        if (_hasBio) ...[
          const SizedBox(height: spacingUsernameToBio),
          _buildBioSection(),
        ],
        const SizedBox(height: spacingBioToStats),
        hairlineDivider(),
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: emphasizeStats ? statsBandPaddingLarge : statsBandPadding,
          ),
          child: statsRow,
        ),
        if (actionButton != null) ...[
          hairlineDivider(),
          const SizedBox(height: spacingStatsToButton),
          Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: actionButton!,
          ),
        ],
      ],
    );
  }

  bool get _hasBio {
    final bio = user.bio?.trim();
    return bio != null && bio.isNotEmpty;
  }

  Widget _buildDisplayName() {
    return Text(
      user.displayName.isNotEmpty ? user.displayName : user.userName,
      textAlign: TextAlign.center,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.1,
        letterSpacing: -0.4,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildUsername() {
    return Text(
      '@${user.userName}',
      textAlign: TextAlign.center,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildBioSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        user.bio!.trim(),
        textAlign: TextAlign.center,
        style: AppTextStyles.collectionDescription(
          fontSize: 14,
          height: 1.55,
        ).copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final avatar = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: _buildAvatar(user),
        ),
      ),
    );

    if (!showAvatarEditBadge) return avatar;

    return GestureDetector(
      onTap: onAvatarTap,
      child: SizedBox(
        width: avatarSize + 8,
        height: avatarSize + 8,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            avatar,
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildStat(
    String count,
    String label, {
    VoidCallback? onTap,
    double countFontSize = 22,
    double labelFontSize = 10,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            count,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textPrimary,
              fontSize: countFontSize,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: statLabelColor,
              fontSize: labelFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  static Widget buildStatsRow({
    required String collectionsCount,
    required String followersCount,
    required String followingCount,
    VoidCallback? onFollowersTap,
    VoidCallback? onFollowingTap,
    double countFontSize = 22,
    double labelFontSize = 10,
  }) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: buildStat(
                collectionsCount,
                'COLLECTIONS',
                countFontSize: countFontSize,
                labelFontSize: labelFontSize,
              ),
            ),
          ),
          _statsVerticalDivider(),
          Expanded(
            child: Center(
              child: buildStat(
                followersCount,
                'FOLLOWERS',
                onTap: onFollowersTap,
                countFontSize: countFontSize,
                labelFontSize: labelFontSize,
              ),
            ),
          ),
          _statsVerticalDivider(),
          Expanded(
            child: Center(
              child: buildStat(
                followingCount,
                'FOLLOWING',
                onTap: onFollowingTap,
                countFontSize: countFontSize,
                labelFontSize: labelFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _statsVerticalDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: hairline,
    );
  }

  static Widget _buildAvatar(UserEntity user) {
    Widget fallback() => AvatarFallback(name: user.userName, size: avatarSize);

    if (user.avatarUrl == null || user.avatarUrl!.isEmpty) {
      return fallback();
    }

    if (user.avatarUrl!.trim().startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(user.avatarUrl!.trim()).getDownloadURL(),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null || url.isEmpty) return fallback();
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => fallback(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: user.avatarUrl!.trim(),
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => fallback(),
    );
  }
}
