import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleCalendarService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '105456248073-7p478blrecon0e5v5b78sh6dfphb1obs.apps.googleusercontent.com',
    // 這裡宣告了我們需要行事曆權限，但在 Web 端還不夠，後面必須顯式 request
    scopes: [calendar.CalendarApi.calendarScope], 
  );

  /// 🎯 核心功能：將 Flutter 新增的任務自動同步到 Google 行事曆
  Future<void> insertEventToGoogleCalendar({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? note,
  }) async {
    try {
      print("【CalenBridge API】正在嘗試獲取當前 Google 登入帳號的授權通訊端...");
      
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      account ??= await _googleSignIn.signIn();

      if (account == null) {
        print("【CalenBridge API】錯誤：無法取得合法的 Google 帳號授權");
        return;
      }

      // 🌟 終極殺招：防禦 Web 端 401 錯誤！
      // 檢查目前的登入狀態有沒有真正獲得「行事曆控制權限」
      bool isAuthorized = await _googleSignIn.canAccessScopes([calendar.CalendarApi.calendarScope]);
      
      if (!isAuthorized) {
        print("【CalenBridge API】發現尚未擁有日曆存取權，正在呼叫 Google 授權視窗...");
        // 強制要求使用者打勾同意行事曆權限
        isAuthorized = await _googleSignIn.requestScopes([calendar.CalendarApi.calendarScope]);
        if (!isAuthorized) {
          print("【CalenBridge API】錯誤：使用者拒絕了日曆存取權限！同步中斷。");
          return;
        }
      }

      // 經過上面的授權後，這裡提取出來的 AccessToken 就會是擁有行事曆寫入權限的「真鑰匙」了！
      final Map<String, String> authHeaders = await account.authHeaders;
      final String? authHeaderValue = authHeaders['Authorization'];
      
      if (authHeaderValue == null || !authHeaderValue.startsWith('Bearer ')) {
        print("【CalenBridge API】錯誤：無法從帳戶中提取有效的 Bearer 認證權杖");
        return;
      }
      
      final String accessToken = authHeaderValue.substring(7);

      final authenticatedHttpClient = _TokenAuthClient(accessToken, http.Client());
      final calendarApi = calendar.CalendarApi(authenticatedHttpClient);

      final calendar.Event event = calendar.Event()
        ..summary = title 
        ..description = note ?? '透過 CalenBridge 智慧系統建立' 
        ..start = (calendar.EventDateTime()
          ..dateTime = startTime
          ..timeZone = 'Asia/Taipei') 
        ..end = (calendar.EventDateTime()
          ..dateTime = endTime
          ..timeZone = 'Asia/Taipei');

      print("【CalenBridge API】火箭升空！正在將行程傳送至真實 Google 日曆...");
      final calendar.Event response = await calendarApi.events.insert(event, 'primary');
      print("【CalenBridge API】🔥 史詩級成功！真實 Google 日曆已同步生成，事件 ID: ${response.id}");
    } catch (e) {
      print("【CalenBridge API】💔 串接大爆炸，同步 Google 行事曆失敗: $e");
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