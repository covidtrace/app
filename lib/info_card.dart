import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoCard extends StatelessWidget {
  final Map<String, dynamic> item;

  InfoCard({Key key, this.item}) : super(key: key);

  Widget cardIcon(String name) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.asset(name, width: 40, height: 40, fit: BoxFit.contain));
  }

  @override
  Widget build(BuildContext context) {
    var subhead = Theme.of(context)
        .textTheme
        .subtitle1
        .merge(TextStyle(fontWeight: FontWeight.bold));

    var mainContent = [
      Text(item['title'], style: subhead),
      SizedBox(height: 5),
      Text(item['body']),
    ];

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 10, horizontal: 1),
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...(item.containsKey('icon'))
                ? [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: mainContent,
                          ),
                        ),
                        SizedBox(width: 10),
                        cardIcon(item['icon']),
                      ],
                    ),
                  ]
                : mainContent,
            ...(item.containsKey('link'))
                ? [
                    Divider(height: 20),
                    InkWell(
                      onTap: () => launch(item['link']),
                      child: Text('Learn more',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ]
                : [],
          ],
        ),
      ),
    );
  }
}
