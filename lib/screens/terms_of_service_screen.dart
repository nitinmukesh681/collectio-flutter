import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        title: const Text('Terms of Service'),
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
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Terms of Service',
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
              Text(
                'Welcome to finds. Please read these Terms of Service ("Terms") carefully before using our mobile application and related curation services (collectively, the "Service"). By accessing or using finds, you agree to be bound by these Terms and our Privacy Policy.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Term Sections
              _buildSection(
                number: '1',
                title: 'Acceptance of Terms',
                icon: Icons.gavel_outlined,
                content:
                    'By creating an account or accessing the finds application, you confirm that you are at least 13 years of age (or the minimum legal age in your jurisdiction) and that you possess the legal authority to enter into these Terms. If you do not agree to all of these Terms, you are not authorized to use the Service.',
              ),
              _buildSection(
                number: '2',
                title: 'User Accounts & Security',
                icon: Icons.person_outline,
                content:
                    'To access certain features of finds, you must create a secure account. You agree to provide accurate, current, and complete information during registration. You are solely responsible for safeguarding your password and for all activities that occur under your account. You must notify us immediately of any unauthorized breach of security.',
              ),
              _buildSection(
                number: '3',
                title: 'User Content & Intellectual Property Rights',
                icon: Icons.folder_shared_outlined,
                content:
                    'You retain all of your ownership rights in the content, images, links, notes, and collections you curate and upload to the Service ("User Content"). By uploading User Content, you grant finds a worldwide, non-exclusive, royalty-free, fully paid-up license to host, store, cache, display, publish, and distribute such content solely for the purpose of operating, distributing, and providing the Service to you and other users (in accordance with your active privacy and sharing settings).',
              ),
              _buildSection(
                number: '4',
                title: 'Collaboration & Shared Collections',
                icon: Icons.people_outline,
                content:
                    'finds allows collaborative curation where multiple users contribute items to a single collection. If you join a collaborative collection, your contributions (items, comments, additions) may be visible to and manageable by other authorized members or the collection creator. You are responsible for ensuring that your contributions respect copyright, privacy, and community guidelines.',
              ),
              _buildSection(
                number: '5',
                title: 'Acceptable Use Guidelines',
                icon: Icons.block_outlined,
                content:
                    'You agree not to use finds to: (a) upload or transmit content that is illegal, defamatory, hateful, abusive, or infringes on any third-party intellectual property; (b) distribute unsolicited promotional material or spam; (c) attempt to reverse-engineer, exploit, or disrupt the Service\'s infrastructure; or (d) violate the privacy rights of other users or scrape their curated information.',
              ),
              _buildSection(
                number: '6',
                title: 'App-Only Data & No External Access Commitment',
                icon: Icons.lock_outline,
                content:
                    'We are fundamentally committed to protecting the integrity of your curated spaces. All data collected, created, or shared on finds is strictly processed within the boundary of the application\'s features. We guarantee that zero third-party entities, advertising networks, or external data brokers have access to your personal information or collections. Your curated collections are yours alone, utilized solely to drive your experience in finds.',
              ),
              _buildSection(
                number: '7',
                title: 'Account Suspension & Termination',
                icon: Icons.no_accounts_outlined,
                content:
                    'We reserve the right to suspend or terminate your account or access to the Service at our sole discretion, without notice or liability, if we determine that you have violated these Terms. You may delete your account at any time through the in-app Settings, which will trigger the permanent removal of your private personal data from our systems.',
              ),
              _buildSection(
                number: '8',
                title: 'Disclaimer of Warranties',
                icon: Icons.warning_amber_outlined,
                content:
                    'The Service is provided on an "AS IS" and "AS AVAILABLE" basis. finds disclaims all warranties of any kind, whether express or implied, including but not limited to the implied warranties of merchantability, fitness for a particular purpose, and non-infringement. We do not warrant that the Service will be uninterrupted, error-free, or entirely secure.',
              ),
              _buildSection(
                number: '9',
                title: 'Limitation of Liability',
                icon: Icons.shield_outlined,
                content:
                    'To the maximum extent permitted by applicable law, finds and its operators shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or any loss of profits or revenues, whether incurred directly or indirectly, or any loss of data, use, goodwill, or other intangible losses resulting from your use of or inability to use the Service.',
              ),
              _buildSection(
                number: '10',
                title: 'Governing Law & Changes to Terms',
                icon: Icons.g_translate_outlined,
                content:
                    'These Terms shall be governed by and construed in accordance with the laws of your jurisdiction, without regard to conflict of law principles. We reserve the right to modify these Terms at any time. We will notify you of any material changes by updating the date at the top of these Terms and, where appropriate, sending an in-app notice.',
              ),
              const SizedBox(height: 16),
              Divider(color: AppColors.divider.withOpacity(0.6)),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Thank you for curating with finds!',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
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
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
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
