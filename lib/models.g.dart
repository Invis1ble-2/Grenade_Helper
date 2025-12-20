// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetGameMapCollection on Isar {
  IsarCollection<GameMap> get gameMaps => this.collection();
}

const GameMapSchema = CollectionSchema(
  name: r'GameMap',
  id: -3635191456468578970,
  properties: {
    r'backgroundPath': PropertySchema(
      id: 0,
      name: r'backgroundPath',
      type: IsarType.string,
    ),
    r'iconPath': PropertySchema(
      id: 1,
      name: r'iconPath',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 2,
      name: r'name',
      type: IsarType.string,
    )
  },
  estimateSize: _gameMapEstimateSize,
  serialize: _gameMapSerialize,
  deserialize: _gameMapDeserialize,
  deserializeProp: _gameMapDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {
    r'layers': LinkSchema(
      id: -8293386274200167784,
      name: r'layers',
      target: r'MapLayer',
      single: false,
    )
  },
  embeddedSchemas: {},
  getId: _gameMapGetId,
  getLinks: _gameMapGetLinks,
  attach: _gameMapAttach,
  version: '3.3.0',
);

int _gameMapEstimateSize(
  GameMap object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.backgroundPath.length * 3;
  bytesCount += 3 + object.iconPath.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _gameMapSerialize(
  GameMap object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.backgroundPath);
  writer.writeString(offsets[1], object.iconPath);
  writer.writeString(offsets[2], object.name);
}

GameMap _gameMapDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = GameMap(
    backgroundPath: reader.readStringOrNull(offsets[0]) ?? "",
    iconPath: reader.readStringOrNull(offsets[1]) ?? "",
    name: reader.readString(offsets[2]),
  );
  object.id = id;
  return object;
}

P _gameMapDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset) ?? "") as P;
    case 1:
      return (reader.readStringOrNull(offset) ?? "") as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _gameMapGetId(GameMap object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _gameMapGetLinks(GameMap object) {
  return [object.layers];
}

void _gameMapAttach(IsarCollection<dynamic> col, Id id, GameMap object) {
  object.id = id;
  object.layers.attach(col, col.isar.collection<MapLayer>(), r'layers', id);
}

extension GameMapQueryWhereSort on QueryBuilder<GameMap, GameMap, QWhere> {
  QueryBuilder<GameMap, GameMap, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension GameMapQueryWhere on QueryBuilder<GameMap, GameMap, QWhereClause> {
  QueryBuilder<GameMap, GameMap, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension GameMapQueryFilter
    on QueryBuilder<GameMap, GameMap, QFilterCondition> {
  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> backgroundPathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'backgroundPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition>
      backgroundPathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'backgroundPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> backgroundPathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'backgroundPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> backgroundPathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'backgroundPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition>
      backgroundPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'backgroundPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> backgroundPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'backgroundPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> backgroundPathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'backgroundPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> backgroundPathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'backgroundPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition>
      backgroundPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'backgroundPath',
        value: '',
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition>
      backgroundPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'backgroundPath',
        value: '',
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'iconPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'iconPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'iconPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'iconPath',
        value: '',
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> iconPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'iconPath',
        value: '',
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }
}

extension GameMapQueryObject
    on QueryBuilder<GameMap, GameMap, QFilterCondition> {}

extension GameMapQueryLinks
    on QueryBuilder<GameMap, GameMap, QFilterCondition> {
  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layers(
      FilterQuery<MapLayer> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'layers');
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layersLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'layers', length, true, length, true);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layersIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'layers', 0, true, 0, true);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layersIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'layers', 0, false, 999999, true);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layersLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'layers', 0, true, length, include);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layersLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'layers', length, include, 999999, true);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterFilterCondition> layersLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(
          r'layers', lower, includeLower, upper, includeUpper);
    });
  }
}

extension GameMapQuerySortBy on QueryBuilder<GameMap, GameMap, QSortBy> {
  QueryBuilder<GameMap, GameMap, QAfterSortBy> sortByBackgroundPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backgroundPath', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> sortByBackgroundPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backgroundPath', Sort.desc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> sortByIconPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> sortByIconPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.desc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }
}

extension GameMapQuerySortThenBy
    on QueryBuilder<GameMap, GameMap, QSortThenBy> {
  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByBackgroundPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backgroundPath', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByBackgroundPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'backgroundPath', Sort.desc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByIconPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByIconPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'iconPath', Sort.desc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<GameMap, GameMap, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }
}

