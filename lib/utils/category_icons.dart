import 'package:flutter/material.dart';
import '../models/category_type.dart';

IconData categoryIcon(CategoryType category) {
  switch (category) {
    case CategoryType.food:
      return Icons.restaurant;
    case CategoryType.finance:
      return Icons.attach_money;
    case CategoryType.wellness:
      return Icons.spa;
    case CategoryType.career:
      return Icons.work_outline;
    case CategoryType.home:
      return Icons.home_outlined;
    case CategoryType.travel:
      return Icons.flight_takeoff;
    case CategoryType.tech:
      return Icons.computer;
    case CategoryType.gaming:
      return Icons.sports_esports;
    case CategoryType.entertainment:
      return Icons.movie_outlined;
    case CategoryType.shopping:
      return Icons.shopping_bag_outlined;
    case CategoryType.style:
      return Icons.checkroom;
    case CategoryType.books:
      return Icons.menu_book;
    case CategoryType.growth:
      return Icons.trending_up;
    case CategoryType.projects:
      return Icons.build;
    case CategoryType.creativity:
      return Icons.brush;
    case CategoryType.sports:
      return Icons.sports_soccer;
    case CategoryType.other:
      return Icons.category_outlined;
  }
}
