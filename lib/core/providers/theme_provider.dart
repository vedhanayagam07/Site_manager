import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_provider.g.dart';

const _kThemeModeKey = 'theme_mode';

@riverpod
Future<SharedPreferences> sharedPreferences(
  Ref ref,
) async {
  return SharedPreferences.getInstance();
}

@riverpod
class AppThemeNotifier extends _$AppThemeNotifier {
  @override
  ThemeMode build() {
    final prefsAsyncValue = ref.watch(sharedPreferencesProvider);
    return prefsAsyncValue.maybeWhen(
      data: (prefs) {
        final savedMode = prefs.getString(_kThemeModeKey);
        if (savedMode == ThemeMode.light.name) return ThemeMode.light;
        if (savedMode == ThemeMode.dark.name) return ThemeMode.dark;
        return ThemeMode.dark;
      },
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;

    final prefs = await ref.read(
      sharedPreferencesProvider.future,
    );

    await prefs.setString(
      _kThemeModeKey,
      mode.name,
    );
  }

  void toggleTheme() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(state);
  }
}