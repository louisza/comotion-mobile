// lib/services/cloud_config.dart
/// Configuration for Comotion cloud API connection.
class CloudConfig {
  /// Base URL of the Comotion web API.
  /// Set to your Railway deployment URL in production.
  static String apiBaseUrl = 'http://localhost:8000';

  /// JWT auth token (set after Google sign-in).
  static String? authToken;

  /// Whether cloud upload is configured and ready.
  static bool get isConfigured => apiBaseUrl.isNotEmpty;
}
