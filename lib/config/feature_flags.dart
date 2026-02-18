/// 发布期开关：用于将未完成功能对外隐藏。
///
/// 默认关闭道具标签功能。需要灰度/恢复时，可在构建命令增加：
/// `--dart-define=ENABLE_GRENADE_TAGS=true`
const bool kEnableGrenadeTags = bool.fromEnvironment(
  'ENABLE_GRENADE_TAGS',
  defaultValue: true,
);
