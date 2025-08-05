import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class MiscDetailsScreen extends StatelessWidget {
  const MiscDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Misc Details'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 100,
                  ranges: <GaugeRange>[
                    GaugeRange(startValue: 0, endValue: 50, color: Colors.green),
                    GaugeRange(startValue: 50, endValue: 80, color: Colors.orange),
                    GaugeRange(startValue: 80, endValue: 100, color: Colors.red),
                  ],
                  pointers: const <GaugePointer>[
                    NeedlePointer(value: 65), // Example value
                  ],
                  annotations: const <GaugeAnnotation>[
                    GaugeAnnotation(
                      widget: Text(
                        '65%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      angle: 90,
                      positionFactor: 0.5,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Center(
            child: Text(
              'Details about Miscellaneous Items',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}
