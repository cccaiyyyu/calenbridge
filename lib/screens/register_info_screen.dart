import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 用於判斷是否在網頁端 (kIsWeb)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart'; 
import 'home_screen.dart';
import 'dart:convert';
import 'dart:typed_data'; 

class RegisterInfoScreen extends StatefulWidget {
  final bool isEditing;
  const RegisterInfoScreen({
    super.key, 
    this.isEditing = false, // <-- 加上這行
  });

  @override
  State<RegisterInfoScreen> createState() => _RegisterInfoScreenState();
  
}

class _RegisterInfoScreenState extends State<RegisterInfoScreen> {
  bool _syncCalendarSettings = false;
  final TextEditingController _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  // 1. 內建 Icon 頭像清單
  final List<IconData> _avatars = [
    Icons.face_rounded,
    Icons.sentiment_very_satisfied_rounded,
    Icons.workspace_premium_rounded,
    Icons.star_rounded,
    Icons.pets_rounded,
    Icons.bolt_rounded,
  ];
  


  // 2. 通知頻率設定（小時）
  int _notificationHours = 2; 
  final List<int> _hoursOptions = [1, 2, 4, 6, 8, 12, 24];
  int _selectedAvatarIndex = 0;
  XFile? _pickedImage;
  Uint8List? _webImage;

  bool _isLoading = false;
  
  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  // 觸發相簿選取自訂圖片
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 250,      
      maxHeight: 250,     
      imageQuality: 50,   
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _webImage = bytes;
        _pickedImage = image;
        _selectedAvatarIndex = -1; 
      });
    }
  }
    @override
void initState() {
  super.initState();
  if (widget.isEditing) {
    _loadExistingProfile();
  }
}

