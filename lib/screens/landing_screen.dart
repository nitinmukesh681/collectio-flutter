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
    final isCompact = availableHeight < 720;
    final headingSize = isCompact ? 36.0 : 48.0;
    final bodySize = isCompact ? 16.0 : 18.0;
    final gridHeight = availableHeight * (isCompact ? 0.26 : 0.32);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, isCompact ? 24 : 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
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
                      ),
                      SizedBox(height: isCompact ? 20 : 32),
                      SizedBox(
                        height: gridHeight,
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
                      SizedBox(height: isCompact ? 24 : 40),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 16),
                        child: Column(
                          children: [
                            RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: headingSize,
                                  height: 1.1,
                                  color: const Color(0xFF1F2937),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                ),
                                children: [
                                  const TextSpan(text: 'Curate\neverything '),
                                  TextSpan(
                                    text: 'you\n',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'love',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            ),
                            SizedBox(height: isCompact ? 16 : 24),
                            Text(
                              'The elegant way to organize your digital world. Save, collaborate, and share curated collections that reflect your unique taste.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: bodySize,
                                color: const Color(0xFF4B5563),
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isCompact ? 24 : 40),
                      Container(
                        width: double.infinity,
                        height: 64,
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageCard(String imageUrl) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
