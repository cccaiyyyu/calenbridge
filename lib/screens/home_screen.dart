import 'dart:convert';

import 'package:calenbridge/screens/calendar_screen.dart';
import 'package:calenbridge/screens/completed_todos_screen.dart';
import 'package:calenbridge/screens/create_group_screen.dart';
import 'package:calenbridge/screens/group_management_screen.dart';
import 'package:calenbridge/screens/login_screen.dart';
import 'package:calenbridge/screens/notification_screen.dart';
import 'package:calenbridge/widgets/add_todo_bottom_sheet.dart';
import 'package:calenbridge/screens/register_info_screen.dart';
import 'package:calenbridge/services/google_calendar_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isReordering = false;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  String _selectedTab = "所有";
  List<Map<String, String>> _groupTabs = [
    {"id": "all", "name": "所有"},
    {"id": "personal", "name": "個人"},
  ];
  bool _isLoadingGroups = true;
  bool _isRailExpanded = false;

  bool _isSyncing = false;

  String _nickname = '';
  String _avatarUrl = '';
  int _avatarIndex = 0;
  bool _showEncouragement = false;
  String _encouragementText = '';

  static const List<String> _encouragements = [
    '太棒了！繼續保持！🎉',
    '你做到了！真厲害！✨',
    '完成一件，離目標更近！🚀',
    '很好！下一個也沒問題！💪',
    '效率滿點！給自己掌聲！👏',
  ];

  @override
  void initState() {
    super.initState();
    _fetchUserGroups();
  }

  // ✅ 修正 1：_isSyncing 狀態改由最外層 finally 統一管理
  // 對話框的確認按鈕不再重複重置，避免 loading 圈圈提早消失
  Future<void> _handleCalendarSync() async {
    setState(() { _isSyncing = true; });
    try {
      final List<Map<String, dynamic>> incomingEvents =
          await GoogleCalendarService().fetchTwoWeeksGoogleEvents();

      if (!mounted) return;

      if (incomingEvents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ℹ️ 近兩週的 Google 行程皆已同步過，無新行程需要導入。'),
            backgroundColor: Color(0xFF203764),
          ),
        );
        return;
      }

      List<bool> selectedFlags =
          List.generate(incomingEvents.length, (index) => true);

      // ✅ 修正 1：用 Completer 等待對話框完整結束後才執行後續邏輯
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    const Icon(Icons.playlist_add_check_rounded,
                        color: Color(0xFF203764), size: 28),
                    const SizedBox(width: 8),
                    const Text('選擇欲導入的待辦事項',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 350,
                  child: ListView.builder(
                    itemCount: incomingEvents.length,
                    itemBuilder: (context, index) {
                      final event = incomingEvents[index];
                      DateTime parsedTime =
                          DateTime.parse(event['startTime']);
                      String formattedTime =
                          "${parsedTime.month}/${parsedTime.day} "
                          "${parsedTime.hour.toString().padLeft(2, '0')}:"
                          "${parsedTime.minute.toString().padLeft(2, '0')}";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.grey.shade200),
                        ),
                        child: CheckboxListTile(
                          activeColor: const Color(0xFF203764),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          title: Text(
                            event['title'],
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '📅 時間: $formattedTime\n📝 備註: ${event['note']}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.5),
                          ),
                          isThreeLine: true,
                          value: selectedFlags[index],
                          onChanged: (bool? value) {
                            setDialogState(() {
                              selectedFlags[index] = value ?? false;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消',
                        style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF203764),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    onPressed: () async {
                      int importCount = 0;
                      try {
                        final String currentUserId =
                            _currentUser?.uid ?? '';

                        for (int i = 0; i < incomingEvents.length; i++) {
                          if (selectedFlags[i]) {
                            final targetEvent = incomingEvents[i];

                            // 同名同天防重複：找手動建立但缺 googleEventId 的任務
                            final titleCheck = await FirebaseFirestore
                                .instance
                                .collection('todos')
                                // ✅ 修正 4：改用 assignedTo 查詢，與 _buildTodoQuery 對齊
                                .where('assignedTo', isEqualTo: currentUserId)
                                .where('title',
                                    isEqualTo: targetEvent['title'])
                                .get();

                            QueryDocumentSnapshot? localMatchDoc;
                            for (var doc in titleCheck.docs) {
                                  final data = doc.data();
                              if (data['startTime']
                                      ?.toString()
                                      .substring(0, 10) ==
                                  targetEvent['startTime']
                                      .toString()
                                      .substring(0, 10)) {
                                localMatchDoc = doc;
                                break;
                              }
                            }

                            if (localMatchDoc != null) {
                              // 情況 A：補綁 googleEventId
                              // ✅ 修正 4：同時補上 assignedTo 確保欄位完整
                              await FirebaseFirestore.instance
                                  .collection('todos')
                                  .doc(localMatchDoc.id)
                                  .update({
                                'googleEventId':
                                    targetEvent['googleEventId'],
                                'assignedTo': currentUserId,
                              });
                              print(
                                  "🔗 成功融合！已為手動任務 [${targetEvent['title']}] 綁定 GoogleCalendar 憑證。");
                            } else {
                              // 情況 B：全新行程直接寫入
                              await FirebaseFirestore.instance
                                  .collection('todos')
                                  .add({
                                ...targetEvent,
                                'assignedTo': currentUserId,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            }
                            importCount++;
                          }
                        }

                        Navigator.pop(dialogContext);

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '🎉 同步大成功！已完美對齊並導入 $importCount 筆行程！'),
                            backgroundColor: const Color(0xFF203764),
                          ),
                        );
                      } catch (err) {
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('❌ 寫入資料庫失敗: $err'),
                              backgroundColor: Colors.red),
                        );
                      }
                      // ✅ 修正 1：移除對話框內的 finally setState，
                      // 改由外層 finally 統一重置 _isSyncing
                    },
                    child: const Text('確認導入',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('❌ 同步失敗，請重新確認授權！錯誤: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      // ✅ 修正 1：唯一的重置點，showDialog await 結束後才執行
      if (mounted) setState(() { _isSyncing = false; });
    }
  }

  Future<void> _fetchUserGroups() async {
    if (_currentUser == null) return;
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data() as Map<String, dynamic>;

        _nickname = userData['nickname'] ?? '';
        final raw = userData['avatarUrl'] ?? '';
        if (raw.startsWith('default_')) {
          _avatarIndex =
              int.tryParse(raw.replaceFirst('default_', '')) ?? 0;
          _avatarUrl = '';
        } else if (raw.startsWith('data:image')) {
          _avatarUrl = raw;
          _avatarIndex = 0;
        } else {
          _avatarUrl = '';
          _avatarIndex = 0;
        }

        List<dynamic> groupIds = userData['groupIds'] ?? [];
        List<Map<String, String>> fetchedTabs = [
          {"id": "all", "name": "所有"},
          {"id": "personal", "name": "個人"},
        ];

        if (groupIds.isNotEmpty) {
          QuerySnapshot groupDocs = await FirebaseFirestore.instance
              .collection('groups')
              .where(FieldPath.documentId,
                  whereIn: List<String>.from(groupIds))
              .get();

          for (var doc in groupDocs.docs) {
            final groupData = doc.data() as Map<String, dynamic>;
            fetchedTabs.add({
              "id": doc.id,
              "name": groupData['groupName'] ?? "未命名小組",
            });
          }
        }

        if (mounted) {
          setState(() {
            _groupTabs = fetchedTabs;
            _isLoadingGroups = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingGroups = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  Future<void> _goToCreateGroup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateGroupScreen()),
    );
    if (result == true) {
      setState(() => _isLoadingGroups = true);
      await _fetchUserGroups();
    }
  }

  void _goToNotifications() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
    setState(() => _isLoadingGroups = true);
    await _fetchUserGroups();
  }

  Query _buildTodoQuery() {
    Query query = FirebaseFirestore.instance.collection('todos');
    final String currentUserId = _currentUser?.uid ?? '';

    if (_selectedTab == "個人") {
      query = query
          .where('groupId', isEqualTo: 'personal')
          .where('assignedTo', isEqualTo: currentUserId);
    } else if (_selectedTab == "所有") {
      query = query.where('assignedTo', isEqualTo: currentUserId);
    } else {
      final targetGroup = _groupTabs.firstWhere(
        (t) => t['name'] == _selectedTab,
        orElse: () => {"id": ""},
      );
      query = query
          .where('groupId', isEqualTo: targetGroup['id'])
          .where('assignedTo', isEqualTo: currentUserId);
    }

    return query;
  }
  
  
  void _openTodoBottomSheet(
      {String? todoId, Map<String, dynamic>? initialData}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return AddTodoBottomSheet(
          currentSelectedTab: _selectedTab,
          groupTabs: _groupTabs,
          todoId: todoId,
          initialData: initialData,
          onTodoAdded: () => setState(() {}),
        );
      },
    );
  }

  // ✅ 修正 3：完成任務時，若有 googleEventId 同步刪除 Google 行事曆行程
  Future<void> _completeTodo(
      String todoId, Map<String, dynamic> todo) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    final completedRef = db.collection('completedTodos').doc();
    batch.set(completedRef, {
      ...todo,
      'originalTodoId': todoId,
      'completedAt': FieldValue.serverTimestamp(),
    });

    batch.delete(db.collection('todos').doc(todoId));

    await batch.commit();

    // ✅ 修正 3：Firestore 批次完成後，非同步刪除 Google 行事曆上對應行程
    final String? googleEventId = todo['googleEventId'] as String?;
    if (googleEventId != null && googleEventId.isNotEmpty) {
      try {
        await GoogleCalendarService()
            .deleteEventFromGoogleCalendar(googleEventId);
        print("【CalenBridge】✅ 任務完成，已同步移除 Google 行事曆行程：$googleEventId");
      } catch (e) {
        // Google 行事曆刪除失敗不阻斷主流程，僅 log 記錄
        print("【CalenBridge】⚠️ Google 行事曆刪除失敗（不影響本地完成）: $e");
      }
    }

    final text = _encouragements[
        DateTime.now().millisecondsSinceEpoch % _encouragements.length];
    if (mounted) {
      setState(() {
        _encouragementText = text;
        _showEncouragement = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showEncouragement = false);
      });
    }
  }

  Future<void> _handleSwitchAccount() async {
  try {
    // 1. 顯示載入中遮罩，避免使用者在非同步處理時重複點擊
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF203764)),
      ),
    );

    // 2. 先登出 Firebase 端
    await FirebaseAuth.instance.signOut();

    // 3. 🎯【網頁版核心關鍵】：建立與 Service 一致的 GoogleSignIn 實體，並執行 disconnect()
    final GoogleSignIn webGoogleSignIn = GoogleSignIn(
      clientId: '105456248073-7p478blrecon0e5v5b78sh6dfphb1obs.apps.googleusercontent.com',
      scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
    );

    // 🌐 網頁版不用 signOut()，用 disconnect() 才能徹底清除瀏覽器的自動登入狀態快取
    await webGoogleSignIn.disconnect();

    if (!mounted) return;
    Navigator.pop(context); // 關閉 Loading 彈窗

    // 4. 清除路由並導回登入頁，讓使用者看到全新的 Google 登入按鈕
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  } catch (e) {
    if (mounted) {
      Navigator.pop(context); // 發生錯誤時也要關閉 Loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切換帳號失敗: $e')),
      );
    }
  }
}

  String _formatDateTimeString(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '未設定截止時間';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  List<Widget> _buildGroupList() {
    final groups = _groupTabs
        .where((t) => t['id'] != 'all' && t['id'] != 'personal')
        .toList();

    if (groups.isEmpty) return [];

    return [
      const Divider(indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('你的小組',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            IconButton(
              icon: Icon(
                _isReordering
                    ? Icons.check_rounded
                    : Icons.edit_rounded,
                size: 16,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _isReordering = !_isReordering),
              tooltip: _isReordering ? '完成排序' : '排列小組',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
      
      // ✏️ 當點擊「那支筆」進入編輯模式時
      if (_isReordering) ...[
        ...List.generate(groups.length, (index) {
          final group = groups[index];
          final groupId = group['id']!;
          final groupName = group['name']!;

          // 封裝一模一樣的標準 ListTile
          Widget buildGroupTile({bool isFeedback = false}) {
            return ListTile(
              dense: true,
              // 如果是跟著滑鼠跑的實體，文字可以加粗，看起來更有「抓起來」的質感
              leading: const Icon(Icons.drag_handle_rounded, size: 20, color: Colors.grey),
              title: Text(
                groupName, 
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: isFeedback ? FontWeight.bold : FontWeight.normal,
                  decoration: TextDecoration.none, // 防止 Web 端跑出黃色底線
                  color: Colors.black,
                )
              ),
            );
          }

          return DragTarget<String>(
            onWillAcceptWithDetails: (details) => details.data != groupId,
            onAcceptWithDetails: (details) {
              final draggedId = details.data;
              setState(() {
                final allGroups = _groupTabs
                    .where((t) => t['id'] != 'all' && t['id'] != 'personal')
                    .toList();
                
                final oldIdx = allGroups.indexWhere((t) => t['id'] == draggedId);
                final newIdx = allGroups.indexWhere((t) => t['id'] == groupId);
                
                if (oldIdx != -1 && newIdx != -1) {
                  final movedGroup = allGroups.removeAt(oldIdx);
                  allGroups.insert(newIdx, movedGroup);
                  _groupTabs = [
                    {"id": "all", "name": "所有"},
                    {"id": "personal", "name": "個人"},
                    ...allGroups,
                  ];
                }
              });
            },
            builder: (context, candidateData, rejectedData) {
              return Draggable<String>(
                data: groupId,
                
                // 🎯【跟著游標跑的實體】：把整塊清單直接拔走！使用 Material 確保擁有白色實體背景，絕無灰色影子
                feedback: Material(
                  elevation: 4, // 加上一點點陰影，讓它看起來真的浮在空中
                  color: Colors.white, // 與你的側邊欄背景一樣是純白實心
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 200, // 限制寬度跟側邊欄差不多，拖曳時才不會散開
                    child: buildGroupTile(isFeedback: true),
                  ),
                ),
                
                // 🎯【拔走後，留在原地的外觀】：設為完全透明的空間，這樣就不會有殘留分身
                childWhenDragging: Opacity(
                  opacity: 0.0,
                  child: buildGroupTile(),
                ),
                
                // 平常沒有拖曳時顯示的外觀（限定按住左邊兩條線才能拖）
                child: buildGroupTile(),
              );
            },
          );
        }).toList(),
      ]
      
      // 🔓 平常正常狀態（沒點筆時）：維持最原本的樣子
      else
        ...groups.map((group) {
          final groupId = group['id']!;
          final groupName = group['name']!;

          return FutureBuilder<DocumentSnapshot>(
            key: ValueKey(groupId),
            future: FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId)
                .get(),
            builder: (context, snapshot) {
              final isCreator = snapshot.hasData &&
                  (snapshot.data!.data()
                          as Map<String, dynamic>?)?['creatorUid'] ==
                      _currentUser?.uid;

              return ListTile(
                dense: true,
                leading: const Icon(Icons.group_rounded, size: 20),
                title: Text(groupName, style: const TextStyle(fontSize: 13)),
                trailing: isCreator
                    ? IconButton(
                        icon: const Icon(Icons.more_vert_rounded, size: 16, color: Colors.grey),
                        onPressed: () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupManagementScreen(
                                groupId: groupId,
                                groupName: groupName,
                              ),
                            ),
                          );
                          if (result == true) {
                            setState(() => _isLoadingGroups = true);
                            await _fetchUserGroups();
                          }
                        },
                      )
                    : null,
                onTap: () {
                  setState(() {
                    _selectedTab = groupName;
                    _isRailExpanded = false;
                  });
                },
              );
            },
          );
        }).toList(),
    ];
}
  
  Widget _buildUnreadBadge(Widget child) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('toUserId', isEqualTo: _currentUser?.uid)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (count > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                      minWidth: 16, minHeight: 16),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCollapsedRail() {
    return Container(
      width: 56,
      color: Theme.of(context).navigationRailTheme.backgroundColor ??
          Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 16),
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 28),
            onPressed: () => setState(() => _isRailExpanded = true),
            tooltip: '展開選單',
          ),
        ],
      ),
    );
  }
  
  Widget _buildAvatar({double radius = 22}) {
    if (_avatarUrl.isNotEmpty && _avatarUrl.startsWith('data:image')) {
      final base64Str = _avatarUrl.split(',').last;
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(base64Decode(base64Str)),
      );
    }

    if (_avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(_avatarUrl),
      );
    }

    const icons = [
      Icons.face_rounded,
      Icons.sentiment_very_satisfied_rounded,
      Icons.workspace_premium_rounded,
      Icons.star_rounded,
      Icons.pets_rounded,
      Icons.bolt_rounded,
    ];
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE6E0F8),
      child: Icon(
        icons[_avatarIndex.clamp(0, icons.length - 1)],
        size: radius,
        color: const Color(0xFF4A4458),
      ),
    );
  }

  Future<void> _goToEditProfile() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const RegisterInfoScreen(isEditing: true),
      ),
    );
    if (result == true) {
      setState(() => _isLoadingGroups = true);
      await _fetchUserGroups();
    }
  }

  Widget _buildExpandedRail() {
    final email = _currentUser?.email ?? '';

    return Container(
      width: 200,
      color: Theme.of(context).navigationRailTheme.backgroundColor ??
          Theme.of(context).colorScheme.surface,
      child: ListView(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              icon: const Icon(Icons.menu_open_rounded, size: 28),
              onPressed: () =>
                  setState(() => _isRailExpanded = false),
              tooltip: '收合選單',
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _goToEditProfile,
                  child: Stack(
                    children: [
                      _buildAvatar(radius: 22),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4A4458),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit,
                              size: 9, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nickname.isNotEmpty ? _nickname : '未設定暱稱',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(indent: 16, endIndent: 16),
          _buildUnreadBadge(
            ListTile(
              leading: const Icon(Icons.notifications_rounded),
              title: const Text('通知中心'),
              onTap: _goToNotifications,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded),
            title: const Text('行事曆'),
            onTap: () {
              setState(() => _isRailExpanded = false);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CalendarScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_rounded),
            title: const Text('建立小組'),
            onTap: () {
              setState(() => _isRailExpanded = false);
              _goToCreateGroup();
            },
          ),
          ..._buildGroupList(),
         
          const Divider(indent: 16, endIndent: 16),
           _buildTrashTarget(),
          const SizedBox(height: 24),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.check_circle_outline_rounded),
            title: const Text('已完成的任務'),
            onTap: () {
              setState(() => _isRailExpanded = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CompletedTodosScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.switch_account_rounded),
            title: const Text('切換帳號'),
            onTap: _handleSwitchAccount,
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTodoBottomSheet(),
        backgroundColor: const Color(0xFFE6E0F8),
        child: const Icon(Icons.add, color: Color(0xFF1D1B20), size: 30),
      ),
      body: Stack(
        children: [
          Row(
            children: [
              SizedBox(
                width: _isRailExpanded ? 200 : 56,
                child: _isRailExpanded
                    ? _buildExpandedRail()
                    : _buildCollapsedRail(),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _isLoadingGroups
                            ? const SizedBox(
                                height: 40,
                                child: Center(
                                    child: CircularProgressIndicator()),
                              )
                            : SizedBox(
                                height: 40,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _groupTabs.length,
                                  itemBuilder: (context, index) {
                                    final tabName =
                                        _groupTabs[index]['name']!;
                                    final isSelected =
                                        _selectedTab == tabName;
                                    return Container(
                                      margin: const EdgeInsets.only(
                                          right: 8),
                                      child: ChoiceChip(
                                        label: Text(tabName),
                                        selected: isSelected,
                                        onSelected: (bool selected) {
                                          if (selected) {
                                            setState(() =>
                                                _selectedTab = tabName);
                                          }
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '待辦事項',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                            ),
                            _isSyncing
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Color(0xFF203764)),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: _isSyncing
                                        ? null
                                        : _handleCalendarSync,
                                    icon: const Icon(
                                        Icons.sync_rounded,
                                        size: 18,
                                        color: Colors.white),
                                    label: const Text('同步',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight:
                                                FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF203764),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10),
                                    ),
                                  ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: StreamBuilder<QuerySnapshot>(
                            stream: _buildTodoQuery().snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return const Center(
                                  child: Text('目前沒有待辦事項喔！',
                                      style:
                                          TextStyle(color: Colors.grey)),
                                );
                              }

                              // 🎯 ✨【核心排序修正點 1】：將快照資料轉為可排序的複製列表
                              final todos = List.from(snapshot.data!.docs);

                              // 🎯 ✨【核心排序修正點 2】：進行時間升序排序（5號 -> 6號 -> 7號）
                              todos.sort((a, b) {
                                final aData = a.data() as Map<String, dynamic>;
                                final bData = b.data() as Map<String, dynamic>;

                                // 取得各自的開始時間 (如果沒有欄位，預設為空字串)
                                final String aTime = aData['startTime']?.toString() ?? '';
                                final String bTime = bData['startTime']?.toString() ?? '';

                                // 防呆處理：沒有設定時間的事項往後排
                                if (aTime.isEmpty) return 1;
                                if (bTime.isEmpty) return -1;

                                // ISO 8601 格式字串直接比大小，結果等同於時間排序
                                return aTime.compareTo(bTime);
                              });

                              return ListView.builder(
                                itemCount: todos.length,
                                itemBuilder: (context, index) {
                                  final doc = todos[index];
                                  final todo = doc.data()
                                      as Map<String, dynamic>;

                                  return Card(
                                    margin: const EdgeInsets.only(
                                        bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      side: BorderSide(
                                          color: Colors.grey.shade300),
                                      borderRadius:
                                          BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      onTap: () => _openTodoBottomSheet(
                                        todoId: doc.id,
                                        initialData: todo,
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8),
                                        leading: GestureDetector(
                                          onTap: () => _completeTodo(
                                              doc.id, todo),
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color:
                                                    Colors.grey.shade400,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          todo['title'] ?? '未命名',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          '截止時間: ${_formatDateTimeString(todo['endTime'])}',
                                          style: TextStyle(
                                              color:
                                                  Colors.grey.shade600),
                                        ),
                                        trailing: Chip(
                                          label: Text(
                                            todo['groupId'] == 'personal'
                                                ? '個人'
                                                : '小組',
                                            style: const TextStyle(
                                                fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showEncouragement)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showEncouragement ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A4458),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _encouragementText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_isRailExpanded)
            Positioned(
              left: 200,
              top: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: () => setState(() => _isRailExpanded = false),
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
        ],
      ),
    );
    
  }
  Future<void> _showExitGroupDialog(BuildContext context, String groupId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final db = FirebaseFirestore.instance;

    // 1. 顯示載入圈圈
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF203764))),
    );

    try {
      // 抓取小組資訊
      final groupDoc = await db.collection('groups').doc(groupId).get();
      if (context.mounted) Navigator.pop(context); // 關閉載入圈圈

      if (!groupDoc.exists) return;

      final groupData = groupDoc.data() as Map<String, dynamic>;
      final String creatorUid = groupData['creatorUid'] ?? ''; 
      final String groupName = groupData['name'] ?? '此小組';

      // 安全檢查：建立者不能退出
      if (currentUser.uid == creatorUid) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('無法退出'),
              content: Text('你是「$groupName」的建立者，無法直接退出！若要解散請點擊小組旁的設定。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('我知道了'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 2. 第一階段：確認是否退出小組
      if (context.mounted) {
        final bool? confirmExit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('退出小組確認'),
            content: Text('你確定要退出小組「$groupName」嗎？\n退出後將無法查看此小組的任何資訊。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('確認退出'),
              ),
            ],
          ),
        );

        // 如果點取消或點外面關閉，直接結束
        if (confirmExit != true) return;
      }

      // 3. 第二階段：檢查該使用者在此小組內是否有「未完成的待辦事項」
      // 💡 註：請確認你的 Firestore todos 欄位名稱是否為 groupId, assigneeId, isCompleted
      final todoQuery = await db.collection('todos')
                .where('groupId', isEqualTo: groupId)
                .where('assigneeId', isEqualTo: currentUser.uid)
                .where('isCompleted', isEqualTo: false)

          .get();

      bool migrateToPersonal = false;

      // 如果有未完成的待辦事項，跳出詢問移轉對話框
      if (todoQuery.docs.isNotEmpty && context.mounted) {
        final int todoCount = todoQuery.docs.length;
        
        final String? actionResult = await showDialog<String>(
          context: context,
          barrierDismissible: false, // 強迫選擇
          builder: (dialogContext) => AlertDialog(
            title: const Text('移轉待辦事項'),
            content: Text('偵測到你在「$groupName」中還有 $todoCount 項「未完成」的待辦事項。\n\n請問需要將這些事項移轉到你的「個人待辦事項」中嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'leave'),
                child: const Text('不用，留在小組', style: TextStyle(color: Colors.red)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF203764)),
                onPressed: () => Navigator.pop(dialogContext, 'migrate'),
                child: const Text('要，移轉至個人'),
              ),
            ],
          ),
        );

        if (actionResult == 'migrate') {
          migrateToPersonal = true;
        }
      }

      // 4. 第三階段：處理資料庫變更
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF203764))),
        );
      }

      final batch = db.batch();

      // 如果使用者有未完成事項
      if (todoQuery.docs.isNotEmpty) {
        if (migrateToPersonal) {
          // 選擇移轉：更新 groupId 為 'personal'
          for (var doc in todoQuery.docs) {
            batch.update(doc.reference, {'groupId': 'personal'});
          }
        } else {
          // 選擇不移轉：直接刪除這些未完成的事項
          for (var doc in todoQuery.docs) {
            batch.delete(doc.reference);
          }
        }
      }

      // 執行退出群組邏輯
      batch.update(db.collection('groups').doc(groupId), {
        'memberIds': FieldValue.arrayRemove([currentUser.uid]),
      });
      batch.update(db.collection('users').doc(currentUser.uid), {
        'groupIds': FieldValue.arrayRemove([groupId]),
      });

      await batch.commit();

      if (context.mounted) Navigator.pop(context); // 關閉載入圈圈

      setState(() => _isLoadingGroups = true);
      await _fetchUserGroups();

      // 5. 提示訊息
      if (context.mounted) {
        String successMsg = migrateToPersonal 
            ? '已退出小組，並將未完成事項移至個人項目。' 
            : '已退出小組，並刪除了你在該組內未完成的任務。';
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMsg), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      // 發生任何錯誤時的保險關對話框機制
      if (context.mounted) Navigator.pop(context);
      print("退出群組或移轉事項失敗: $e");
    }
  }
  // ... 這裡是你 HomeScreen 裡面原本就有的其他各種 method (例如 _buildTodoQuery 或是 _fetchUserGroups)

  // =========================================================
  // 🎯 把這兩段「完全複製」，然後直接貼在 HomeScreen class 結束前的這個空白處：
  // =========================================================
  Widget _buildTrashTarget() {
    return DragTarget<String>(
      // 🎯 核心控制：只有在點了編輯筆 (_isReordering 為 true) 時，才接受拖曳進來的物件
      onWillAcceptWithDetails: (details) => _isReordering,
      onAcceptWithDetails: (details) {
        final droppedGroupId = details.data;
        _showExitGroupDialog(context, droppedGroupId);
      },
      builder: (context, candidateData, rejectedData) {
        // 當滑鼠拖曳物件懸浮在上方，且當前處於編輯狀態
        final bool isHovering = candidateData.isNotEmpty && _isReordering;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            // 平常是極淡的灰色，拖曳上去時變成醒目的紅色警告
            color: isHovering ? Colors.red.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovering 
                  ? Colors.red.shade300 
                  : (_isReordering ? Colors.amber.shade300 : Colors.grey.shade200),
              width: isHovering ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isHovering 
                    ? Icons.delete_forever_rounded 
                    : (_isReordering ? Icons.delete_sweep_rounded : Icons.delete_outline_rounded),
                color: isHovering 
                    ? Colors.red 
                    : (_isReordering ? Colors.amber.shade700 : Colors.grey.shade400),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isHovering 
                    ? '放開滑鼠以退出' 
                    : (_isReordering ? '拖曳至此退出小組' : '退出小組功能已關閉'),
                style: TextStyle(
                  color: isHovering 
                      ? Colors.red.shade700 
                      : (_isReordering ? Colors.amber.shade900 : Colors.grey.shade500),
                  fontSize: 12,
                  fontWeight: isHovering || _isReordering ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  

} 
