import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:calenbridge/services/google_calendar_service.dart';

class AddTodoBottomSheet extends StatefulWidget {
  
  final String currentSelectedTab;
  final List<Map<String, String>> groupTabs;
  final VoidCallback onTodoAdded; 

  final String? todoId;
  final Map<String, dynamic>? initialData;
  
  const AddTodoBottomSheet({
    super.key,
    required this.currentSelectedTab,
    required this.groupTabs,
    required this.onTodoAdded,
    this.todoId,
    this.initialData,
  });

  @override
  State<AddTodoBottomSheet> createState() => _AddTodoBottomSheetState();
  
}

class _AddTodoBottomSheetState extends State<AddTodoBottomSheet> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String? _assignedToUid;      // 被指派的組員 uid
  String? _assignedToEmail;    // 被指派的組員 email
  List<Map<String, String>> _groupMembers = []; // 目前小組的組員清單
  bool _canAssignTask = false;  // 當前使用者是否有指派權限
  late int _selectedColorValue; 
  late DateTime _startDateTime;
  late DateTime _endDateTime;
  late String _reminderSetting;
  late String _repeatSetting;
  late String _selectedGroupId;

  bool _isSaving = false;
  
  final List<int> _colorOptions = [0xFF203764, 0xFFE53935, 0xFF43A047, 0xFFFB8C00, 0xFF8E24AA, 0xFF00ACC1];
  final List<String> _reminderOptions = ["不提醒", "開始時間點", "10分鐘前", "一小時前", "一天前", "自訂"];
  final List<String> _repeatOptions = ["不要", "每天", "每週", "每個月", "每年"];

  bool get _isEditMode => widget.todoId != null; 

  @override
  void initState() {
    super.initState();
    // 在 initState() 最後加
    if (_isEditMode && widget.initialData != null) {
     _assignedToUid = widget.initialData!['assignedToUid'];
     _assignedToEmail = widget.initialData!['assignedToEmail'];
      }
    _loadGroupMembersAndPermission();
    
    if (_isEditMode && widget.initialData != null) {
      final data = widget.initialData!;
      _titleController.text = data['title'] ?? '';
      _noteController.text = data['note'] ?? '';
      _selectedColorValue = data['color'] ?? 0xFF203764;
      _startDateTime = DateTime.parse(data['startTime'] ?? DateTime.now().toIso8601String());
      _endDateTime = DateTime.parse(data['endTime'] ?? DateTime.now().add(const Duration(hours: 1)).toIso8601String());
      _reminderSetting = data['reminderSetting'] ?? "不提醒"; 
      _repeatSetting = data['repeatSetting'] ?? "不要";
      _selectedGroupId = data['groupId'] ?? "personal";
    } else {
      _selectedColorValue = 0xFF203764; 
      _startDateTime = DateTime.now().add(const Duration(minutes: 30));
      _endDateTime = DateTime.now().add(const Duration(hours: 1, minutes: 30));
      
      _reminderSetting = "不提醒"; 
      _repeatSetting = "不要";
      _selectedGroupId = "personal";

      if (widget.currentSelectedTab != "所有" && widget.currentSelectedTab != "個人") {
        final currentTab = widget.groupTabs.firstWhere(
          (t) => t['name'] == widget.currentSelectedTab, 
          orElse: () => {"id": "personal"}
        );
        _selectedGroupId = currentTab['id']!;
      }
    }
    
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }
  Future<void> _loadGroupMembersAndPermission() async {
  if (_selectedGroupId == 'personal') return;

  final db = FirebaseFirestore.instance;

  // 取得小組資料
  final groupDoc = await db.collection('groups').doc(_selectedGroupId).get();
  if (!groupDoc.exists) return;
  final groupData = groupDoc.data() as Map<String, dynamic>;

  // 判斷當前使用者是否有指派權限
  final permissions = groupData['memberPermissions'] as Map<String, dynamic>? ?? {};
  final myPerm = permissions[_currentUser?.uid] as Map<String, dynamic>? ?? {};
  final canAssign = myPerm['canAssignTask'] ?? false;
  final isCreator = groupData['creatorUid'] == _currentUser?.uid;

  // 取得組員 email 清單（排除自己）
  final List memberIds = groupData['memberIds'] ?? [];
  final List<Map<String, String>> members = [];
  for (final uid in memberIds) {
    if (uid == _currentUser?.uid) continue;
    final userDoc = await db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final email = (userDoc.data() as Map<String, dynamic>)['email'] ?? uid;
      members.add({'uid': uid, 'email': email});
    }
  }

  if (mounted) {
    setState(() {
      _canAssignTask = canAssign || isCreator;
      _groupMembers = members;
    });
  }
}
  Widget _buildTimeWheel({
    required int itemCount,
    required int selectedValue,
    required ValueChanged<int> onSelectedItemChanged,
  }) {
    return SizedBox(
      height: 90, 
      width: 45,   
      child: ListWheelScrollView.useDelegate(
        controller: FixedExtentScrollController(initialItem: selectedValue),
        itemExtent: 30, 
        perspective: 0.004, 
        diameterRatio: 1.1, 
        physics: const FixedExtentScrollPhysics(), 
        onSelectedItemChanged: onSelectedItemChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (context, index) {
            final isSelected = index == selectedValue;
            return Center(
              child: Text(
                index.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: isSelected ? 22 : 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.black : Colors.grey.shade400,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDateTimePickerSection({
    required String label,
    required DateTime currentDateTime,
    required Function(DateTime) onDateTimeChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: currentDateTime,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2030),
                );
                if (pickedDate != null) {
                  onDateTimeChanged(DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    currentDateTime.hour,
                    currentDateTime.minute,
                  ));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(
                    "${currentDateTime.year}/${currentDateTime.month.toString().padLeft(2, '0')}/${currentDateTime.day.toString().padLeft(2, '0')}",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF203764)),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 20, thickness: 1),
          Row(
            children: [
              _buildTimeWheel(
                itemCount: 24,
                selectedValue: currentDateTime.hour,
                onSelectedItemChanged: (h) {
                  onDateTimeChanged(DateTime(
                    currentDateTime.year, currentDateTime.month, currentDateTime.day,
                    h, currentDateTime.minute,
                  ));
                },
              ),
              const Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              _buildTimeWheel(
                itemCount: 60,
                selectedValue: currentDateTime.minute,
                onSelectedItemChanged: (m) {
                  onDateTimeChanged(DateTime(
                    currentDateTime.year, currentDateTime.month, currentDateTime.day,
                    currentDateTime.hour, m,
                  ));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTodo() async {
    if (!_isEditMode) return;
    setState(() { _isSaving = true; });
    try {
      final String? googleEventId = widget.initialData?['googleEventId'];
      if (googleEventId != null && googleEventId.isNotEmpty) {
        try {
          await GoogleCalendarService().deleteEventFromGoogleCalendar(googleEventId);
        } catch (googleError) {
          print("【CalenBridge 提醒】Google 日曆刪除同步略過: $googleError");
        }
      }

      await FirebaseFirestore.instance.collection('todos').doc(widget.todoId).delete();
      widget.onTodoAdded();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除失敗: $e')));
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }

  Future<void> _saveOrUpdateTodo() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('任務名稱不能留空喔！')));
      return;
    }

    if (_endDateTime.isBefore(_startDateTime) || _endDateTime.isAtSameMomentAs(_startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('結束時間必須晚於開始時間喔！')));
      return;
    }

    setState(() { _isSaving = true; });

    // 1. 準備寫入 Firestore 的任務本體資料
    final Map<String, dynamic> todoData = {
      'title': _titleController.text.trim(),
      'color': _selectedColorValue,
      'startTime': _startDateTime.toIso8601String(), 
      'endTime': _endDateTime.toIso8601String(),
      'reminderSetting': _reminderSetting,
      'repeatSetting': _repeatSetting,
      'groupId': _selectedGroupId,
      'ownerUid': _currentUser?.uid, 
      'note': _noteController.text.trim(),
      'assignedToUid': _assignedToUid,
      'assignedToEmail': _assignedToEmail,
    };

    try {
      // 🎯 核心優化：線上獲取使用者在註冊時設定的個人檔案同步偏好
      bool syncCalendarSettings = true; // 預設為 true (要一樣)
      if (_currentUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser.uid)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          // 💡 請確保你們註冊頁面存入的欄位名稱叫作 'syncCalendarSettings' (型態為 bool)
          syncCalendarSettings = userData['syncCalendarSettings'] ?? true;
        }
      }
      // 如果有指派對象，發送通知
if (_assignedToUid != null && !_isEditMode) {
  await FirebaseFirestore.instance.collection('notifications').add({
    'type': 'taskAssigned',
    'toUserId': _assignedToUid,
    'toEmail': _assignedToEmail,
    'fromUserId': _currentUser?.uid,
    'fromEmail': _currentUser?.email,
    'fromName': _currentUser?.displayName ?? _currentUser?.email,
    'taskName': _titleController.text.trim(),
    'groupId': _selectedGroupId,
    'isRead': false,
    'status': 'pending', // pending / accepted / rejected
    'createdAt': FieldValue.serverTimestamp(),
  });
}

      // 🎯 核心優化：偏好規則分流計算
      String finalGoogleReminder = "不提醒";
      String finalGoogleRepeat = "不要";

      if (syncCalendarSettings) {
        // 要一樣：完美複製 App 畫面上的參數
        finalGoogleReminder = _reminderSetting;
        finalGoogleRepeat = _repeatSetting;
      } else {
        // 不要一樣：無視 App 的選擇，強制預設為不提醒、不重複
        print("【CalenBridge 偏好】使用者設定不同步參數，日曆將預設為不提醒與不重複。");
      }

      if (!_isEditMode) {
        // 新增模式
        try {
          print("【CalenBridge 聯動】正在連動建立 Google 行事曆事件...");
          final String? googleId = await GoogleCalendarService().insertEventToGoogleCalendar(
            title: _titleController.text.trim(),
            startTime: _startDateTime,
            endTime: _endDateTime,
            reminderSetting: finalGoogleReminder, // 👈 帶入分流後的參數
            repeatSetting: finalGoogleRepeat,     // 👈 帶入分流後的參數
            note: _noteController.text.trim(),
          );
          if (googleId != null) {
            todoData['googleEventId'] = googleId;
          }
        } catch (googleError) {
          print("【CalenBridge 提醒】Google 日曆背景建立同步略過: $googleError");
        }

        todoData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('todos').add(todoData);
      } else {
        // 修改模式
        await FirebaseFirestore.instance.collection('todos').doc(widget.todoId).update(todoData);

        final String? googleEventId = widget.initialData?['googleEventId'];
        if (googleEventId != null && googleEventId.isNotEmpty) {
          try {
            print("【CalenBridge 聯動】正在連動修改 Google 行事曆事件...");
            await GoogleCalendarService().updateEventInGoogleCalendar(
              googleEventId: googleEventId,
              title: _titleController.text.trim(),
              startTime: _startDateTime,
              endTime: _endDateTime,
              reminderSetting: finalGoogleReminder, // 👈 帶入分流後的參數
              repeatSetting: finalGoogleRepeat,     // 👈 帶入分流後的參數
              note: _noteController.text.trim(),
            );
          } catch (googleError) {
            print("【CalenBridge 提醒】Google 日曆修改同步失敗: $googleError");
          }
        }
      }

      widget.onTodoAdded(); 
      if (!mounted) return;
      Navigator.pop(context); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('資料庫處理失敗: $e')));
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 24, left: 24, right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24, 
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEditMode ? '⚙️ 編輯任務項目' : '建立新任務', 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                ),
                if (_isEditMode)
                  IconButton(
                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
                    onPressed: _deleteTodo,
                  ),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '任務名稱',
                prefixIcon: Icon(Icons.assignment_rounded),
              ),
            ),
            const SizedBox(height: 16),

            const Text('選擇代表顏色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colorOptions.length,
                itemBuilder: (context, index) {
                  final colorVal = _colorOptions[index];
                  final isSelected = _selectedColorValue == colorVal;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColorValue = colorVal),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 36,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: const Color(0xFF203764), width: 3) : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            _buildDateTimePickerSection(
              label: '📅 開始日期與時間',
              currentDateTime: _startDateTime,
              onDateTimeChanged: (newDateTime) {
                setState(() {
                  _startDateTime = newDateTime;
                  if (_endDateTime.isBefore(_startDateTime)) {
                    _endDateTime = _startDateTime.add(const Duration(hours: 1));
                  }
                });
              },
            ),
            const SizedBox(height: 12),

            _buildDateTimePickerSection(
              label: '⏳ 結束日期與時間',
              currentDateTime: _endDateTime,
              onDateTimeChanged: (newDateTime) {
                setState(() {
                  _endDateTime = newDateTime;
                });
              },
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _reminderSetting,
                    decoration: const InputDecoration(labelText: '提醒我'),
                    items: _reminderOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _reminderSetting = val ?? "不提醒"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _repeatSetting,
                    decoration: const InputDecoration(labelText: '重複'),
                    items: _repeatOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _repeatSetting = val ?? "不要"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _selectedGroupId,
              decoration: const InputDecoration(labelText: '指派給哪個組別'),
              items: widget.groupTabs.where((t) => t['id'] != 'all').map((t) {
                return DropdownMenuItem(
                  value: t['id'],
                  child: Text(t['name'] == 'personal' ? '個人（不公開）' : t['name']!),
                );
              }).toList(),
              onChanged: (val) {
  setState(() {
    _selectedGroupId = val ?? "personal";
    _assignedToUid = null;
    _assignedToEmail = null;
    _groupMembers = [];
    _canAssignTask = false;
  });
  _loadGroupMembersAndPermission();
},
            ),
            const SizedBox(height: 16),
            // ─── 指派組員（只有小組任務且有權限才顯示）──────────────────
if (_selectedGroupId != 'personal' && _canAssignTask) ...[
  const SizedBox(height: 16),
  DropdownButtonFormField<String>(
    value: _assignedToUid,
    decoration: const InputDecoration(
      labelText: '指派給',
      prefixIcon: Icon(Icons.person_pin_rounded),
    ),
    items: [
      const DropdownMenuItem(
        value: null,
        child: Text('不指派（所有人）'),
      ),
      ..._groupMembers.map((m) => DropdownMenuItem(
            value: m['uid'],
            child: Text(m['email']!),
          )),
    ],
    onChanged: (val) {
      setState(() {
        _assignedToUid = val;
        _assignedToEmail = val == null
            ? null
            : _groupMembers
                .firstWhere((m) => m['uid'] == val)['email'];
      });
    },
  ),
],
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '備註（選填）'),
            ),
            const SizedBox(height: 32),
            
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF203764),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _saveOrUpdateTodo,
              child: _isSaving 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isEditMode ? '確認修改任務' : '確認新增任務', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}