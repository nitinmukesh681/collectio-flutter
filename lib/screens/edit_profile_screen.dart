import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/username_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_fallback.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late String _originalUsername;

  File? _newAvatar;
  bool _clearAvatar = false;
  bool _isLoading = false;
  bool _usernameTaken = false;

  static const double _avatarSize = 108;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _originalUsername = UsernameUtils.normalize(auth.userEntity?.userName ?? '');
    _usernameController = TextEditingController(text: _originalUsername);
    _bioController = TextEditingController(text: auth.userEntity?.bio ?? '');
    _usernameController.addListener(() {
      if (_usernameTaken) setState(() => _usernameTaken = false);
    });
    _bioController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null || !mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressQuality: 85,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Photo',
            toolbarColor: AppColors.primaryPurple,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.primaryPurple,
            lockAspectRatio: true,
            hideBottomControls: false,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'Crop Profile Photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            embedInNavigationController: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
        ],
      );

      if (!mounted || croppedFile == null) return;
      setState(() {
        _newAvatar = File(croppedFile.path);
        _clearAvatar = false;
      });
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Could not update profile photo');
      }
    }
  }

  void _clearProfilePhoto() {
    setState(() {
      _newAvatar = null;
      _clearAvatar = true;
    });
  }

  bool _canClearProfilePhoto(String? avatarUrl) {
    if (_newAvatar != null) return true;
    if (_clearAvatar) return false;
    return avatarUrl != null && avatarUrl.trim().isNotEmpty;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _usernameTaken = false;
    });

    try {
      final auth = context.read<AuthProvider>();
      final newUsername = UsernameUtils.normalize(_usernameController.text);

      if (newUsername != UsernameUtils.normalize(_originalUsername)) {
        final available = await _firestoreService.isUsernameAvailable(
          newUsername,
          excludeUserId: auth.userId,
        );
        if (!available) {
          if (mounted) {
            setState(() {
              _usernameTaken = true;
              _isLoading = false;
            });
            _formKey.currentState!.validate();
          }
          return;
        }
      }

      final shouldClearAvatar = _clearAvatar && _newAvatar == null;
      String? avatarUrl = auth.userEntity?.avatarUrl;

      if (shouldClearAvatar) {
        await _firestoreService.clearUserAvatar(auth.userId);
        avatarUrl = null;
      } else if (_newAvatar != null) {
        final rawUrl = await _firestoreService.uploadImage(
          _newAvatar!,
          'avatars/${auth.userId}.jpg',
        );
        if (rawUrl == null) {
          if (mounted) {
            SnackBarUtils.showErrorSnackBar(context, 'Could not upload profile photo');
            setState(() => _isLoading = false);
          }
          return;
        }
        final separator = rawUrl.contains('?') ? '&' : '?';
        avatarUrl = '$rawUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}';
      }

      final updatedUser = shouldClearAvatar
          ? auth.userEntity!.copyWith(
              username: newUsername,
              bio: _bioController.text.trim(),
              clearAvatarUrl: true,
            )
          : auth.userEntity!.copyWith(
              username: newUsername,
              bio: _bioController.text.trim(),
              avatarUrl: avatarUrl,
            );

      final success = await auth.updateProfile(updatedUser);

      if (success && mounted) {
        SnackBarUtils.showSuccessSnackBar(context, 'Profile updated successfully');
        Navigator.pop(context, true);
      } else if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Error: ${auth.error ?? "Unknown error"}');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Error: ${e.toString()}');
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userEntity;
    final email = auth.firebaseUser?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Edit Profile',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _buildAvatarSection(user?.userName ?? 'U', user?.avatarUrl),
                  const SizedBox(height: 12),
                  _buildFormCard(),
                  const SizedBox(height: 12),
                  _buildEmailCard(auth, email),
                ],
              ),
            ),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection(String userName, String? avatarUrl) {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: SizedBox(
            width: _avatarSize + 8,
            height: _avatarSize + 8,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: SizedBox(
                      width: _avatarSize,
                      height: _avatarSize,
                      child: _buildAvatarImage(userName, avatarUrl),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 32,
                    height: 32,
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
                    child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_canClearProfilePhoto(avatarUrl)) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: _isLoading ? null : _clearProfilePhoto,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Remove photo',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatarImage(String userName, String? avatarUrl) {
    if (_clearAvatar) {
      return AvatarFallback(name: userName, size: _avatarSize);
    }

    if (_newAvatar != null) {
      return Image.file(_newAvatar!, fit: BoxFit.cover);
    }

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return AvatarFallback(name: userName, size: _avatarSize);
    }

    return CachedNetworkImage(
      key: ValueKey(avatarUrl),
      imageUrl: avatarUrl,
      cacheKey: avatarUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      errorWidget: (_, __, ___) => AvatarFallback(name: userName, size: _avatarSize),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel('Username'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _usernameController,
            style: _fieldTextStyle(),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            inputFormatters: UsernameUtils.inputFormatters,
            decoration: _fieldDecoration(
              hintText: 'Choose a username',
              prefixIcon: Icons.alternate_email_rounded,
            ),
            validator: (value) {
              if (_usernameTaken) {
                return 'This username is already taken';
              }
              return UsernameUtils.validate(value);
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildFieldLabel('Bio')),
              Text(
                '${_bioController.text.characters.length}/150',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _bioController,
            style: _fieldTextStyle(),
            maxLines: 4,
            maxLength: 150,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                const SizedBox.shrink(),
            decoration: _fieldDecoration(
              hintText: 'Tell people a little about yourself',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailCard(AuthProvider auth, String email) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACCOUNT',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.mail_outline_rounded, color: AppColors.textMuted, size: 20),
              ),
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
                            'Email',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (auth.isEmailVerified) _buildVerifiedBadge(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
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
          if (!auth.isEmailVerified) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  auth.resendEmailVerification();
                  SnackBarUtils.showSuccessSnackBar(context, 'Verification email sent');
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  'Resend verification email',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.surfaceMuted,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Save changes',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedBadge() {
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

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }

  TextStyle _fieldTextStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: 15,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w500,
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.plusJakartaSans(
        color: AppColors.textMuted,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: AppColors.textMuted, size: 20),
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1),
      ),
    );
  }
}
