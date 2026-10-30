class QuestionOption {
  const QuestionOption(this.id, this.label);

  final String id;
  final String label;

  Map<String, String> toJson() => {'id': id, 'label': label};
}

/// `activities/{a}/questions/{id}`. type: single | multiple | scale (1-5).
class ActivityQuestion {
  const ActivityQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.options = const [],
    this.required = true,
    this.order = 0,
  });

  factory ActivityQuestion.fromFirestore(String id, Map<String, dynamic> d) =>
      ActivityQuestion(
        id: id,
        label: d['label'] as String? ?? id,
        type: d['type'] as String? ?? 'single',
        options: [
          for (final o in (d['options'] as List?) ?? const [])
            if (o is Map)
              QuestionOption(
                o['id'] as String? ?? '',
                o['label'] as String? ?? '',
              ),
        ],
        required: d['required'] != false,
        order: (d['order'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String label;
  final String type;
  final List<QuestionOption> options;
  final bool required;
  final int order;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'type': type,
    if (type != 'scale') 'options': [for (final o in options) o.toJson()],
    'required': required,
  };
}

/// The caller's own `registrations/{a}_{uid}`.
class Registration {
  const Registration({required this.status, this.answers = const {}});

  factory Registration.fromFirestore(Map<String, dynamic> d) => Registration(
    status: d['status'] as String? ?? '',
    answers: Map<String, Object?>.from(d['answers'] as Map? ?? const {}),
  );

  /// `submitted | cancelled`.
  final String status;
  final Map<String, Object?> answers;

  bool get submitted => status == 'submitted';
}

/// One personality axis (matching.traits): 1-3 scale questions averaged into
/// a score; reverse items count as 6 - answer. The engine balances each axis
/// across teams (or groups similar people with `similar`).
class TraitAxis {
  const TraitAxis({required this.id, required this.label, required this.items});

  /// Lowercase letters/digits, unique within the activity.
  final String id;
  final String label;

  /// (question ID, reverse).
  final List<(String, bool)> items;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'items': [
      for (final (questionId, reverse) in items)
        {'questionId': questionId, if (reverse) 'reverse': true},
    ],
  };
}

/// Input for createActivity (functions/src/validation.js activity()).
class NewActivity {
  const NewActivity({
    required this.title,
    required this.type,
    this.description = '',
    required this.capacity,
    required this.targetTeamSize,
    required this.deadline,
    required this.questions,
    required this.criteria,
    this.method = 'balanced',
    this.requireCommonTime = false,
    this.traits = const [],
  });

  final String title;

  /// study | project | social | other (activityTypeLabels); a learning
  /// feature, so the operator always picks one.
  final String type;
  final String description;
  final int capacity;
  final int targetTeamSize;
  final DateTime deadline;
  final List<ActivityQuestion> questions;

  /// questionId -> role | time | experience | interest, in priority order.
  final Map<String, String> criteria;

  /// `balanced` (골고루) or `similar` (비슷하게).
  final String method;
  final bool requireCommonTime;

  /// Personality axes; when present the 'personality' criterion leads the
  /// priority (operators can reorder it in the formation settings).
  final List<TraitAxis> traits;

  Map<String, Object> toJson() => {
    'title': title.trim(),
    'type': type,
    'description': description.trim(),
    'capacity': capacity,
    'targetTeamSize': targetTeamSize,
    'deadlineAt': deadline.millisecondsSinceEpoch,
    'questions': [for (final q in questions) q.toJson()],
    'matching': {
      'method': method,
      'questionCriteria': criteria,
      'priority': [
        if (traits.isNotEmpty) 'personality',
        ...criteria.values,
        'size',
      ],
      'requireCommonTime': requireCommonTime,
      if (traits.isNotEmpty) 'traits': [for (final t in traits) t.toJson()],
    },
  };
}