extension GameMapQueryWhereDistinct
    on QueryBuilder<GameMap, GameMap, QDistinct> {
  QueryBuilder<GameMap, GameMap, QDistinct> distinctByBackgroundPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'backgroundPath',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GameMap, GameMap, QDistinct> distinctByIconPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'iconPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GameMap, GameMap, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }
}

extension GameMapQueryProperty
    on QueryBuilder<GameMap, GameMap, QQueryProperty> {
  QueryBuilder<GameMap, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<GameMap, String, QQueryOperations> backgroundPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'backgroundPath');
    });
  }

  QueryBuilder<GameMap, String, QQueryOperations> iconPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'iconPath');
    });
  }

  QueryBuilder<GameMap, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetMapLayerCollection on Isar {
  IsarCollection<MapLayer> get mapLayers => this.collection();
}

const MapLayerSchema = CollectionSchema(
  name: r'MapLayer',
  id: -6679060664901798519,
  properties: {
    r'assetPath': PropertySchema(
      id: 0,
      name: r'assetPath',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 1,
      name: r'name',
      type: IsarType.string,
    ),
    r'sortOrder': PropertySchema(
      id: 2,
      name: r'sortOrder',
      type: IsarType.long,
    )
  },
  estimateSize: _mapLayerEstimateSize,
  serialize: _mapLayerSerialize,
  deserialize: _mapLayerDeserialize,
  deserializeProp: _mapLayerDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {
    r'map': LinkSchema(
      id: -4556794790667815539,
      name: r'map',
      target: r'GameMap',
      single: true,
      linkName: r'layers',
    ),
    r'grenades': LinkSchema(
      id: 9149734396513681524,
      name: r'grenades',
      target: r'Grenade',
      single: false,
    )
  },
  embeddedSchemas: {},
  getId: _mapLayerGetId,
  getLinks: _mapLayerGetLinks,
  attach: _mapLayerAttach,
  version: '3.3.0',
);

int _mapLayerEstimateSize(
  MapLayer object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.assetPath.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _mapLayerSerialize(
  MapLayer object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.assetPath);
  writer.writeString(offsets[1], object.name);
  writer.writeLong(offsets[2], object.sortOrder);
}

MapLayer _mapLayerDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MapLayer(
    assetPath: reader.readString(offsets[0]),
    name: reader.readString(offsets[1]),
    sortOrder: reader.readLong(offsets[2]),
  );
  object.id = id;
  return object;
}

P _mapLayerDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _mapLayerGetId(MapLayer object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _mapLayerGetLinks(MapLayer object) {
  return [object.map, object.grenades];
}

void _mapLayerAttach(IsarCollection<dynamic> col, Id id, MapLayer object) {
  object.id = id;
  object.map.attach(col, col.isar.collection<GameMap>(), r'map', id);
  object.grenades.attach(col, col.isar.collection<Grenade>(), r'grenades', id);
}

extension MapLayerQueryWhereSort on QueryBuilder<MapLayer, MapLayer, QWhere> {
  QueryBuilder<MapLayer, MapLayer, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension MapLayerQueryWhere on QueryBuilder<MapLayer, MapLayer, QWhereClause> {
  QueryBuilder<MapLayer, MapLayer, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension MapLayerQueryFilter
    on QueryBuilder<MapLayer, MapLayer, QFilterCondition> {
  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assetPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'assetPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'assetPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'assetPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'assetPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'assetPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'assetPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'assetPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> assetPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assetPath',
        value: '',
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition>
      assetPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'assetPath',
        value: '',
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> sortOrderEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sortOrder',
        value: value,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> sortOrderGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sortOrder',
        value: value,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> sortOrderLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sortOrder',
        value: value,
      ));
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> sortOrderBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sortOrder',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension MapLayerQueryObject
    on QueryBuilder<MapLayer, MapLayer, QFilterCondition> {}

extension MapLayerQueryLinks
    on QueryBuilder<MapLayer, MapLayer, QFilterCondition> {
  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> map(
      FilterQuery<GameMap> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'map');
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> mapIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'map', 0, true, 0, true);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> grenades(
      FilterQuery<Grenade> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'grenades');
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> grenadesLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'grenades', length, true, length, true);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> grenadesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'grenades', 0, true, 0, true);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> grenadesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'grenades', 0, false, 999999, true);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition>
      grenadesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'grenades', 0, true, length, include);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition>
      grenadesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'grenades', length, include, 999999, true);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterFilterCondition> grenadesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(
          r'grenades', lower, includeLower, upper, includeUpper);
    });
  }
}

