import 'package:flutter/material.dart';

/// Banner shown when screen data is loaded from cache after a network failure.
class CacheDataBanner extends StatelessWidget {
  const CacheDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, color: Color(0xFFF59E0B), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing cached data — may not be up to date',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
