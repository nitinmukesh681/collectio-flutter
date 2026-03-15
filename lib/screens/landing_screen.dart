import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Modern Logo
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogoIcon(),
                const SizedBox(width: 10),
                Text(
                  'finds',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E),
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
            
            const Spacer(flex: 1),
            
            // Refined Masonry-style Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.42,
                child: Row(
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
                          const SizedBox(height: 16),
                          Expanded(
                            flex: 4,
                            child: _buildImageCard(
                              'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=500&q=80',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            flex: 4,
                            child: _buildImageCard(
                              'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?w=500&q=80',
                            ),
                          ),
                          const SizedBox(height: 16),
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
                ),
              ),
            ),
            
            const Spacer(flex: 1),
            
            // High-Impact Typography
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 42,
                        height: 1.2, // Increased line height to prevent cropping
                        color: const Color(0xFF1A1A2E),
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        const TextSpan(text: 'curate\n'),
                        TextSpan(
                          text: 'everything',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [AppColors.primaryPurple, Color(0xFFA78BFA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(const Rect.fromLTWH(0.0, 0.0, 250.0, 70.0)),
                          ),
                        ),
                        const TextSpan(text: '\nyou love.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your personal collection of places,\nmedia, and hidden gems.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(flex: 1),
            
            // Modern CTA Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                width: double.infinity,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryPurple.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryPurple, Color(0xFF9D84FF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
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
                    borderRadius: BorderRadius.circular(32),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Start Collecting',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
        ),
        const Icon(Icons.auto_awesome_motion_rounded, color: AppColors.primaryPurple, size: 24),
      ],
    );
  }

  Widget _buildImageCard(String imageUrl) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (context, url) => Container(
            color: const Color(0xFFF1F5F9),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryPurple),
              ),
            ),
          ),
          errorWidget: (context, url, error) => const Icon(Icons.image_outlined, color: Colors.grey),
        ),
      ),
    );
  }
}
