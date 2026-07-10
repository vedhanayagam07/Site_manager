import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _voiceLanguage = 'ta-IN';
  double _voiceSpeed = 1.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _voiceLanguage = prefs.getString('voice_language') ?? 'ta-IN';
        _voiceSpeed = prefs.getDouble('voice_speed') ?? 1.0;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateLanguage(String lang) async {
    setState(() => _voiceLanguage = lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_language', lang);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang == 'ta-IN' 
                ? 'விருப்ப மொழி தமிழுக்கு மாற்றப்பட்டது' 
                : 'Language updated to English'
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _updateSpeed(double speed) async {
    setState(() => _voiceSpeed = speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('voice_speed', speed);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // SECTION: APPEARANCE
                _buildSectionHeader('Appearance'),
                Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.palette_outlined, color: AppColors.roseGold),
                          title: const Text('Theme Mode'),
                          subtitle: Text(
                            themeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          trailing: Switch(
                            value: themeMode == ThemeMode.dark,
                            activeColor: AppColors.roseGold,
                            onChanged: (value) {
                              ref.read(appThemeProvider.notifier).setThemeMode(
                                    value ? ThemeMode.dark : ThemeMode.light,
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // SECTION: VOICE ASSISTANT OPTIONS
                _buildSectionHeader('Voice Assistant'),
                Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Speech Recognition Language',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('தமிழ் (Tamil)'),
                                ),
                                selected: _voiceLanguage == 'ta-IN',
                                selectedColor: AppColors.roseGold.withValues(alpha: 0.2),
                                labelStyle: TextStyle(
                                  color: _voiceLanguage == 'ta-IN' ? AppColors.roseGold : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                ),
                                side: BorderSide(
                                  color: _voiceLanguage == 'ta-IN' ? AppColors.roseGold : Colors.white12,
                                ),
                                onSelected: (val) {
                                  if (val) _updateLanguage('ta-IN');
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                  child: Text('English (US)'),
                                ),
                                selected: _voiceLanguage == 'en-US',
                                selectedColor: AppColors.roseGold.withValues(alpha: 0.2),
                                labelStyle: TextStyle(
                                  color: _voiceLanguage == 'en-US' ? AppColors.roseGold : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                ),
                                side: BorderSide(
                                  color: _voiceLanguage == 'en-US' ? AppColors.roseGold : Colors.white12,
                                ),
                                onSelected: (val) {
                                  if (val) _updateLanguage('en-US');
                                },
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32, color: Colors.white10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Voice Feedback Speed',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${_voiceSpeed.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                color: AppColors.roseGold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _voiceSpeed,
                          min: 0.5,
                          max: 1.5,
                          divisions: 10,
                          activeColor: AppColors.roseGold,
                          inactiveColor: Colors.white10,
                          onChanged: _updateSpeed,
                        ),
                      ],
                    ),
                  ),
                ),

                // SECTION: DIAGNOSTICS & SYSTEM
                _buildSectionHeader('Diagnostics'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        const ListTile(
                          leading: Icon(Icons.cloud_done_outlined, color: AppColors.success),
                          title: Text('Database Connection'),
                          trailing: Text(
                            'Online',
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        ListTile(
                          leading: const Icon(Icons.info_outline, color: AppColors.textSecondary),
                          title: const Text('App Version'),
                          trailing: Text(
                            '1.0.0 (Build 1)',
                           style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.roseGold,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
