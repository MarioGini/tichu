import 'package:flutter/material.dart';
import 'routes/routeA.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      routes: {'routeA': (context) => RouteA()},
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _username = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Routing & Navigation"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Enter user name'),
            Padding(
              padding: EdgeInsets.all(1.0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: "User name",
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (String str) {
                  setState(() {
                    _username = str;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => RouteA()),
                    );
                  });
                },
              ),
            ),
            Text(_username),
          ],
        ),
      ),
    );
  }
}