extension MapLayerQuerySortBy on QueryBuilder<MapLayer, MapLayer, QSortBy> {
  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> sortByAssetPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetPath', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> sortByAssetPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetPath', Sort.desc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> sortBySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> sortBySortOrderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.desc);
    });
  }
}

extension MapLayerQuerySortThenBy
    on QueryBuilder<MapLayer, MapLayer, QSortThenBy> {
  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenByAssetPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetPath', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenByAssetPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetPath', Sort.desc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenBySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.asc);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QAfterSortBy> thenBySortOrderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.desc);
    });
  }
}

extension MapLayerQueryWhereDistinct
    on QueryBuilder<MapLayer, MapLayer, QDistinct> {
  QueryBuilder<MapLayer, MapLayer, QDistinct> distinctByAssetPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'assetPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MapLayer, MapLayer, QDistinct> distinctBySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sortOrder');
    });
  }
}

extension MapLayerQueryProperty
    on QueryBuilder<MapLayer, MapLayer, QQueryProperty> {
  QueryBuilder<MapLayer, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MapLayer, String, QQueryOperations> assetPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'assetPath');
    });
  }

  QueryBuilder<MapLayer, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<MapLayer, int, QQueryOperations> sortOrderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sortOrder');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetGrenadeCollection on Isar {
  IsarCollection<Grenade> get grenades => this.collection();
}

const GrenadeSchema = CollectionSchema(
  name: r'Grenade',
  id: 4722472505309867140,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'isFavorite': PropertySchema(
      id: 1,
      name: r'isFavorite',
      type: IsarType.bool,
    ),
    r'isNewImport': PropertySchema(
      id: 2,
      name: r'isNewImport',
      type: IsarType.bool,
    ),
    r'team': PropertySchema(
      id: 3,
      name: r'team',
      type: IsarType.long,
    ),
    r'title': PropertySchema(
      id: 4,
      name: r'title',
      type: IsarType.string,
    ),
    r'type': PropertySchema(
      id: 5,
      name: r'type',
      type: IsarType.long,
    ),
    r'updatedAt': PropertySchema(
      id: 6,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'xRatio': PropertySchema(
      id: 7,
      name: r'xRatio',
      type: IsarType.double,
    ),
    r'yRatio': PropertySchema(
      id: 8,
      name: r'yRatio',
      type: IsarType.double,
    )
  },
  estimateSize: _grenadeEstimateSize,
  serialize: _grenadeSerialize,
  deserialize: _grenadeDeserialize,
  deserializeProp: _grenadeDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {
    r'layer': LinkSchema(
      id: -7909199833607422965,
      name: r'layer',
      target: r'MapLayer',
      single: true,
      linkName: r'grenades',
    ),
    r'steps': LinkSchema(
      id: 3007108002024856986,
      name: r'steps',
      target: r'GrenadeStep',
      single: false,
    )
  },
  embeddedSchemas: {},
  getId: _grenadeGetId,
  getLinks: _grenadeGetLinks,
  attach: _grenadeAttach,
  version: '3.3.0',
);

int _grenadeEstimateSize(
  Grenade object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _grenadeSerialize(
  Grenade object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeBool(offsets[1], object.isFavorite);
  writer.writeBool(offsets[2], object.isNewImport);
  writer.writeLong(offsets[3], object.team);
  writer.writeString(offsets[4], object.title);
  writer.writeLong(offsets[5], object.type);
  writer.writeDateTime(offsets[6], object.updatedAt);
  writer.writeDouble(offsets[7], object.xRatio);
  writer.writeDouble(offsets[8], object.yRatio);
}

Grenade _grenadeDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Grenade(
    isFavorite: reader.readBoolOrNull(offsets[1]) ?? false,
    isNewImport: reader.readBoolOrNull(offsets[2]) ?? false,
    team: reader.readLongOrNull(offsets[3]) ?? 0,
    title: reader.readString(offsets[4]),
    type: reader.readLong(offsets[5]),
    xRatio: reader.readDouble(offsets[7]),
    yRatio: reader.readDouble(offsets[8]),
  );
  object.createdAt = reader.readDateTime(offsets[0]);
  object.id = id;
  object.updatedAt = reader.readDateTime(offsets[6]);
  return object;
}

