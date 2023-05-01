import 'package:flutter/material.dart';

class GetCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(/*body: _buildBody(context)*/);
  }

  // Widget _buildBody(BuildContext context) {
  //   return StreamBuilder<QuerySnapshot>(
  //     stream: Firestore.instance.collection('baby').snapshots(),
  //     builder: (context, snapshot) {
  //       if (!snapshot.hasData) return LinearProgressIndicator();

  //       return _buildList(context, snapshot.data.documents);
  //     },
  //   );
  // }

  // Widget _buildList(BuildContext context, List<DocumentSnapshot> snapshot) {
  //   return ListView(
  //     padding: const EdgeInsets.only(top: 20.0),
  //     //children: snapshot.map((data) =>_buildListItem(context, data)).toList(),
  //   );
  // }

  // Widget _buildListItem(BuildContext context, DocumentSnapshot data) {
  //   final record = Record.fromSnapshot(data);

//     return Padding(
//       key: ValueKey(record.name),
//       padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
//       child: Container(
//         decoration: BoxDecoration(
//           border: Border.all(color: Colors.grey),
//           borderRadius: BorderRadius.circular(5.0),
//         ),
//         child: ListTile(
//           title: Text(record.name),
//           trailing: Text(record.votes.toString()),
//           onTap: () {
//             //record.reference.updateData({'votes': FieldValue.increment(1)});
//           },
//         ),
//       ),
//     );
//   }
}

class Record {
  final String name;
  final int votes;

  Record.fromMap(Map<String, dynamic> map)
      : name = map['name'],
        votes = map['votes'];

  // Record.fromSnapshot(DocumentSnapshot snapshot)
  //: this.fromMap(snapshot.data, reference: snapshot.reference);

  @override
  String toString() => 'Record<$name:$votes>';
}
