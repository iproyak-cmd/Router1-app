const cycleModuleId = 'cycle';
const journalModuleId = 'journal';
const connectionModuleId = 'connection';
const compatibilityModuleId = 'compatibility';
const companionModuleId = 'companion';
const careerModuleId = 'career';

List<String> fabulaNavigationSectionIds(Set<String> enabledModules) => [
  'today',
  if (enabledModules.contains(companionModuleId)) companionModuleId,
  if (enabledModules.contains(careerModuleId)) careerModuleId,
  if (enabledModules.contains(cycleModuleId)) cycleModuleId,
  if (enabledModules.contains(connectionModuleId)) connectionModuleId,
  if (enabledModules.contains(compatibilityModuleId)) compatibilityModuleId,
  'profile',
];

String? fabulaAssistantNudgeModuleId(
  Set<String> enabledModules, {
  required bool cycleConfigured,
}) {
  if (enabledModules.contains(cycleModuleId) && !cycleConfigured) {
    return cycleModuleId;
  }
  if (enabledModules.contains(journalModuleId)) return journalModuleId;
  return null;
}