P _grenadeDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 2:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 3:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readDateTime(offset)) as P;
    case 7:
      return (reader.readDouble(offset)) as P;
    case 8:
      return (reader.readDouble(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _grenadeGetId(Grenade object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _grenadeGetLinks(Grenade object) {
  return [object.layer, object.steps];
}

void _grenadeAttach(IsarCollection<dynamic> col, Id id, Grenade object) {
  object.id = id;
  object.layer.attach(col, col.isar.collection<MapLayer>(), r'layer', id);
  object.steps.attach(col, col.isar.collection<GrenadeStep>(), r'steps', id);
}

extension GrenadeQueryWhereSort on QueryBuilder<Grenade, Grenade, QWhere> {
  QueryBuilder<Grenade, Grenade, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension GrenadeQueryWhere on QueryBuilder<Grenade, Grenade, QWhereClause> {
  QueryBuilder<Grenade, Grenade, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension GrenadeQueryFilter
    on QueryBuilder<Grenade, Grenade, QFilterCondition> {
  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> isFavoriteEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isFavorite',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> isNewImportEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isNewImport',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> teamEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'team',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> teamGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'team',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> teamLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'team',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> teamBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'team',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> typeEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> typeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> typeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> typeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> updatedAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> xRatioEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'xRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> xRatioGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'xRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> xRatioLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'xRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> xRatioBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'xRatio',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> yRatioEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'yRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> yRatioGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'yRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> yRatioLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'yRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> yRatioBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'yRatio',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension GrenadeQueryObject
    on QueryBuilder<Grenade, Grenade, QFilterCondition> {}

extension GrenadeQueryLinks
    on QueryBuilder<Grenade, Grenade, QFilterCondition> {
  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> layer(
      FilterQuery<MapLayer> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'layer');
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> layerIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'layer', 0, true, 0, true);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> steps(
      FilterQuery<GrenadeStep> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'steps');
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> stepsLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'steps', length, true, length, true);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> stepsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'steps', 0, true, 0, true);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> stepsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'steps', 0, false, 999999, true);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> stepsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'steps', 0, true, length, include);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> stepsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'steps', length, include, 999999, true);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterFilterCondition> stepsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(
          r'steps', lower, includeLower, upper, includeUpper);
    });
  }
}

extension GrenadeQuerySortBy on QueryBuilder<Grenade, Grenade, QSortBy> {
  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByIsFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFavorite', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByIsFavoriteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFavorite', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByIsNewImport() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNewImport', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByIsNewImportDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNewImport', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByTeam() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'team', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByTeamDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'team', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByXRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'xRatio', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByXRatioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'xRatio', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByYRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yRatio', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> sortByYRatioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yRatio', Sort.desc);
    });
  }
}

extension GrenadeQuerySortThenBy
    on QueryBuilder<Grenade, Grenade, QSortThenBy> {
  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByIsFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFavorite', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByIsFavoriteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isFavorite', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByIsNewImport() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNewImport', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByIsNewImportDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNewImport', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByTeam() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'team', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByTeamDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'team', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByXRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'xRatio', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByXRatioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'xRatio', Sort.desc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByYRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yRatio', Sort.asc);
    });
  }

  QueryBuilder<Grenade, Grenade, QAfterSortBy> thenByYRatioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yRatio', Sort.desc);
    });
  }
}

extension GrenadeQueryWhereDistinct
    on QueryBuilder<Grenade, Grenade, QDistinct> {
  QueryBuilder<Grenade, Grenade, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByIsFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isFavorite');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByIsNewImport() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isNewImport');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByTeam() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'team');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByXRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'xRatio');
    });
  }

  QueryBuilder<Grenade, Grenade, QDistinct> distinctByYRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'yRatio');
    });
  }
}

extension GrenadeQueryProperty
    on QueryBuilder<Grenade, Grenade, QQueryProperty> {
  QueryBuilder<Grenade, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Grenade, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Grenade, bool, QQueryOperations> isFavoriteProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isFavorite');
    });
  }

  QueryBuilder<Grenade, bool, QQueryOperations> isNewImportProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isNewImport');
    });
  }

  QueryBuilder<Grenade, int, QQueryOperations> teamProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'team');
    });
  }

  QueryBuilder<Grenade, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<Grenade, int, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }

  QueryBuilder<Grenade, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<Grenade, double, QQueryOperations> xRatioProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'xRatio');
    });
  }

  QueryBuilder<Grenade, double, QQueryOperations> yRatioProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'yRatio');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetGrenadeStepCollection on Isar {
  IsarCollection<GrenadeStep> get grenadeSteps => this.collection();
}

