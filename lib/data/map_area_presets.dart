import '../models/tag.dart';

/// 地图区域预设
const Map<String, List<String>> mapAreaPresets = {
  'dust2': ['A大', 'A1', 'A2', 'A3', 'A包点', 'A坑', '中门', '中路', 'B通', 'B洞', 'B包点', 'B门', '匪家', '警家', '大坑', '小坑'],
  'mirage': ['A大', 'A1', 'A2', 'A3', 'A包点', 'CT房', '中路', 'B通', 'B包点', 'B洞', '短点', '窗台', '天台', '匪家', '警家'],
  'inferno': ['A大', 'A1', 'A2', 'A3', 'A包点', 'A平台', '中路', 'B通', 'B包点', 'B车', '香蕉', '二楼', '匪家', '警家'],
  'nuke': ['A包点', 'A大厅', '天台', '外围', 'B包点', 'B秘', '单向', '双向', '地下', '匪家', '警家'],
  'overpass': ['A包点', 'A厕所', 'A电话', 'B包点', 'B通', 'B怪兽', '下水道', '连接', '匪家', '警家'],
  'vertigo': ['A包点', 'A斜坡', 'B包点', 'B斜坡', '中路', '电梯', '匪家', '警家'],
  'ancient': ['A包点', 'A大', 'B包点', 'B通', '中路', '匪家', '警家'],
  'anubis': ['A包点', 'A运河', 'B包点', 'B通', '中路', '连接', '匪家', '警家'],
};

/// 通用系统标签预设
const Map<int, List<String>> commonSystemTags = {
  TagDimension.role: ['T方', 'CT方', '通用'],
  TagDimension.phase: ['开局', '中期', '残局', '回防'],
  TagDimension.spawn: ['1号位', '2号位', '3号位', '4号位', '5号位'],
  TagDimension.purpose: ['封烟', '爆闪', '火封', '迷惑', '压制', '信息'],
};

/// 维度颜色
const Map<int, int> dimensionColors = {
  TagDimension.role: 0xFF9C27B0,
  TagDimension.area: 0xFF4CAF50,
  TagDimension.phase: 0xFF2196F3,
  TagDimension.spawn: 0xFFFF9800,
  TagDimension.purpose: 0xFFE91E63,
  TagDimension.custom: 0xFF607D8B,
};
