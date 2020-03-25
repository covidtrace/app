import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state.dart';

class Settings extends StatelessWidget {
  Settings({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      Consumer<SettingsState>(builder: (context, settings, _) {
        var user = settings.getUser();

        return Scaffold(
            appBar: AppBar(title: Text('Set My Home')),
            body: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text('Location Sharing',
                                  style: Theme.of(context).textTheme.title)),
                          Switch.adaptive(
                              value: user.trackLocation,
                              onChanged: (value) {
                                user.trackLocation = value;
                                settings.setUser(user);
                              }),
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
                          value: user.age,
                          onChanged: (value) {
                            user.age = value;
                            settings.setUser(user);
                          },
                          hint: Text('Age'),
                          isExpanded: true,
                          items: {
                            0: '< 2 years',
                            2: '2 - 4',
                            5: '5 - 9',
                            10: '10 - 19',
                            20: '20 - 29',
                            30: '30 - 39',
                            40: '40 - 49',
                            50: '50 - 59',
                            60: '60 - 69',
                            70: '70 - 79',
                            80: '80+'
                          }
                              .map((value, label) => MapEntry(
                                  value,
                                  DropdownMenuItem(
                                      value: value, child: Text(label))))
                              .values
                              .toList()),
                      SizedBox(height: 10),
                      DropdownButton(
                          value: user.gender,
                          onChanged: (value) {
                            user.gender = value;
                            settings.setUser(user);
                          },
                          hint: Text('Gender'),
                          isExpanded: true,
                          items: ['Female', 'Male', 'Other']
                              .map((label) => DropdownMenuItem(
                                  value: label, child: Text(label)))
                              .toList()),
                    ])));
      });
}
