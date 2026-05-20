import 'package:flutter/material.dart';
import 'home_screen.dart'; // 確保 home_screen.dart 與此檔案在同一個 screens 資料夾下
import 'package:google_sign_in/google_sign_in.dart';
// 🎯 這是你剛剛少引入的關鍵：Firebase Auth 核心套件
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 日曆圖標
              Icon(
                Icons.calendar_month_rounded,
                size: 90,
                color: Theme.of(context).primaryColor, // 自動抓取深海藍
              ),
              const SizedBox(height: 20),
              
              // 2. 專案名稱與副標
              const Text(
                'CalenBridge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '智慧行事曆跨團隊橋樑',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 60), // 拉開跟按鈕的距離，讓畫面呼吸
              
              // 3. 🎯 串接整合 Google 登入與 Firebase Auth 服務的核心按鈕
              OutlinedButton(
                onPressed: () async {
                  try {
                    print("【CalenBridge】第一階段：啟動 Google 認證觸發方法...");
                    
                    // 帶入你昨晚查到的真實 Web Client ID
                    final GoogleSignIn googleSignIn = GoogleSignIn(
                      clientId: '105456248073-7p478blrecon0e5v5b78sh6dfphb1obs.apps.googleusercontent.com',
                    );
                    
                    // 1. 拉起 Google 帳號選擇視窗
                    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
                    
                    if (googleUser == null) {
                      print("【CalenBridge】使用者取消了 Google 登入視窗。");
                      return; // 使用者中途關閉視窗，直接攔截並結束
                    }
                    
                    print("【CalenBridge】第二階段：Google 驗證成功，正在擷取身分驗證權杖...");
                    // 2. 從 Google 帳號中取得金鑰認證資料
                    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
                    
                    // 3. 將 Google 拿到的通行證，轉換成 Firebase Auth 的登入憑證
                    final OAuthCredential credential = GoogleAuthProvider.credential(
                      accessToken: googleAuth.accessToken,
                      idToken: googleAuth.idToken,
                    );
                    
                    print("【CalenBridge】第三階段：將憑證送往 Firebase Auth 後台進行驗收與使用者生成...");
                    // 4. 傳送憑證讓 Firebase 服務在後台生成並認證使用者資訊
                    final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
                    
                    final User? firebaseUser = userCredential.user;
                    
                    if (firebaseUser != null) {
                      print("【CalenBridge】🔥 Firebase 后台驗收成功！使用者資訊生成完畢 🔥");
                      print("唯一識別碼 UID: ${firebaseUser.uid}");
                      print("使用者名稱: ${firebaseUser.displayName}");
                      
                      if (!context.mounted) return;

                      // 彈出成功提示
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Firebase 後台驗收成功！歡迎回來，${firebaseUser.displayName}！')),
                      );

                      // 跳轉到首頁且無法返回
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const HomeScreen()),
                      );
                    }
                  } on FirebaseAuthException catch (e) {
                    // 專門擷取 Firebase 服務噴出的特定異常
                    print("【CalenBridge】Firebase Auth 後台驗收失敗: [${e.code}] ${e.message}");
                    if (!context.mounted) return;
                    _showErrorDialog(context, "Firebase 後台拒絕驗收", "錯誤代碼: ${e.code}\n${e.message}");
                  } catch (error) {
                    // 擷取其餘未知異常（例如你剛剛遇到的 popup_closed）
                    print("【CalenBridge】系統認證擷取到異常邏輯: $error");
                    if (!context.mounted) return;
                    _showErrorDialog(context, "安全認證失敗", "在串接服務時擷取到異常邏輯，請重試。\n錯誤代碼: $error");
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.g_mobiledata_rounded, size: 30, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      '使用 Google 帳號登入',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 抽離出的精緻 Dialog 提示
  void _showErrorDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }
}