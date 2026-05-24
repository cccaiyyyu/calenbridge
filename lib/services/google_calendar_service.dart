import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleCalendarService {
  // 靜態全域實體，防止重複彈出認證視窗
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '105456248073-7p478blrecon0e5v5b78sh6dfphb1obs.apps.googleusercontent.com',
    scopes: [calendar.CalendarApi.calendarScope],
  );

  // 檢查並獲取已登入帳號
  Future<GoogleSignInAccount?> _getSignedInAccount() async {
    if (_googleSignIn.currentUser != null) {
      return _googleSignIn.currentUser;
    }
    try {
      var account = await _googleSignIn.signInSilently();
      if (account != null) return account;
    } catch (e) {
      print("【CalenBridge API】無聲登入失敗，準備請求授權...");
    }
    return await _googleSignIn.signIn();
  }

  // 🛠️ 輔助工具：將 App 的重複設定轉譯為 Google 官方 RRULE 字串
  List<String>? _parseRecurrence(String repeatSetting) {
    if (repeatSetting == "不要" || repeatSetting.isEmpty) return null;
    String freq = "DAILY";
    if (repeatSetting == "每週") freq = "WEEKLY";
    else if (repeatSetting == "每個月") freq = "MONTHLY";
    else if (repeatSetting == "每年") freq = "YEARLY";
    
    return ["RRULE:FREQ=$freq"];
  }

  // 🛠️ 輔助工具：將 App 的提醒設定轉譯為 Google 官方 Reminders 架構
  calendar.EventReminders _parseReminders(String reminderSetting) {
    final reminders = calendar.EventReminders()
      ..useDefault = false
      ..overrides = [];

    if (reminderSetting == "不提醒" || reminderSetting.isEmpty) {
      return reminders; // 回傳空列表代表不提醒
    }

    int minutes = 0;
    if (reminderSetting == "10分鐘前") minutes = 10;
    else if (reminderSetting == "一小時前") minutes = 60;
    else if (reminderSetting == "一天前") minutes = 1440;
    // 「開始時間點」則保持 minutes = 0

    reminders.overrides!.add(
      calendar.EventReminder()
        ..method = 'popup'
        ..minutes = minutes,
    );
    return reminders;
  }

  /// 🎯 核心功能：將新任務自動同步到 Google 行事曆，支援提醒與重複週期
  Future<String?> insertEventToGoogleCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String reminderSetting, // 👈 新增參數
    required String repeatSetting,   // 👈 新增參數
    String? note,
  }) async {
    try {
      var account = await _getSignedInAccount();
      if (account == null) return null;

      bool isAuthorized = await _googleSignIn.canAccessScopes([calendar.CalendarApi.calendarScope]);
      if (!isAuthorized) {
        isAuthorized = await _googleSignIn.requestScopes([calendar.CalendarApi.calendarScope]);
        if (!isAuthorized) return null;
      }

      final Map<String, String> authHeaders = await account.authHeaders;
      final String? authHeaderValue = authHeaders['Authorization'];
      if (authHeaderValue == null || !authHeaderValue.startsWith('Bearer ')) return null;
      final String accessToken = authHeaderValue.substring(7);

      final authenticatedHttpClient = _TokenAuthClient(accessToken, http.Client());
      final calendarApi = calendar.CalendarApi(authenticatedHttpClient);

      // 打包標準 Google Event 物件
      final calendar.Event event = calendar.Event()
        ..summary = title 
        ..description = note ?? '透過 CalenBridge 智慧系統建立' 
        ..start = (calendar.EventDateTime()
          ..dateTime = startTime
          ..timeZone = 'Asia/Taipei') 
        ..end = (calendar.EventDateTime()
          ..dateTime = endTime
          ..timeZone = 'Asia/Taipei')
        ..recurrence = _parseRecurrence(repeatSetting)   // 🎯 注入官方重複週期
        ..reminders = _parseReminders(reminderSetting);   // 🎯 注入官方提醒設定

      print("【CalenBridge API】正在將行程（含週期與提醒設定）上傳至 Google 日曆...");
      final calendar.Event response = await calendarApi.events.insert(event, 'primary');
      return response.id; 
    } catch (e) {
      print("【CalenBridge API】💔 同步建立 Google 行事曆失敗: $e");
      rethrow;
    }
  }

  /// 🎯 核心功能：更新真實 Google 行事曆上的行程內容（含提醒與重複週期更新）
  Future<void> updateEventInGoogleCalendar({
    required String googleEventId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String reminderSetting, // 👈 新增參數
    required String repeatSetting,   // 👈 新增參數
    String? note,
  }) async {
    try {
      var account = await _getSignedInAccount();
      if (account == null) return;

      final Map<String, String> authHeaders = await account.authHeaders;
      final String? authHeaderValue = authHeaders['Authorization'];
      if (authHeaderValue == null || !authHeaderValue.startsWith('Bearer ')) return;
      final String accessToken = authHeaderValue.substring(7);

      final authenticatedHttpClient = _TokenAuthClient(accessToken, http.Client());
      final calendarApi = calendar.CalendarApi(authenticatedHttpClient);

      final calendar.Event updatedEvent = calendar.Event()
        ..summary = title
        ..description = note ?? '透過 CalenBridge 智慧系統更新'
        ..start = (calendar.EventDateTime()
          ..dateTime = startTime
          ..timeZone = 'Asia/Taipei')
        ..end = (calendar.EventDateTime()
          ..dateTime = endTime
          ..timeZone = 'Asia/Taipei')
        ..recurrence = _parseRecurrence(repeatSetting)   // 🎯 更新官方重複週期
        ..reminders = _parseReminders(reminderSetting);   // 🎯 更新官方提醒設定

      await calendarApi.events.update(updatedEvent, 'primary', googleEventId);
      print("【CalenBridge API】🔥 該行程內容（含週期與提醒設定）已同步修改完畢！");
    } catch (e) {
      print("【CalenBridge API】💔 同步修改 Google 行事曆失敗: $e");
      rethrow;
    }
  }

  /// 🎯 核心功能：根據 Google 事件 ID 刪除行程
  Future<void> deleteEventFromGoogleCalendar(String googleEventId) async {
    try {
      var account = await _getSignedInAccount();
      if (account == null) return;

      final Map<String, String> authHeaders = await account.authHeaders;
      final String? authHeaderValue = authHeaders['Authorization'];
      if (authHeaderValue == null || !authHeaderValue.startsWith('Bearer ')) return;
      final String accessToken = authHeaderValue.substring(7);

      final authenticatedHttpClient = _TokenAuthClient(accessToken, http.Client());
      final calendarApi = calendar.CalendarApi(authenticatedHttpClient);

      await calendarApi.events.delete('primary', googleEventId);
      print("【CalenBridge API】🗑️ 該行程已成功從真實 Google 行事曆中同步抹除！");
    } catch (e) {
      print("【CalenBridge API】💔 同步刪除 Google 行事曆失敗: $e");
      rethrow;
    }
  }
}

class _TokenAuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _innerClient;

  _TokenAuthClient(this._accessToken, this._innerClient);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _innerClient.send(request);
  }
}