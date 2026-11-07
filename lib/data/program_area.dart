import 'package:flutter/material.dart';

class ProgramArea {
  const ProgramArea({
    required this.title,
    required this.summary,
    required this.icon,
    required this.source,
  });

  final String title;
  final String summary;
  final IconData icon;
  final String source;
}

const publicProgramAreas = <ProgramArea>[
  ProgramArea(
    title: 'Migrant Welfare & Diaspora Protection',
    summary:
        'The public website describes member-focused welfare, healthcare access and family protection as program goals.',
    icon: Icons.shield_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Rights & Representation',
    summary:
        'Legal advocacy and representation for the interests and rights of Orakzai communities.',
    icon: Icons.account_balance_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Education & Global Scholarships',
    summary:
        'Scholarship, mentorship and educational pathway information for students and families.',
    icon: Icons.school_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Social Welfare & Crisis Relief',
    summary:
        'Humanitarian assistance and community support are listed among the organization’s priorities.',
    icon: Icons.volunteer_activism_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Economic Innovation & Grants',
    summary:
        'The website outlines entrepreneurship, business support and local economic development.',
    icon: Icons.trending_up_rounded,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Global Diaspora Network',
    summary:
        'A public initiative focused on connecting Orakzai families, professionals and organizations.',
    icon: Icons.public_rounded,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Healthcare Infrastructure & Access',
    summary:
        'Healthcare access, preventive care and community health infrastructure are listed as focus areas.',
    icon: Icons.health_and_safety_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Women Empowerment & Artisan Support',
    summary:
        'The public program description highlights vocational skills and support for local artisans.',
    icon: Icons.diversity_3_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Youth Development & Sports',
    summary:
        'Youth mentorship, sports and constructive community development are listed as priorities.',
    icon: Icons.sports_soccer_outlined,
    source: 'Official website',
  ),
  ProgramArea(
    title: 'Clean Water & Sanitation',
    summary:
        'The website describes access to safe water and sanitation as a community development focus.',
    icon: Icons.water_drop_outlined,
    source: 'Official website',
  ),
];

const serviceDirectory = <ProgramArea>[
  ...publicProgramAreas,
  ProgramArea(
    title: 'Jobs & Careers',
    summary:
        'A directory category for future verified job and career resources.',
    icon: Icons.work_outline_rounded,
    source: 'App brief',
  ),
  ProgramArea(
    title: 'Business Directory',
    summary:
        'A directory category for community businesses; listings are not connected yet.',
    icon: Icons.storefront_outlined,
    source: 'App brief',
  ),
  ProgramArea(
    title: 'Emergency Resources',
    summary: 'A category for verified emergency contacts and local resources.',
    icon: Icons.emergency_outlined,
    source: 'App brief',
  ),
  ProgramArea(
    title: 'Blood Donor Network',
    summary:
        'A planned service directory; no donor records or contacts are stored in this preview.',
    icon: Icons.bloodtype_outlined,
    source: 'App brief',
  ),
  ProgramArea(
    title: 'Community Events',
    summary:
        'A directory category for confirmed community events and opportunities.',
    icon: Icons.event_outlined,
    source: 'App brief',
  ),
  ProgramArea(
    title: 'News & Announcements',
    summary:
        'A place for organization updates sourced from verified public announcements.',
    icon: Icons.campaign_outlined,
    source: 'App brief',
  ),
  ProgramArea(
    title: 'Heritage & Culture',
    summary:
        'A future space for Orakzai history, language, culture and community stories.',
    icon: Icons.auto_stories_outlined,
    source: 'App brief',
  ),
];

const helpCategories = <String>[
  'Emergency',
  'Education',
  'Healthcare',
  'Employment',
  'Welfare',
  'Housing',
  'Legal guidance',
  'Other',
];
