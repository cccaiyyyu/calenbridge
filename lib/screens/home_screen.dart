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
      if (_isReordering)
        SizedBox(
          height: groups.length * 48.0,
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final allGroups = _groupTabs
                    .where(
                        (t) => t['id'] != 'all' && t['id'] != 'personal')
                    .toList();
                final movedGroup = allGroups.removeAt(oldIndex);
                allGroups.insert(newIndex, movedGroup);
                _groupTabs = [
                  {"id": "all", "name": "所有"},
                  {"id": "personal", "name": "個人"},
                  ...allGroups,
                ];
              });
            },
            children: groups.map((group) {
              final groupId = group['id']!;
              final groupName = group['name']!;
              return ListTile(
                key: ValueKey(groupId),
                dense: true,
                leading: const Icon(Icons.drag_handle_rounded,
                    size: 20, color: Colors.grey),
                title: Text(groupName,
                    style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
          ),
        )
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
                leading:
                    const Icon(Icons.group_rounded, size: 20),
                title: Text(groupName,
                    style: const TextStyle(fontSize: 13)),
                trailing: isCreator
                    ? IconButton(
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 16, color: Colors.grey),
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
                            setState(
                                () => _isLoadingGroups = true);
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

                              final todos = snapshot.data!.docs;

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
}