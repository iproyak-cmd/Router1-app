const cycleModuleId = 'cycle';
const connectionModuleId = 'connection';
const compatibilityModuleId = 'compatibility';
const companionModuleId = 'companion';

List<String> fabulaNavigationSectionIds(Set<String> enabledModules) => [
  'today',
  if (enabledModules.contains(companionModuleId)) companionModuleId,
  if (enabledModules.contains(cycleModuleId)) cycleModuleId,
  if (enabledModules.contains(compatibilityModuleId)) compatibilityModuleId,
  'profile',
];
