import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  Future<void> _handleNotificationAction({
    required BuildContext context,
    required String notifId,
    required String groupId,
    required String groupName,
    required bool canAssignTask,
    required bool accepted,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    batch.update(db.collection('notifications').doc(notifId), {
      'status': accepted ? 'accepted' : 'rejected',
      'isRead': true,
    });

    if (accepted) {
      batch.update(db.collection('groups').doc(groupId), {
        'memberIds': FieldValue.arrayUnion([currentUser.uid]),
        'pendingInvites': FieldValue.arrayRemove([currentUser.email]),
        'memberPermissions.${currentUser.uid}': {'canAssignTask': canAssignTask},
      });
      batch.update(db.collection('users').doc(currentUser.uid), {
        'groupIds': FieldValue.arrayUnion([groupId]),
      });
    } else {
      batch.update(db.collection('groups').doc(groupId), {
        'pendingInvites': FieldValue.arrayRemove([currentUser.email]),
      });
    }

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted ? '已加入「$groupName」！' : '已拒絕邀請'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleTaskAssign({
    required BuildContext context,
    required String notifId,
    required bool accepted,
  }) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notifId)
        .update({
      'status': accepted ? 'accepted' : 'rejected',
      'isRead': true,
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accepted ? '已接受任務' : '已拒絕任務'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _markAllAsRead(String userId) async {
    final db = FirebaseFirestore.instance;
    final unreadDocs = await db
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = db.batch();
    for (final doc in unreadDocs.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = (timestamp as Timestamp).toDate();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '剛剛';
      if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
      if (diff.inHours < 24) return '${diff.inHours} 小時前';
      if (diff.inDays < 7) return '${diff.inDays} 天前';
      return DateFormat('MM/dd').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Scaffold();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('通知中心'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () => _markAllAsRead(currentUser.uid),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('全部已讀'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('toUserId', isEqualTo: currentUser.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '目前沒有任何通知',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final notif = docs[index].data() as Map<String, dynamic>;
              final notifId = docs[index].id;
              final isRead = notif['isRead'] ?? false;
              final status = notif['status'] ?? 'pending';
              final isPending = status == 'pending';
              final type = notif['type'] ?? '';
              final timeStr = _formatTime(notif['createdAt']);

              return _NotificationTile(
                isRead: isRead,
                isPending: isPending,
                status: status,
                type: type,
                notif: notif,
                timeStr: timeStr,
                onAccept: () {
                  if (type == 'taskAssigned') {
                    _handleTaskAssign(
                      context: context,
                      notifId: notifId,
                      accepted: true,
                    );
                  } else {
                    _handleNotificationAction(
                      context: context,
                      notifId: notifId,
                      groupId: notif['groupId'] ?? '',
                      groupName: notif['groupName'] ?? '',
                      canAssignTask: notif['canAssignTask'] ?? false,
                      accepted: true,
                    );
                  }
                },
                onReject: () {
                  if (type == 'taskAssigned') {
                    _handleTaskAssign(
                      context: context,
                      notifId: notifId,
                      accepted: false,
                    );
                  } else {
                    _handleNotificationAction(
                      context: context,
                      notifId: notifId,
                      groupId: notif['groupId'] ?? '',
                      groupName: notif['groupName'] ?? '',
                      canAssignTask: notif['canAssignTask'] ?? false,
                      accepted: false,
                    );
                  }
                },
                onTap: isRead
                    ? null
                    : () {
                        FirebaseFirestore.instance
                            .collection('notifications')
                            .doc(notifId)
                            .update({'isRead': true});
                      },
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final bool isRead;
  final bool isPending;
  final String status;
  final String type;
  final Map<String, dynamic> notif;
  final String timeStr;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onTap;

  const _NotificationTile({
    required this.isRead,
    required this.isPending,
    required this.status,
    required this.type,
    required this.notif,
    required this.timeStr,
    required this.onAccept,
    required this.onReject,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (IconData tileIcon, Color iconBg, Color iconColor) = switch (type) {
      'groupInvite' => (Icons.group_add_rounded, Colors.blue.shade50, Colors.blue),
      'taskAssigned' => (Icons.assignment_rounded, Colors.orange.shade50, Colors.orange),
      _ => (Icons.notifications_rounded, Colors.grey.shade100, Colors.grey),
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isRead ? null : colorScheme.primaryContainer.withOpacity(0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(tileIcon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildTitle(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                      ),
                      if (!isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // groupInvite
                  if (type == 'groupInvite') ...[
                    _PermissionBadge(canAssignTask: notif['canAssignTask'] ?? false),
                    const SizedBox(height: 8),
                    if (isPending)
                      _buildActionButtons()
                    else
                      _StatusChip(status: status),
                  ],

                  // taskAssigned
                  if (type == 'taskAssigned') ...[
                    const SizedBox(height: 4),
                    if (isPending)
                      _buildActionButtons()
                    else
                      _StatusChip(status: status),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        FilledButton(
          onPressed: onAccept,
          style: FilledButton.styleFrom(
            minimumSize: const Size(72, 32),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text('接受'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: onReject,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(72, 32),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text('拒絕'),
        ),
      ],
    );
  }

  String _buildTitle() {
    return switch (type) {
      'groupInvite' =>
        '${notif['fromName'] ?? notif['fromEmail'] ?? '某人'} 邀請你加入「${notif['groupName'] ?? ''}」',
      'taskAssigned' =>
        '${notif['fromName'] ?? notif['fromEmail'] ?? '某人'} 指派了一個任務給你：${notif['taskName'] ?? '未命名任務'}',
      'permissionChanged' =>
        '你在「${notif['groupName'] ?? ''}」的權限已被更新',
      _ => notif['message'] ?? '你有一則新通知',
    };
  }
}

class _PermissionBadge extends StatelessWidget {
  final bool canAssignTask;
  const _PermissionBadge({required this.canAssignTask});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          canAssignTask ? Icons.task_alt_rounded : Icons.block_rounded,
          size: 13,
          color: canAssignTask ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 4),
        Text(
          canAssignTask ? '具有派發任務的權限' : '無派發任務的權限',
          style: TextStyle(
            fontSize: 12,
            color: canAssignTask ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isAccepted = status == 'accepted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAccepted ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAccepted ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAccepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 13,
            color: isAccepted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 4),
          Text(
            isAccepted ? '已接受' : '已拒絕',
            style: TextStyle(
              fontSize: 12,
              color: isAccepted ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}