const GrenadeStepSchema = CollectionSchema(
  name: r'GrenadeStep',
  id: 8915658492438724618,
  properties: {
    r'description': PropertySchema(
      id: 0,
      name: r'description',
      type: IsarType.string,
    ),
    r'stepIndex': PropertySchema(
      id: 1,
      name: r'stepIndex',
      type: IsarType.long,
    ),
    r'title': PropertySchema(
      id: 2,
      name: r'title',
      type: IsarType.string,
    )
  },
  estimateSize: _grenadeStepEstimateSize,
  serialize: _grenadeStepSerialize,
  deserialize: _grenadeStepDeserialize,
  deserializeProp: _grenadeStepDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {
    r'grenade': LinkSchema(
      id: 7927984084280716986,
      name: r'grenade',
      target: r'Grenade',
      single: true,
      linkName: r'steps',
    ),
    r'medias': LinkSchema(
      id: 6935159071535812115,
      name: r'medias',
      target: r'StepMedia',
      single: false,
    )
  },
  embeddedSchemas: {},
  getId: _grenadeStepGetId,
  getLinks: _grenadeStepGetLinks,
  attach: _grenadeStepAttach,
  version: '3.3.0',
);

int _grenadeStepEstimateSize(
  GrenadeStep object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.description.length * 3;
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _grenadeStepSerialize(
  GrenadeStep object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.description);
  writer.writeLong(offsets[1], object.stepIndex);
  writer.writeString(offsets[2], object.title);
}

GrenadeStep _grenadeStepDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = GrenadeStep(
    description: reader.readString(offsets[0]),
    stepIndex: reader.readLong(offsets[1]),
    title: reader.readStringOrNull(offsets[2]) ?? "",
  );
  object.id = id;
  return object;
}

P _grenadeStepDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset) ?? "") as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _grenadeStepGetId(GrenadeStep object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _grenadeStepGetLinks(GrenadeStep object) {
  return [object.grenade, object.medias];
}

void _grenadeStepAttach(
    IsarCollection<dynamic> col, Id id, GrenadeStep object) {
  object.id = id;
  object.grenade.attach(col, col.isar.collection<Grenade>(), r'grenade', id);
  object.medias.attach(col, col.isar.collection<StepMedia>(), r'medias', id);
}

extension GrenadeStepQueryWhereSort
    on QueryBuilder<GrenadeStep, GrenadeStep, QWhere> {
  QueryBuilder<GrenadeStep, GrenadeStep, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension GrenadeStepQueryWhere
    on QueryBuilder<GrenadeStep, GrenadeStep, QWhereClause> {
  QueryBuilder<GrenadeStep, GrenadeStep, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension GrenadeStepQueryFilter
    on QueryBuilder<GrenadeStep, GrenadeStep, QFilterCondition> {
  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'description',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'description',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      stepIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'stepIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      stepIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'stepIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      stepIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'stepIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      stepIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'stepIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }
}

extension GrenadeStepQueryObject
    on QueryBuilder<GrenadeStep, GrenadeStep, QFilterCondition> {}

extension GrenadeStepQueryLinks
    on QueryBuilder<GrenadeStep, GrenadeStep, QFilterCondition> {
  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> grenade(
      FilterQuery<Grenade> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'grenade');
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      grenadeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'grenade', 0, true, 0, true);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition> medias(
      FilterQuery<StepMedia> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'medias');
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      mediasLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'medias', length, true, length, true);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      mediasIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'medias', 0, true, 0, true);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      mediasIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'medias', 0, false, 999999, true);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      mediasLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'medias', 0, true, length, include);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      mediasLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'medias', length, include, 999999, true);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterFilterCondition>
      mediasLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(
          r'medias', lower, includeLower, upper, includeUpper);
    });
  }
}

extension GrenadeStepQuerySortBy
    on QueryBuilder<GrenadeStep, GrenadeStep, QSortBy> {
  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> sortByStepIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stepIndex', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> sortByStepIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stepIndex', Sort.desc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }
}

extension GrenadeStepQuerySortThenBy
    on QueryBuilder<GrenadeStep, GrenadeStep, QSortThenBy> {
  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByStepIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stepIndex', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByStepIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stepIndex', Sort.desc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }
}

