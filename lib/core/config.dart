// Values put in at build time by the GitHub build (from firebase-app.json).
// When they are empty the app runs in DEMO mode with sample data.
const String fbProject = String.fromEnvironment('FB_PROJECT');
const String fbApiKey = String.fromEnvironment('FB_API_KEY');
const String fbAppId = String.fromEnvironment('FB_APP_ID');
const String fbSender = String.fromEnvironment('FB_SENDER');
const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

bool get firebaseConfigured => fbProject.isNotEmpty && fbApiKey.isNotEmpty && fbAppId.isNotEmpty;
