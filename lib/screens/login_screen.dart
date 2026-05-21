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
      
      // 🎯 核心補強：向 Google 伺服器明確要到「讀寫 Google 行事曆」的史詩級權限！
      googleProvider.addScope('https://www.googleapis.com/auth/calendar');

      UserCredential userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      User? user = userCredential.user;

      if (user != null) {
        print("【CalenBridge】登入成功，正在檢查是否為新會員... UID: ${user.uid}");
        
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!mounted) return;

        if (userDoc.exists) {
          print("【CalenBridge】老會員回來了，導向首頁！");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          print("【CalenBridge】新會員初次登入，導向個資設定頁！");
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
        SnackBar(content: Text('登入失敗: $e')),
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