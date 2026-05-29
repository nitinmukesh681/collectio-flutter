import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom;
    final textScale = mediaQuery.textScaler.scale(1);
    final needsScroll = textScale > 1.2 || availableHeight < 640;

    Widget page = LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final isCompact = height < 700;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: height * 0.02),
            _buildLogo(),
            SizedBox(height: height * 0.015),
            Expanded(
              flex: isCompact ? 36 : 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildImageGrid(),
              ),
            ),
            SizedBox(height: height * 0.018),
            Expanded(
              flex: isCompact ? 30 : 28,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 24 : 36),
                child: Center(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: _buildTypography(isCompact: isCompact),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, height * 0.012, 24, height * 0.022),
              child: _buildCta(context, height: isCompact ? 56 : 60),
            ),
          ],
        );
      },
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: needsScroll
            ? SingleChildScrollView(
                child: SizedBox(
                  height: availableHeight,
                  child: page,
                ),
              )
            : page,
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          'finds',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  Widget _buildImageGrid() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: _buildImageCard(
                  'https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?w=500&q=80',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 4,
                child: _buildImageCard(
                  'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=500&q=80',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 4,
                child: _buildImageCard(
                  'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?w=500&q=80',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 5,
                child: _buildImageCard(
                  'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=500&q=80',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypography({required bool isCompact}) {
    final headingSize = isCompact ? 34.0 : 44.0;
    final bodySize = isCompact ? 15.0 : 17.0;

    final baseStyle = GoogleFonts.plusJakartaSans(
      fontSize: headingSize,
      height: 1.08,
      color: const Color(0xFF1F2937),
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
    );

    final accentStyle = baseStyle.copyWith(
      fontStyle: FontStyle.italic,
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Curate', style: baseStyle, textAlign: TextAlign.center),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'everything ', style: baseStyle),
                    TextSpan(text: 'you', style: accentStyle),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'love', style: accentStyle),
                    TextSpan(text: '.', style: baseStyle),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SizedBox(height: isCompact ? 12 : 16),
        Text(
          'The elegant way to organize your digital world. Save, collaborate, and share curated collections that reflect your unique taste.',
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: bodySize,
            color: const Color(0xFF4B5563),
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildCta(BuildContext context, {required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Text(
              'Start Curating',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageCard(String imageUrl) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (context, url) => Container(
            color: AppColors.surfaceMuted,
          ),
          errorWidget: (context, url, error) =>
              const Icon(Icons.image_outlined, color: Colors.grey),
        ),
      ),
    );
  }
}
