import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'register_info_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() { _isLoading = true; });

    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      
      // 🎯 權限補強：向 Google 伺服器明確要到「讀寫 Google 行事曆」的權限
      googleProvider.addScope('https://www.googleapis.com/auth/calendar');

      // 🔥【超重要防守點】：強制 Google 彈出視窗每次都要讓使用者「選擇帳號」
      // 這樣可以徹底根治網頁端切換帳號時，UID 沒有真正刷新的 Bug！
      googleProvider.setCustomParameters({'prompt': 'select_account'});

      UserCredential userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      User? user = userCredential.user;

      if (user != null) {
        print("【CalenBridge】登入成功，正在檢查是否為新會員... UID: ${user.uid}");
        
        final db = FirebaseFirestore.instance;
        DocumentSnapshot userDoc = await db.collection('users').doc(user.uid).get();

        if (!mounted) return;

        if (userDoc.exists) {
          print("【CalenBridge】老會員回來了，導向首頁！");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          print("【CalenBridge】新會員初次登入，先初始化帳號資料，再導向個資設定頁！");
          
          // 💡 防守補強：在資料庫先建立基本文件，確保 UID 與 Email 優先綁定成功
          await db.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'email': user.email ?? '',
            'nickname': user.displayName ?? '', // 先拿 Google 的名字擋一下，等一下讓他在個資頁改
            'groupIds': [],                      // 預設沒有加入任何小組
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)); // 使用 merge 防止覆蓋

          if (!mounted) return;
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const RegisterInfoScreen()),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      print("【CalenBridge】登入失敗: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('登入失敗: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        size: 100,
                        color: Color(0xFF203764), 
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'CalenBridge',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '智慧行事曆跨團隊橋樑',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 60),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: OutlinedButton.icon(
                          onPressed: _handleGoogleSignIn,
                          icon: const Text(
                            'G', 
                            style: TextStyle(
                              color: Color(0xFF203764), 
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          label: const Text(
                            '使用 Google 帳號登入',
                            style: TextStyle(
                              color: Color(0xFF1F2937), 
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            side: const BorderSide(color: Color(0xFFE5E7EB)), 
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12), 
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}