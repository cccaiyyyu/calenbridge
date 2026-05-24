import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:calenbridge/screens/login_screen.dart';
import 'package:calenbridge/screens/notification_screen.dart';
import 'package:calenbridge/screens/create_group_screen.dart';
import 'package:calenbridge/widgets/add_todo_bottom_sheet.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:calenbridge/screens/group_management_screen.dart';
import 'package:calenbridge/screens/completed_todos_screen.dart';



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
  bool _isRailExpanded = false; // ← 控制側邊欄展開/收合

  String _nickname = '';
  String _avatarUrl = '';
  int _avatarIndex = 0;
static const List<IconData> _avatarIcons = [
  Icons.face_rounded,
  Icons.sentiment_very_satisfied_rounded,
  Icons.workspace_premium_rounded,
  Icons.star_rounded,
  Icons.pets_rounded,
  Icons.bolt_rounded,
];
bool _showEncouragement = false;
String _encouragementText = '';

static const List<String> _encouragements = [
  '太棒了！繼續保持！🎉',
  '你做到了！真厲害！✨',
  '完成一件，離目標更近！🚀',
  '很好！下一個也沒問題！💪',
  '效率滿點！給自己掌聲！👏',
];
  void _openGroupSettings(String groupId, String groupName) async {
  // 將資料傳遞給 GroupManagementScreen
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => GroupManagementScreen(
        groupId: groupId,
        groupName: groupName,
      ),
    ),
  );

  // 如果編輯頁回傳了 true (表示有更動)，則刷新 UI
  if (result == true) {
    await _fetchUserGroups(); 
    if (mounted) setState(() {});
  }
}
  @override
  void initState() {
    super.initState();
    _fetchUserGroups();

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

      // ← 正確位置：在 userData 讀取後
      _nickname = userData['nickname'] ?? '';
      final raw = userData['avatarUrl'] ?? '';
if (raw.startsWith('default_')) {
  // 預設 icon，取出數字部分
  _avatarIndex = int.tryParse(raw.replaceFirst('default_', '')) ?? 0;
  _avatarUrl = '';
} else if (raw.startsWith('data:image')) {
  // Base64 自訂圖片
  _avatarUrl = raw;
  _avatarIndex = 0;
} else {
  // 其他（空值或舊格式）
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
            .where( FieldPath.documentId,
          whereIn: List<String>.from(groupIds),)
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
  } catch (e) {
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

 

  void _goToNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
  }

  Query _buildTodoQuery() {
    Query query = FirebaseFirestore.instance
        .collection('todos')
        .where('ownerUid', isEqualTo: _currentUser?.uid);

    if (_selectedTab == "個人") {
      query = query.where('groupId', isEqualTo: 'personal');
    } else if (_selectedTab != "所有") {
      final targetGroup = _groupTabs.firstWhere(
        (t) => t['name'] == _selectedTab,
        orElse: () => {"id": ""},
      );
      query = query.where('groupId', isEqualTo: targetGroup['id']);
    }
    return query;
  }

  void _openTodoBottomSheet({String? todoId, Map<String, dynamic>? initialData}) {
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
  Future<void> _completeTodo(String todoId, Map<String, dynamic> todo) async {
  final db = FirebaseFirestore.instance;
  final batch = db.batch();

  // 寫入 completedTodos
  final completedRef = db.collection('completedTodos').doc();
  batch.set(completedRef, {
    ...todo,
    'originalTodoId': todoId,
    'completedAt': FieldValue.serverTimestamp(),
  });

  // 刪除原本的 todo
  batch.delete(db.collection('todos').doc(todoId));

  await batch.commit();

  // 顯示鼓勵小語
  final text = _encouragements[
      DateTime.now().millisecondsSinceEpoch % _encouragements.length];
  if (mounted) {
    setState(() {
      _encouragementText = text;
      _showEncouragement = true;
    });
    // 2 秒後消失
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showEncouragement = false);
    });
  }
}
  Future<void> _handleSignOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
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
          const Text('你的小組', style: TextStyle(fontSize: 12, color: Colors.grey)),
          // ← 排序按鈕
          IconButton(
            icon: Icon(
              _isReordering ? Icons.check_rounded : Icons.edit_rounded,
              size: 16,
              color: Colors.grey,
            ),
            onPressed: () => setState(() => _isReordering = !_isReordering),
            tooltip: _isReordering ? '完成排序' : '排列小組',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    ),
    if (_isReordering)
      // 排序模式：可拖曳
      SizedBox(
        height: groups.length * 48.0,
        child: ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              // 在 _groupTabs 裡找到對應的實際 index
              final allGroups = _groupTabs
                  .where((t) => t['id'] != 'all' && t['id'] != 'personal')
                  .toList();
              final movedGroup = allGroups.removeAt(oldIndex);
              allGroups.insert(newIndex, movedGroup);
              // 重建 _groupTabs 保留 "所有" 和 "個人" 在前面
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
              leading: const Icon(Icons.drag_handle_rounded, size: 20, color: Colors.grey),
              title: Text(groupName, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
        ),
      )
    else
      // 一般模式：點擊切換 tab，⋮ 進管理頁
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
                (snapshot.data!.data() as Map<String, dynamic>?)?['creatorUid'] ==
                    _currentUser?.uid;

            return ListTile(
              dense: true,
              leading: const Icon(Icons.group_rounded, size: 20),
              title: Text(groupName, style: const TextStyle(fontSize: 13)),
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
  // ─── 未讀通知 badge ────────────────────────────────────────────
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
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
  
  // ─── 收合時只顯示三條線的窄側邊欄 ─────────────────────────────
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
  // ← 修改三放這裡
  Widget _buildAvatar({double radius = 22}) {
    if (_avatarUrl.isNotEmpty && _avatarUrl.startsWith('data:image')) {
    final base64Str = _avatarUrl.split(',').last;
    return CircleAvatar(
      radius: radius,
      backgroundImage: MemoryImage(base64Decode(base64Str)),
    );
  }
  // 一般 URL 圖片
  if (_avatarUrl.isNotEmpty) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(_avatarUrl),
    );
  }
  // 預設 icon
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

  // ─── 展開後的側邊欄 ────────────────────────────────────────────
  Widget _buildExpandedRail() {
    
  final email = _currentUser?.email ?? '';
  final initials = _nickname.isNotEmpty ? _nickname[0].toUpperCase() : '?';

  return Container(
    width: 200,
    color: Theme.of(context).navigationRailTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface,
    child: ListView(
      children: [
        const SizedBox(height: 16),
        // 收合按鈕
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconButton(
            icon: const Icon(Icons.menu_open_rounded, size: 28),
            onPressed: () => setState(() => _isRailExpanded = false),
            tooltip: '收合選單',
          ),
        ),
        const SizedBox(height: 8),

        // ─── 用戶資訊卡 ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 頭像
             _buildAvatar(radius: 22),
              const SizedBox(width: 10),
              // 暱稱 + gmail
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

        // 通知
        _buildUnreadBadge(
          ListTile(
            leading: const Icon(Icons.notifications_rounded),
            title: const Text('通知中心'),
            onTap: _goToNotifications,
          ),
        ),
        // 建立小組
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
        // 首頁
        ListTile(
          leading: const Icon(Icons.home_rounded),
          title: const Text('首頁'),
          selected: true,
          onTap: () => setState(() => _isRailExpanded = false),
        ),
        const SizedBox(height: 24),
        const Divider(indent: 16, endIndent: 16),
ListTile(
  leading: const Icon(Icons.check_circle_outline_rounded),
  title: const Text('已完成的任務'),
  onTap: () {
    setState(() => _isRailExpanded = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompletedTodosScreen()),
    );
  },
),
// 登出
ListTile(
  leading: const Icon(Icons.logout_rounded),
  title: const Text('登出'),
  onTap: _handleSignOut,
),
        const SizedBox(height: 16),
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
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : SizedBox(
                          height: 40,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _groupTabs.length,
                            itemBuilder: (context, index) {
                              final tabName = _groupTabs[index]['name']!;
                              final isSelected = _selectedTab == tabName;
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(tabName),
                                  selected: isSelected,
                                  onSelected: (bool selected) {
                                    if (selected) {
                                      setState(() => _selectedTab = tabName);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                  const SizedBox(height: 24),
                  const Text(
                    '待辦事項',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                                style: TextStyle(color: Colors.grey)),
                          );
                        }
                        // ─── 已完成入口 ───────────────────────────────────────────────
                        final todos = snapshot.data!.docs;

                        return ListView.builder(
                         itemCount: todos.length,
                          itemBuilder: (context, index) {
                        final doc = todos[index];
                           
                            final todo = doc.data() as Map<String, dynamic>;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _openTodoBottomSheet(
                                  todoId: doc.id,
                                  initialData: todo,
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  leading: GestureDetector(
  onTap: () => _completeTodo(doc.id, todo),
  child: Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.grey.shade400,
        width: 2,
      ),
    ),
  ),
),
                                  title: Text(
                                    todo['title'] ?? '未命名',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '截止時間: ${_formatDateTimeString(todo['endTime'])}',
                                    style:
                                        TextStyle(color: Colors.grey.shade600),
                                  ),
                                  trailing: Chip(
                                    label: Text(
                                      todo['groupId'] == 'personal'
                                          ? '個人'
                                          : '小組',
                                      style: const TextStyle(fontSize: 12),
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
    // ─── 鼓勵小語浮層 ────────────────────────────────────────────
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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