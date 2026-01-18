import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportTicketsScreen extends StatelessWidget {
  const SupportTicketsScreen({Key? key}) : super(key: key);

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.orange;
      case 'closed':
        return Colors.green;
      case 'pending':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Support Tickets"),
        backgroundColor: primary,
        centerTitle: true,
      ),
      body: user == null
          ? const Center(child: Text("Please login to view tickets"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('support_tickets')
                  .where('userId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No support tickets found",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                /// ✅ FILTER OUT CLOSED TICKETS HERE
                final tickets = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return (data['status'] ?? '').toString().toLowerCase() !=
                      'closed';
                }).toList();

                if (tickets.isEmpty) {
                  return const Center(
                    child: Text(
                      "No active tickets found",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: tickets.length,
                  itemBuilder: (context, index) {
                    final data = tickets[index].data() as Map<String, dynamic>;

                    final ticketNo = data['ticketNumber'] ?? 'N/A';
                    final name = data['name'] ?? '';
                    final mobile = data['mobile'] ?? '';
                    final issue = data['issue'] ?? '';
                    final status = data['status'] ?? 'Open';

                    final timestamp = data['createdAt'];
                    String dateText = '';
                    if (timestamp != null) {
                      dateText = DateFormat(
                        'dd MMM yyyy, hh:mm a',
                      ).format(timestamp.toDate());
                    }

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ticket No + Status
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ticketNo,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      status,
                                    ).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            Text("👤 Name: $name"),
                            Text("📞 Mobile: $mobile"),
                            const SizedBox(height: 6),

                            Text(
                              issue,
                              style: const TextStyle(color: Colors.black87),
                            ),

                            if (dateText.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                dateText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
