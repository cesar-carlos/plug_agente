import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navPlayground.
  ///
  /// In en, this message translates to:
  /// **'Playground'**
  String get navPlayground;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @titlePlayground.
  ///
  /// In en, this message translates to:
  /// **'Playground Database'**
  String get titlePlayground;

  /// No description provided for @titleConfig.
  ///
  /// In en, this message translates to:
  /// **'Settings - Plug Database'**
  String get titleConfig;

  /// No description provided for @modalTitleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get modalTitleSuccess;

  /// No description provided for @modalTitleError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get modalTitleError;

  /// No description provided for @modalTitleAuthError.
  ///
  /// In en, this message translates to:
  /// **'Authentication Error'**
  String get modalTitleAuthError;

  /// No description provided for @modalTitleConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get modalTitleConnectionError;

  /// No description provided for @modalTitleConfigError.
  ///
  /// In en, this message translates to:
  /// **'Configuration Error'**
  String get modalTitleConfigError;

  /// No description provided for @modalTitleConnectionEstablished.
  ///
  /// In en, this message translates to:
  /// **'Connection Established'**
  String get modalTitleConnectionEstablished;

  /// No description provided for @modalTitleDriverNotFound.
  ///
  /// In en, this message translates to:
  /// **'Driver Not Found'**
  String get modalTitleDriverNotFound;

  /// No description provided for @modalTitleConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection Successful'**
  String get modalTitleConnectionSuccessful;

  /// No description provided for @modalTitleConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get modalTitleConnectionFailed;

  /// No description provided for @modalTitleConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Configuration Saved'**
  String get modalTitleConfigSaved;

  /// No description provided for @modalTitleErrorTestingConnection.
  ///
  /// In en, this message translates to:
  /// **'Error Testing Connection'**
  String get modalTitleErrorTestingConnection;

  /// No description provided for @modalTitleErrorVerifyingDriver.
  ///
  /// In en, this message translates to:
  /// **'Error Verifying Driver'**
  String get modalTitleErrorVerifyingDriver;

  /// No description provided for @modalTitleErrorSaving.
  ///
  /// In en, this message translates to:
  /// **'Error Saving'**
  String get modalTitleErrorSaving;

  /// No description provided for @modalTitleConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection Status'**
  String get modalTitleConnectionStatus;

  /// No description provided for @msgAuthenticatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Authenticated successfully!'**
  String get msgAuthenticatedSuccessfully;

  /// No description provided for @msgWebSocketConnectedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Connected to WebSocket server successfully!'**
  String get msgWebSocketConnectedSuccessfully;

  /// No description provided for @msgDatabaseConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Database connection established successfully!'**
  String get msgDatabaseConnectionSuccessful;

  /// No description provided for @msgConfigSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Configuration saved successfully!'**
  String get msgConfigSavedSuccessfully;

  /// No description provided for @msgConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'success'**
  String get msgConnectionSuccessful;

  /// No description provided for @msgOdbcDriverNameRequired.
  ///
  /// In en, this message translates to:
  /// **'ODBC Driver name is required'**
  String get msgOdbcDriverNameRequired;

  /// No description provided for @msgConnectionCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to database. Check credentials and settings.'**
  String get msgConnectionCheckFailed;

  /// No description provided for @btnOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get btnOk;

  /// No description provided for @btnCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get btnCancel;

  /// No description provided for @queryNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get queryNoResults;

  /// No description provided for @queryNoResultsMessage.
  ///
  /// In en, this message translates to:
  /// **'Execute a SELECT query to see results here.'**
  String get queryNoResultsMessage;

  /// No description provided for @queryTotalRecords.
  ///
  /// In en, this message translates to:
  /// **'Total records'**
  String get queryTotalRecords;

  /// No description provided for @queryExecutionTime.
  ///
  /// In en, this message translates to:
  /// **'Execution time'**
  String get queryExecutionTime;

  /// No description provided for @queryAffectedRows.
  ///
  /// In en, this message translates to:
  /// **'Affected rows'**
  String get queryAffectedRows;

  /// No description provided for @dashboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Monitor your agent status and database connections here.'**
  String get dashboardDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
