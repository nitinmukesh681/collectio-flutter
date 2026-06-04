import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final email = auth.firebaseUser?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            'Manage your account, preferences, and privacy.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionCard(
            label: 'ACCOUNT',
            children: [
              _SettingsNavRow(
                icon: Icons.lock_outline_rounded,
                title: 'Change Password',
                subtitle: 'Send a reset link to your email',
                onTap: () => _showChangePasswordDialog(context),
              ),
              _SettingsDivider(),
              _SettingsInfoRow(
                icon: Icons.mail_outline_rounded,
                title: 'Email',
                subtitle: email,
                trailing: auth.isEmailVerified
                    ? _VerifiedBadge()
                    : TextButton(
                        onPressed: () {
                          auth.resendEmailVerification();
                          SnackBarUtils.showSuccessSnackBar(
                            context,
                            'Verification email sent',
                          );
                        },
                        child: Text(
                          'Verify',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            label: 'APPEARANCE',
            children: [
              _SettingsSwitchRow(
                icon: Icons.dark_mode_outlined,
                title: 'Dark Mode',
                subtitle: 'Use dark theme',
                value: _darkMode,
                onChanged: (value) {
                  setState(() => _darkMode = value);
                  // TODO: Implement theme switching
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            label: 'NOTIFICATIONS',
            children: [
              _SettingsSwitchRow(
                icon: Icons.notifications_outlined,
                title: 'Push Notifications',
                subtitle: 'Receive push notifications',
                value: _notificationsEnabled,
                onChanged: (value) => setState(() => _notificationsEnabled = value),
              ),
              _SettingsDivider(),
              _SettingsSwitchRow(
                icon: Icons.mail_outline_rounded,
                title: 'Email Notifications',
                subtitle: 'Receive email updates',
                value: _emailNotifications,
                onChanged: (value) => setState(() => _emailNotifications = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            label: 'PRIVACY',
            children: [
              _SettingsNavRow(
                icon: Icons.shield_outlined,
                title: 'Privacy Policy',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                  );
                },
              ),
              _SettingsDivider(),
              _SettingsNavRow(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            label: 'ABOUT',
            children: [
              _SettingsInfoRow(
                icon: Icons.info_outline_rounded,
                title: 'App Version',
                subtitle: '1.0.5 (8)',
              ),
              _SettingsDivider(),
              _SettingsNavRow(
                icon: Icons.star_outline_rounded,
                title: 'Rate App',
                subtitle: 'Enjoying finds? Leave a review',
                onTap: () {
                  // Open app store
                },
              ),
              _SettingsDivider(),
              _SettingsNavRow(
                icon: Icons.share_outlined,
                title: 'Share App',
                subtitle: 'Invite friends to discover with you',
                onTap: () {
                  // Share app
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionCard(
            label: 'ACCOUNT ACTIONS',
            children: [
              _SettingsNavRow(
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                iconColor: const Color(0xFFD97706),
                iconBackground: const Color(0xFFFFF7ED),
                onTap: () => _showSignOutDialog(context, auth),
              ),
              _SettingsDivider(),
              _SettingsNavRow(
                icon: Icons.delete_forever_outlined,
                title: 'Delete Account',
                subtitle: 'Permanently remove your data',
                iconColor: AppColors.heartSalmon,
                iconBackground: const Color(0xFFFEF2F2),
                titleColor: AppColors.heartSalmon,
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String label,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Change Password',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'A password reset email will be sent to your registered email address.',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final auth = context.read<AuthProvider>();
              auth.sendPasswordReset(auth.firebaseUser?.email ?? '');
              Navigator.pop(context);
              SnackBarUtils.showSuccessSnackBar(context, 'Password reset email sent');
            },
            child: const Text('Send Email'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Sign Out',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
            onPressed: () {
              auth.signOut();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final passwordController = TextEditingController();
    var isDeleting = false;
    var needsReauth = false;

    showDialog(
      context: context,
      barrierDismissible: !isDeleting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final usesPassword = auth.usesEmailPassword;
          final usesGoogle = auth.usesGoogleSignIn;

          Future<void> performDelete({String? password, bool withGoogle = false}) async {
            setDialogState(() => isDeleting = true);
            auth.clearError();

            final success = await auth.deleteAccount(
              password: password,
              reauthenticateWithGoogle: withGoogle,
            );

            if (!dialogContext.mounted) return;

            if (success) {
              Navigator.pop(dialogContext);
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                SnackBarUtils.showSuccessSnackBar(
                  context,
                  'Your account has been deleted',
                );
              }
              return;
            }

            setDialogState(() {
              isDeleting = false;
              needsReauth = auth.error?.contains('confirm your password') ?? false;
            });
          }

          return AlertDialog(
            title: Text(
              'Delete Account',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppColors.heartSalmon,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This action cannot be undone. All your data will be permanently deleted.',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (usesPassword || needsReauth) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    enabled: !isDeleting,
                    decoration: InputDecoration(
                      labelText: 'Confirm your password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                if (auth.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    auth.error!,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.heartSalmon,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton(
                onPressed: isDeleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.heartSalmon),
                onPressed: isDeleting
                    ? null
                    : () async {
                        if (usesPassword || needsReauth) {
                          final password = passwordController.text.trim();
                          if (password.isEmpty) {
                            setDialogState(() {
                              auth.clearError();
                            });
                            SnackBarUtils.showErrorSnackBar(
                              dialogContext,
                              'Please enter your password to confirm.',
                            );
                            return;
                          }
                          await performDelete(password: password);
                          return;
                        }

                        if (usesGoogle) {
                          await performDelete(withGoogle: true);
                          return;
                        }

                        await performDelete();
                      },
                child: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(usesGoogle && !usesPassword ? 'Confirm with Google' : 'Delete'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(passwordController.dispose);
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: AppColors.divider),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text(
            'Verified',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.green.shade700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsIconBox extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final Color? backgroundColor;

  const _SettingsIconBox({
    required this.icon,
    this.iconColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        color: iconColor ?? AppColors.textMuted,
        size: 20,
      ),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? iconBackground;
  final Color? titleColor;

  const _SettingsNavRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor,
    this.iconBackground,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _SettingsIconBox(
                icon: icon,
                iconColor: iconColor,
                backgroundColor: iconBackground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SettingsInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _SettingsIconBox(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _SettingsIconBox(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
