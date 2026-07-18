enum NotePageTemplate { blank, ruled, dotted, grid, cornell, planner }

extension NotePageTemplateLabel on NotePageTemplate {
  String get label => switch (this) {
    NotePageTemplate.blank => 'Blank',
    NotePageTemplate.ruled => 'Ruled',
    NotePageTemplate.dotted => 'Dotted',
    NotePageTemplate.grid => 'Grid',
    NotePageTemplate.cornell => 'Cornell',
    NotePageTemplate.planner => 'Planner',
  };
}

NotePageTemplate notePageTemplateFromJson(Object? value) {
  if (value is! String) {
    return NotePageTemplate.blank;
  }

  for (final template in NotePageTemplate.values) {
    if (template.name == value) {
      return template;
    }
  }
  return NotePageTemplate.blank;
}
