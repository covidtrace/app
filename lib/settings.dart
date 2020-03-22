import 'package:flutter/material.dart';

class Settings extends StatefulWidget {
  Settings({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => SettingsState();
}

class SettingsState extends State<Settings> {
  var _gender;
  var _age;
  var _sharing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(
                  child: Text('Location Sharing',
                      style: Theme.of(context).textTheme.title)),
              Switch.adaptive(
                value: _sharing,
                onChanged: (value) => setState(() => _sharing = value),
              )
            ],
          ),
          Text(
              'Share my anonymized location history (time & place) with others when I confirm that I have COVID-19. We will NEVER track or share the location marked as your home.'),
          SizedBox(height: 50),
          Text('Optional Health Information',
              style: Theme.of(context).textTheme.title),
          SizedBox(height: 10),
          Text(
              'You can optionally provide some additional info when submitting reports. The information you provide here is never associated with your location history.'),
          SizedBox(height: 10),
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
          SizedBox(height: 10),
          DropdownButton(
              value: _gender,
              onChanged: (value) => setState(() => _gender = value),
              hint: Text('Gender'),
              isExpanded: true,
              items: ['Female', 'Male', 'Other']
                  .map((label) =>
                      DropdownMenuItem(value: label, child: Text(label)))
                  .toList()),
        ]));
  }
}
