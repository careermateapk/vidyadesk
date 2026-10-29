// Values put in at build time by the GitHub build (from firebase-app.json).
// When they are empty the app runs in DEMO mode with sample data.
const String fbProject = String.fromEnvironment('FB_PROJECT');
const String fbApiKey = String.fromEnvironment('FB_API_KEY');
const String fbAppId = String.fromEnvironment('FB_APP_ID');
const String fbSender = String.fromEnvironment('FB_SENDER');
const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

bool get firebaseConfigured => fbProject.isNotEmpty && fbApiKey.isNotEmpty && fbAppId.isNotEmpty;

/// Where "Contact Us" emails go. Change this when the real support email is ready.
const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@vidyadesk.in');
const String appVersion = '1.0';

/// Ola Maps key (from the GitHub secret OLA_MAPS_KEY). Empty = maps hidden, GPS still works.
const String olaMapsKey = String.fromEnvironment('OLA_MAPS_KEY');

/// Our notification server (Cloudflare Worker). Empty = phone notifications off.
const String notifyUrl = String.fromEnvironment('NOTIFY_URL');
