import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  final String rideId;

  const ChatScreen({
    super.key,
    required this.rideId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final TextEditingController messageController = TextEditingController();
  final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> sendMessage() async {
    String text = messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;

    await firestore
        .collection('rides')
        .doc(widget.rideId)
        .collection('messages')
        .add({
      'message': text,
      'senderId': currentUser?.uid ?? 'ANONYMOUS',
      'senderEmail': currentUser?.email ?? 'anonymous@aeroride.com',
      'createdAt': FieldValue.serverTimestamp(), // Better than Timestamp.now() for live sync!
    });

    messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Ride Chat",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // 1. Live Chat Stream Area
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection('rides')
                  .doc(widget.rideId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true) // Set to true so new messages pop up at the bottom smoothly
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.green),
                  );
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      "No messages yet. Say hello!",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true, // Reverses scroll physics so the chat behaves like WhatsApp/Telegram
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    
                    // Core Alignment Rule: Am I the person who sent this specific message?
                    bool isMe = data['senderId'] == currentUid;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75, // Stop bubbles stretching full screen
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.green : Colors.grey.shade200,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 0),  // Sharp tail design
                            bottomRight: Radius.circular(isMe ? 0 : 16), // Sharp tail design
                          ),
                        ),
                        child: Text(
                          data['message'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 2. Bottom Typing Controls Panel
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                )
              ]
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: "Type message...",
                      hintStyle: const TextStyle(color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.green,
                  radius: 22,
                  child: IconButton(
                    onPressed: sendMessage,
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
/*import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {

  final String rideId;

  const ChatScreen({
    super.key,
    required this.rideId,
  });

  @override
  State<ChatScreen> createState() =>
      _ChatScreenState();
}

class _ChatScreenState
    extends State<ChatScreen> {

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final TextEditingController
      messageController =
          TextEditingController();

  Future<void> sendMessage() async {

  if (messageController.text
      .trim()
      .isEmpty) {
    return;
  }

  final currentUser =
      FirebaseAuth.instance.currentUser;

  await firestore
      .collection('rides')
      .doc(widget.rideId)
      .collection('messages')
      .add({

    'message':
        messageController.text.trim(),

    'senderId':
        currentUser?.uid,

    'senderEmail':
        currentUser?.email,

    'createdAt':
        Timestamp.now(),
  });

  messageController.clear();
}

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Ride Chat",
        ),
      ),

      body: Column(

        children: [

          Expanded(

            child:
                StreamBuilder<QuerySnapshot>(

              stream: firestore
                  .collection('rides')
                  .doc(widget.rideId)
                  .collection('messages')
                  .orderBy(
                    'createdAt',
                  )
                  .snapshots(),

              builder:
                  (context, snapshot) {

                if (!snapshot.hasData) {

                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }

                final messages =
                    snapshot.data!.docs;

                return ListView.builder(

                  itemCount:
                      messages.length,

                  itemBuilder: (context, index) {

  final data =
      messages[index].data()
          as Map<String, dynamic>;

  return ListTile(

    title: Text(
      data['message'],
    ),

    subtitle: Text(
      data['createdAt'] != null
          ? data['createdAt']
              .toDate()
              .toString()
          : '',
    ),
  );
},
                  
                );
              },
            ),
          ),

          Padding(

            padding:
                const EdgeInsets.all(10),

            child: Row(

              children: [

                Expanded(

                  child: TextField(

                    controller:
                        messageController,

                    decoration:
                        const InputDecoration(

                      hintText:
                          "Type message...",
                    ),
                  ),
                ),

                IconButton(

                  onPressed:
                      sendMessage,

                  icon: const Icon(
                    Icons.send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}*/