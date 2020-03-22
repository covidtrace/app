import 'package:flutter/material.dart';

class Settings extends StatefulWidget {
  Settings({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => SettingsState();
}

class SettingsState extends State<Settings> {
  var _gender;
  var _age;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: Text('Settings'),
            leading: IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  Navigator.pop(context);
                })),
        body: Padding(
            padding: EdgeInsets.all(20),
            child: Column(children: [
              DropdownButton(
                  value: _age,
                  onChanged: (value) => setState(() => _age = value),
                  hint: Text('Age'),
                  isExpanded: true,
                  items: [
                    '< 2 years',
                    '2 - 4',
                    '5 - 9',
                    '10 - 18',
                    '19 - 29',
                    '30 - 39',
                    '40 - 49',
                    '50 - 59',
                    '60 - 69',
                    '70 - 79',
                    '80+'
                  ]
                      .map((label) =>
                          DropdownMenuItem(value: label, child: Text(label)))
                      .toList()),
              SizedBox(height: 20),
              DropdownButton(
                  value: _gender,
                  onChanged: (value) => setState(() => _gender = value),
                  hint: Text('Gender'),
                  isExpanded: true,
                  items: ['Female', 'Male', 'Other']
                      .map((label) =>
                          DropdownMenuItem(value: label, child: Text(label)))
                      .toList()),
            ])));
  }
}
