import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:optionxi/Main_Pages/Learning/act_learn_optionxi.dart';

class RouteNotFoundPage extends StatelessWidget {
  const RouteNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.scaffold,
      appBar: AppBar(
        backgroundColor: DColors.scaffold,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: DColors.ink),
          onPressed: () => Get.back(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded,
                  size: 48, color: DColors.grey),
              const SizedBox(height: 12),
              const Text(
                "That page isn't available right now.",
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: DColors.ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 180,
                child: DButton(text: 'Go back', onPressed: () => Get.back()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
