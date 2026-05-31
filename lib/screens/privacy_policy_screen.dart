import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Colors.teal,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Privacy Policy',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Last Updated: May 31, 2026',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Special Core Commitment Panel
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF134E5E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Our Privacy Guarantee',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We believe your curations are personal. finds operates with a strict app-only data model. We guarantee that your personal data, links, notes, and collections are utilized solely to power your in-app experience. We NEVER sell, share, or disclose your information to advertisers, data brokers, or any third party.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.92),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Policy Sections
              _buildSection(
                number: '1',
                title: 'Introduction & Core Values',
                icon: Icons.info_outline,
                content:
                    'At finds, we are committed to safeguarding your privacy. This Privacy Policy details how we collect, store, and process your data. Unlike modern commercial networks, finds is built with an editorial, curated approach where you control exactly who sees your digital collections.',
              ),
              _buildSection(
                number: '2',
                title: 'Information We Collect',
                icon: Icons.save_alt_outlined,
                content:
                    'To deliver the best possible curating experience, finds collects:\n'
                    '• Account Credentials: Secure authenticated details (email address, username, profile picture representation, encrypted password metadata) managed securely by Firebase Authentication.\n'
                    '• Curated Collections: Titles, descriptions, category groupings, items, uploaded images, notes, and imported links that you explicitly save.\n'
                    '• Social & Collaborative Data: Follow relationships, collection likes, comment histories, and joint contributions in shared collaborative spaces.',
              ),
              _buildSection(
                number: '3',
                title: 'How We Use Your Information',
                icon: Icons.settings_accessibility_outlined,
                content:
                    'Your data is processed strictly within the application boundaries to:\n'
                    '• Deliver core features (e.g., rendering your collections, loading content cards, managing collaboration edits).\n'
                    '• Build the Explore feed (showing collections designated as public by creators).\n'
                    '• Send necessary alerts (push or email notifications related to activities like collaborative edits, comments, or follow events, based on your settings).',
              ),
              _buildSection(
                number: '4',
                title: 'Strict Commitment Against Third-Party Access',
                icon: Icons.phonelink_lock_outlined,
                content:
                    'We make a binding commitment that your data is for our application use only. Specifically:\n'
                    '• No Advertising Networks: We do not display third-party advertisements or integrate tracking SDKs from commercial advertisers.\n'
                    '• No Data Sales or Trades: We never rent, sell, trade, or distribute your email or curated items to marketing lists, data brokers, or target profile agencies.\n'
                    '• Minimal Subprocessors: We use trusted infrastructure providers (like Google Firebase / Cloud Platform) purely to host data, enforce cloud firewalls, and deliver your assets.',
              ),
              _buildSection(
                number: '5',
                title: 'Data Control & Deletion Rights',
                icon: Icons.delete_outline,
                content:
                    'You retain complete control of your digital curations. You can edit or delete individual collection items, categories, or entire collections at any time. If you decide to close your account, tapping "Delete Account" in settings triggers a comprehensive deletion routine that permanently removes your profile information and cloud database entries from finds server instances.',
              ),
              _buildSection(
                number: '6',
                title: 'Data Security & Storage Standards',
                icon: Icons.lock_outline,
                content:
                    'We employ rigorous security protocols to protect your personal information. Database layers are fully isolated behind Firebase Security Rules, validating that only authorized users can read or write content. All data transmitted between the finds mobile app and our backend is encrypted using Transport Layer Security (TLS) and stored with industry-standard server encryption at rest.',
              ),
              _buildSection(
                number: '7',
                title: 'Children\'s Privacy',
                icon: Icons.child_care_outlined,
                content:
                    'finds is not designed or intended for children under the age of 13. We do not knowingly collect personal data from anyone under this age threshold. If we discover that a child under 13 has created an account, we will immediately execute account deletion protocols.',
              ),
              _buildSection(
                number: '8',
                title: 'Updates to this Privacy Policy',
                icon: Icons.update_outlined,
                content:
                    'We may update this Privacy Policy from time to time as features expand. Any revisions will be accompanied by an updated "Last Updated" timestamp at the top of the policy page. We recommend reviewing this document periodically to stay informed about our data handling practices.',
              ),
              _buildSection(
                number: '9',
                title: 'Contact Information',
                icon: Icons.mail_outline,
                content:
                    'If you have any questions or security concerns regarding this Privacy Policy, your account, or finds data practices, please contact our support team through the official support avenues in the application.',
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.divider.withOpacity(0.6)),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Your privacy is our priority.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal[700],
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String number,
    required String title,
    required IconData icon,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.teal[700],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$number. $title',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 48.0),
            child: Text(
              content,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