Future<void> _loadExistingProfile() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();

  if (!mounted || !userDoc.exists) return;

  final data = userDoc.data() as Map<String, dynamic>;
  final nickname = data['nickname'] ?? '';
  final raw = data['avatarUrl'] ?? '';
  
  // 🎯 補強：讀取原本資料庫儲存的偏好設定，若無則給予預設值
  final syncCalendar = data['syncCalendarSettings'] ?? false;
  final notiHours = data['notificationFrequencyHours'] ?? 2;

  setState(() {
    _nicknameController.text = nickname;
    _syncCalendarSettings = syncCalendar; // ✅ 正確回復 Switch 狀態
    _notificationHours = notiHours;      // ✅ 正確回復下拉選單狀態

    if (raw.startsWith('default_')) {
      _selectedAvatarIndex = int.tryParse(raw.replaceFirst('default_', '')) ?? 0;
      _webImage = null;
      _pickedImage = null;
    } else if (raw.startsWith('data:image')) {
      _selectedAvatarIndex = -1;
      final base64Str = raw.split(',').last;
      _webImage = base64Decode(base64Str);
    } else {
      _selectedAvatarIndex = 0;
    }
  });
}
  // 核心後端寫入邏輯
  Future<void> _saveProfileToFirestore() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() { _isLoading = true; });

  try {
    final User? user = FirebaseAuth.instance.currentUser;
    
    if (user != null) {
      String avatarData = "";

      if (_selectedAvatarIndex == -1 && _webImage != null) {
        print("【CalenBridge】將圖片轉換為 Base64 字串...");
        avatarData = "data:image/jpeg;base64,${base64Encode(_webImage!)}";
        
        if (avatarData.length > 1000000) {
          throw Exception("圖片檔案太大了，即使壓縮後仍超過資料庫限制，請更換其他照片。");
        }
      } else {
        avatarData = "default_$_selectedAvatarIndex";
      }

      print("【CalenBridge】準備寫入 Firestore，目標 UID: ${user.uid}");

      // 🎯 建立要寫入或更新的 Map 資料
      final Map<String, dynamic> userData = {
        'uid': user.uid,
        'email': user.email ?? '',
        'nickname': _nicknameController.text.trim(),
        'avatarUrl': avatarData, 
        'notificationFrequencyHours': _notificationHours,
        'syncCalendarSettings': _syncCalendarSettings,
      };

      // 🔥【防守關鍵】：如果是新會員（第一次初始化設定），才寫入註冊時間
      if (!widget.isEditing) {
        userData['createdAt'] = FieldValue.serverTimestamp();
      }

      // 寫入 Firestore (使用 merge 確保沒被蓋掉的欄位如 groupIds 依然健全)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userData, SetOptions(merge: true));

      print("【CalenBridge】後端 Firestore 寫入成功！");

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isEditing ? '偏好設定修改成功！' : '個人偏好初始化成功！')),
      );

      // 如果只是編輯模式，可以直接 pop 回去首頁或前一頁，不一定要推 Replacement
      if (widget.isEditing) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    }
  } catch (e) {
    print("【CalenBridge】Firestore 寫入異常: $e");
    if (!mounted) return;
    
    String errorMsg = e.toString();
    if (errorMsg.contains("longer than 1048487 bytes")) {
      errorMsg = "照片檔案太大（超過1MB限制），請嘗試更換其他照片或裁剪後上傳！";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('寫入後台資料庫失敗: $errorMsg')),
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
      appBar: AppBar(
        title: Text(widget.isEditing ? '個人化設定' : '個人偏好初始化設定'),
        //title: const Text('個人偏好初始化設定', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(40.0), // 稍微縮小 padding 讓畫面能放得下新選項
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('選擇系統頭像或自行上傳', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    
                    SizedBox(
                      height: 70,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _avatars.length + 1, 
                        itemBuilder: (context, index) {
                          if (index == _avatars.length) {
                            final isCustomSelected = _selectedAvatarIndex == -1;
                            return GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCustomSelected ? const Color(0xFF203764) : Colors.grey.shade400, 
                                    width: isCustomSelected ? 3 : 1
                                  ),
                                ),
                                child: CircleAvatar(
                                  backgroundColor: Colors.grey.shade200,
                                  radius: 26,
                                  backgroundImage: (_selectedAvatarIndex == -1 && _webImage != null)
                                      ? MemoryImage(_webImage!) 
                                      : null,
                                  child: (_selectedAvatarIndex == -1 && _webImage != null)
                                      ? null
                                      : Icon(Icons.add_a_photo_rounded, color: Colors.grey.shade700, size: 20),
                                ),
                              ),
                            );
                          }

                          final isSelected = _selectedAvatarIndex == index;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedAvatarIndex = index),
                            child: Container(
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF203764) : Colors.transparent, 
                                  width: isSelected ? 3 : 1
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: isSelected ? const Color(0xFF203764) : Colors.grey.shade100,
                                child: Icon(_avatars[index], color: isSelected ? Colors.white : Colors.grey.shade700),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    const Text('輸入你的暱稱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(hintText: '例如：阿光'), 
                      validator: (value) => (value == null || value.trim().isEmpty) ? '暱稱不能留白喔！' : null,
                    ),
                    const SizedBox(height: 30),
                    
                    const Text('待處理區通知頻率設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _notificationHours,
                      decoration: const InputDecoration(), 
                      items: _hoursOptions.map((h) => DropdownMenuItem(value: h, child: Text('每隔 $h 小時傳送一次通知'))).toList(),
                      onChanged: (val) => setState(() => _notificationHours = val ?? 2),
                    ),
                    const SizedBox(height: 30),

                    // 🎯 新增：Google 行事曆同步偏好設定 UI
                    const Text('行事曆同步設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '完整保留提醒與重複設定', 
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)
                        ),
                        subtitle: const Text(
                          '開啟：完美複製 App 內的提醒與重複規則。\n關閉：寫入 Google 的任務一律預設為「不提醒、不重複」。', 
                          style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)
                        ),
                        value: _syncCalendarSettings,
                        activeColor: const Color(0xFF203764),
                        onChanged: (bool value) {
                          setState(() {
                            _syncCalendarSettings = value; // 更新偏好狀態
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    ElevatedButton(
                      onPressed: _saveProfileToFirestore,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52), 
                        backgroundColor: const Color(0xFF203764), // 確保按鈕有顏色
                      ),
                      child: const Text(
                        '完成設定！', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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