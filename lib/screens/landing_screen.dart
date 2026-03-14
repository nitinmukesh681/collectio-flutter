import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF), // Very light purple/white
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Header Logo
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bubble_chart, color: AppColors.primaryPurple, size: 28),
                const SizedBox(width: 8),
                const Text(
                  'finds',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E), // Dark Navy
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Image Masonry Grid (Expanded to fill available space)
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Column 1
                    Expanded(
                      child: Column(
                        children: [
                          // Ocean Image (Tall)
                          Expanded(
                            flex: 3,
                            child: _buildImageCard(
                              'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500&q=80',
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Avocado Toast (Short)
                          Expanded(
                            flex: 2,
                            child: _buildImageCard(
                              'https://images.unsplash.com/photo-1588137372308-15f75323a675?w=500&q=80',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Column 2
                    Expanded(
                      child: Column(
                        children: [
                          // Books (Square/Short)
                          Expanded(
                            flex: 2,
                            child: _buildImageCard(
                              'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=500&q=80',
                              color: const Color(0xFFEBCBB1), // Beige background placeholder if needed
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Vintage Camera (Tall)
                          Expanded(
                            flex: 3,
                            child: _buildImageCard(
                              'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=500&q=80',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Text Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1.1,
                        color: Color(0xFF1A1A2E),
                        fontFamily: '.SF Pro Display', // System font attempt
                        fontWeight: FontWeight.w800,
                      ),
                      children: [
                        const TextSpan(text: 'curate\n'),
                        WidgetSpan(
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF836FFF), Color(0xFFFF69B4)], // Purple to Pink
                            ).createShader(bounds),
                            child: const Text(
                              'everything',
                              style: TextStyle(
                                fontSize: 36,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                color: Colors.white, // Required for ShaderMask
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: '\nyou love.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your personal collection of places,\nmedia, and hidden gems.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // CTA Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF836FFF).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  gradient: const LinearGradient(
                    colors: [Color(0xFF836FFF), Color(0xFF9D84FF)],
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
                    borderRadius: BorderRadius.circular(30),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Start Collecting',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            const Spacer(),
            
            // Page Indicator (Dots)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDot(false),
                _buildDot(true),
                _buildDot(false),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCard(String imageUrl, {Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
          placeholder: (context, url) => Container(color: const Color(0xFFF1F5F9)),
          errorWidget: (context, url, error) => const Icon(Icons.error),
        ),
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? const Color(0xFF836FFF) : const Color(0xFFE5E7EB),
      ),
    );
  }
}
