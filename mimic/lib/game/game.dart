import 'package:flutter/material.dart';

class MimicGame extends StatelessWidget {
  const MimicGame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mimic Game',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Mimic - Social Deduction Game'),
        ),
        body: const Center(
          child: Text(
            'Welcome to Mimic!\nTap around to find the secret vault...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}