import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GoogleCalendarService {
  // 🎯 v6 世代最穩定的全域認證實體
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // ✅ 修正 2：clientId 僅對 iOS/Web 有效，Android 靠 google-services.json
    // 若目標平台包含 Android，此行可安全移除；Web/iOS 保留即可
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

  /// 🛠️ 輔助工具：從 Firestore 查詢當前使用者是否開啟「完整同步偏好」
  Future<bool> _getUserSyncPreference() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['syncCalendarSettings'] ?? true;
      }
    } catch (e) {
      print("【CalenBridge API】讀取使用者行事曆同步偏好失敗: $e");
    }
    return true;
  }

  // 🛠️ 輔助工具：將 App 的重複設定轉譯為 Google 官方 RRULE 字串
  List<String>? _parseRecurrence(String repeatSetting, bool isSyncEnabled) {
    if (!isSyncEnabled || repeatSetting == "不要" || repeatSetting.isEmpty) {
      return null;
    }

    String freq = "DAILY";
    if (repeatSetting == "每週") freq = "WEEKLY";
    else if (repeatSetting == "每個月") freq = "MONTHLY";
    else if (repeatSetting == "每年") freq = "YEARLY";

    return ["RRULE:FREQ=$freq"];
  }

  // 🛠️ 輔助工具：將 App 的提醒設定轉譯為 Google 官方 Reminders 架構
  calendar.EventReminders _parseReminders(
      String reminderSetting, bool isSyncEnabled) {
    final reminders = calendar.EventReminders()
      ..useDefault = false
      ..overrides = [];

    if (!isSyncEnabled ||
        reminderSetting == "不提醒" ||
        reminderSetting.isEmpty) {
      return reminders;
    }

    int minutes = 0;
    if (reminderSetting == "10分鐘前") minutes = 10;
    else if (reminderSetting == "一小時前") minutes = 60;
    else if (reminderSetting == "一天前") minutes = 1440;

    reminders.overrides!.add(
      calendar.EventReminder()
        ..method = 'popup'
        ..minutes = minutes,
    );
    return reminders;
  }

  /// 🎯 核心功能：【真實連線】將新任務自動同步到 Google 行事曆
  Future<String?> insertEventToGoogleCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String reminderSetting,
    required String repeatSetting,
    String? note,
  }) async {
    try {
      var account = await _getSignedInAccount();
      if (account == null) return null;

      bool isAuthorized = await _googleSignIn
          .canAccessScopes([calendar.CalendarApi.calendarScope]);
      if (!isAuthorized) {
        isAuthorized = await _googleSignIn
            .requestScopes([calendar.CalendarApi.calendarScope]);
        if (!isAuthorized) return null;
      }

      final calendarApi = await _buildCalendarApi(account);
      if (calendarApi == null) return null;

      final bool isSyncEnabled = await _getUserSyncPreference();
      print("【CalenBridge API】目前真實同步開關狀態為: $isSyncEnabled");

      final calendar.Event event = calendar.Event()
        ..summary = title
        ..description = note ?? '透過 CalenBridge 智慧系統建立'
        ..start = (calendar.EventDateTime()
          ..dateTime = startTime
          ..timeZone = 'Asia/Taipei')
        ..end = (calendar.EventDateTime()
          ..dateTime = endTime
          ..timeZone = 'Asia/Taipei')
        ..recurrence = _parseRecurrence(repeatSetting, isSyncEnabled)
        ..reminders = _parseReminders(reminderSetting, isSyncEnabled);

      print("【CalenBridge API】🚀 正在將行程「真實寫入」Google 雲端日曆中...");
      final calendar.Event response =
          await calendarApi.events.insert(event, 'primary');
      print("【CalenBridge API】🎉 寫入成功！Google 事件 ID: ${response.id}");
      return response.id;
    } catch (e) {
      print("【CalenBridge API】💔 真實同步建立 Google 行事曆失敗: $e");
      rethrow;
    }
  }

  /// 🎯 核心功能：【真實連線】更新真實 Google 行事曆上的行程內容
  Future<void> updateEventInGoogleCalendar({
    required String googleEventId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required String reminderSetting,
    required String repeatSetting,
    String? note,
  }) async {
    try {
      var account = await _getSignedInAccount();
      if (account == null) return;

      final calendarApi = await _buildCalendarApi(account);
      if (calendarApi == null) return;

      final bool isSyncEnabled = await _getUserSyncPreference();

      final calendar.Event updatedEvent = calendar.Event()
        ..summary = title
        ..description = note ?? '透過 CalenBridge 智慧系統更新'
        ..start = (calendar.EventDateTime()
          ..dateTime = startTime
          ..timeZone = 'Asia/Taipei')
        ..end = (calendar.EventDateTime()
          ..dateTime = endTime
          ..timeZone = 'Asia/Taipei')
        ..recurrence = _parseRecurrence(repeatSetting, isSyncEnabled)
        ..reminders = _parseReminders(reminderSetting, isSyncEnabled);

      await calendarApi.events.update(updatedEvent, 'primary', googleEventId);
      print("【CalenBridge API】🔥 該行程內容已同步「真實修改」至 Google 日曆！");
    } catch (e) {
      print("【CalenBridge API】💔 同步修改 Google 行事曆失敗: $e");
      rethrow;
    }
  }

  /// 🎯 核心功能：【真實連線】根據 Google 事件 ID 刪除行程
  Future<void> deleteEventFromGoogleCalendar(String googleEventId) async {
    try {
      var account = await _getSignedInAccount();
      if (account == null) return;

      final calendarApi = await _buildCalendarApi(account);
      if (calendarApi == null) return;

      await calendarApi.events.delete('primary', googleEventId);
      print("【CalenBridge API】🗑️ 該行程已成功從真實 Google 行事曆中「同步抹除」！");
    } catch (e) {
      print("【CalenBridge API】💔 同步刪除 Google 行事曆失敗: $e");
      rethrow;
    }
  }

  /// 🎯 功能 5：智慧反向同步 - 抓取「今天起兩週內」行程，按時間排序，並回傳待勾選清單
  Future<List<Map<String, dynamic>>> fetchTwoWeeksGoogleEvents() async {
    try {
      print("【CalenBridge 同步】發動反向抓取，準備建立 Google 通訊端...");

      var account = await _getSignedInAccount();
      if (account == null) throw Exception("無法取得 Google 帳號，請重新登入！");

      bool isAuthorized = await _googleSignIn
          .canAccessScopes([calendar.CalendarApi.calendarScope]);
      if (!isAuthorized) {
        isAuthorized = await _googleSignIn
            .requestScopes([calendar.CalendarApi.calendarScope]);
        if (!isAuthorized) throw Exception("您拒絕了行事曆授權，系統無法抓取行程喔！");
      }

      final calendarApi = await _buildCalendarApi(account);
      if (calendarApi == null) throw Exception("無法取得有效的 Google 授權憑證");

      final now = DateTime.now();
      final todayStart =
          DateTime(now.year, now.month, now.day, 0, 0, 0).toUtc();
      final twoWeeksEnd = DateTime(now.year, now.month, now.day, 23, 59, 59)
          .add(const Duration(days: 14))
          .toUtc();

      print(
          "【CalenBridge 同步】正在撈取 Google 雲端行程清單 (範圍: ${todayStart.toLocal()} ~ ${twoWeeksEnd.toLocal()})...");
      final calendar.Events events = await calendarApi.events.list(
        'primary',
        timeMin: todayStart,
        timeMax: twoWeeksEnd,
        singleEvents: true,
      );

      List<Map<String, dynamic>> googleTodoDataList = [];
      final String? uid = FirebaseAuth.instance.currentUser?.uid;

      if (events.items != null && uid != null) {
        for (var event in events.items!) {
          if (event.id == null) continue;

          // ✅ 修正 4：防重複改用 assignedTo，與 _buildTodoQuery 對齊
          final duplicateCheck = await FirebaseFirestore.instance
              .collection('todos')
              .where('assignedTo', isEqualTo: uid)
              .where('googleEventId', isEqualTo: event.id)
              .get();

          if (duplicateCheck.docs.isEmpty) {
            DateTime startDateTime =
                event.start?.dateTime ?? event.start?.date ?? DateTime.now();
            DateTime endDateTime = event.end?.dateTime ??
                event.end?.date ??
                startDateTime.add(const Duration(hours: 1));

            String startTimeIso = startDateTime.toLocal().toIso8601String();
            String endTimeIso = endDateTime.toLocal().toIso8601String();

            googleTodoDataList.add({
              'googleEventId': event.id,
              'title': event.summary ?? '未命名 Google 行程',
              'startTime': startTimeIso,
              'endTime': endTimeIso,
              'deadline': endTimeIso,
              'color': 0xFF203764,
              'reminderSetting': "開始時間點",
              'repeatSetting': "不要",
              'groupId': "personal",
              // ✅ 修正 4：ownerUid 和 assignedTo 都寫入，確保查詢不漏
              'ownerUid': uid,
              'assignedTo': uid,
              'note': event.description ?? '自 Google 行事曆一鍵同步拉回',
              'isCompleted': false,
            });
          }
        }

        googleTodoDataList.sort((a, b) {
          DateTime timeA = DateTime.parse(a['startTime']);
          DateTime timeB = DateTime.parse(b['startTime']);
          return timeA.compareTo(timeB);
        });
      }

      print(
          "【CalenBridge 同步】成功抓取並排序了 ${googleTodoDataList.length} 筆潛在同步行程。");
      return googleTodoDataList;
    } catch (e) {
      print("【CalenBridge 同步大爆炸】抓取失敗: $e");
      rethrow;
    }
  }

  // ✅ 新增：抽出共用的 CalendarApi 建立邏輯，避免各方法重複撰寫
  Future<calendar.CalendarApi?> _buildCalendarApi(
      GoogleSignInAccount account) async {
    final Map<String, String> authHeaders = await account.authHeaders;
    final String? authHeaderValue = authHeaders['Authorization'];
    if (authHeaderValue == null || !authHeaderValue.startsWith('Bearer ')) {
      return null;
    }
    final String accessToken = authHeaderValue.substring(7);
    final authenticatedHttpClient = _TokenAuthClient(accessToken, http.Client());
    return calendar.CalendarApi(authenticatedHttpClient);
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