extension GrenadeStepQueryWhereDistinct
    on QueryBuilder<GrenadeStep, GrenadeStep, QDistinct> {
  QueryBuilder<GrenadeStep, GrenadeStep, QDistinct> distinctByDescription(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QDistinct> distinctByStepIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stepIndex');
    });
  }

  QueryBuilder<GrenadeStep, GrenadeStep, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }
}

extension GrenadeStepQueryProperty
    on QueryBuilder<GrenadeStep, GrenadeStep, QQueryProperty> {
  QueryBuilder<GrenadeStep, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<GrenadeStep, String, QQueryOperations> descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<GrenadeStep, int, QQueryOperations> stepIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stepIndex');
    });
  }

  QueryBuilder<GrenadeStep, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStepMediaCollection on Isar {
  IsarCollection<StepMedia> get stepMedias => this.collection();
}

const StepMediaSchema = CollectionSchema(
  name: r'StepMedia',
  id: 6649895050305602134,
  properties: {
    r'localPath': PropertySchema(
      id: 0,
      name: r'localPath',
      type: IsarType.string,
    ),
    r'type': PropertySchema(
      id: 1,
      name: r'type',
      type: IsarType.long,
    )
  },
  estimateSize: _stepMediaEstimateSize,
  serialize: _stepMediaSerialize,
  deserialize: _stepMediaDeserialize,
  deserializeProp: _stepMediaDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {
    r'step': LinkSchema(
      id: -5270616345131903840,
      name: r'step',
      target: r'GrenadeStep',
      single: true,
      linkName: r'medias',
    )
  },
  embeddedSchemas: {},
  getId: _stepMediaGetId,
  getLinks: _stepMediaGetLinks,
  attach: _stepMediaAttach,
  version: '3.3.0',
);

int _stepMediaEstimateSize(
  StepMedia object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.localPath.length * 3;
  return bytesCount;
}

void _stepMediaSerialize(
  StepMedia object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.localPath);
  writer.writeLong(offsets[1], object.type);
}

StepMedia _stepMediaDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StepMedia(
    localPath: reader.readString(offsets[0]),
    type: reader.readLong(offsets[1]),
  );
  object.id = id;
  return object;
}

P _stepMediaDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _stepMediaGetId(StepMedia object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _stepMediaGetLinks(StepMedia object) {
  return [object.step];
}

void _stepMediaAttach(IsarCollection<dynamic> col, Id id, StepMedia object) {
  object.id = id;
  object.step.attach(col, col.isar.collection<GrenadeStep>(), r'step', id);
}

extension StepMediaQueryWhereSort
    on QueryBuilder<StepMedia, StepMedia, QWhere> {
  QueryBuilder<StepMedia, StepMedia, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension StepMediaQueryWhere
    on QueryBuilder<StepMedia, StepMedia, QWhereClause> {
  QueryBuilder<StepMedia, StepMedia, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension StepMediaQueryFilter
    on QueryBuilder<StepMedia, StepMedia, QFilterCondition> {
  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition>
      localPathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'localPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> localPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localPath',
        value: '',
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition>
      localPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'localPath',
        value: '',
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> typeEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> typeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> typeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> typeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension StepMediaQueryObject
    on QueryBuilder<StepMedia, StepMedia, QFilterCondition> {}

extension StepMediaQueryLinks
    on QueryBuilder<StepMedia, StepMedia, QFilterCondition> {
  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> step(
      FilterQuery<GrenadeStep> q) {
    return QueryBuilder.apply(this, (query) {
      return query.link(q, r'step');
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterFilterCondition> stepIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.linkLength(r'step', 0, true, 0, true);
    });
  }
}

extension StepMediaQuerySortBy on QueryBuilder<StepMedia, StepMedia, QSortBy> {
  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> sortByLocalPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.asc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> sortByLocalPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.desc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension StepMediaQuerySortThenBy
    on QueryBuilder<StepMedia, StepMedia, QSortThenBy> {
  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> thenByLocalPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.asc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> thenByLocalPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.desc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension StepMediaQueryWhereDistinct
    on QueryBuilder<StepMedia, StepMedia, QDistinct> {
  QueryBuilder<StepMedia, StepMedia, QDistinct> distinctByLocalPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'localPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StepMedia, StepMedia, QDistinct> distinctByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type');
    });
  }
}

extension StepMediaQueryProperty
    on QueryBuilder<StepMedia, StepMedia, QQueryProperty> {
  QueryBuilder<StepMedia, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<StepMedia, String, QQueryOperations> localPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localPath');
    });
  }

  QueryBuilder<StepMedia, int, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }
}
