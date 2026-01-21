// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grenade_tag.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetGrenadeTagCollection on Isar {
  IsarCollection<GrenadeTag> get grenadeTags => this.collection();
}

const GrenadeTagSchema = CollectionSchema(
  name: r'GrenadeTag',
  id: -9159300689878422325,
  properties: {
    r'grenadeId': PropertySchema(
      id: 0,
      name: r'grenadeId',
      type: IsarType.long,
    ),
    r'tagId': PropertySchema(
      id: 1,
      name: r'tagId',
      type: IsarType.long,
    )
  },
  estimateSize: _grenadeTagEstimateSize,
  serialize: _grenadeTagSerialize,
  deserialize: _grenadeTagDeserialize,
  deserializeProp: _grenadeTagDeserializeProp,
  idName: r'id',
  indexes: {
    r'grenadeId': IndexSchema(
      id: -5982136024902040837,
      name: r'grenadeId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'grenadeId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'tagId': IndexSchema(
      id: -2598179288284149414,
      name: r'tagId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'tagId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _grenadeTagGetId,
  getLinks: _grenadeTagGetLinks,
  attach: _grenadeTagAttach,
  version: '3.3.0',
);

int _grenadeTagEstimateSize(
  GrenadeTag object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  return bytesCount;
}

void _grenadeTagSerialize(
  GrenadeTag object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.grenadeId);
  writer.writeLong(offsets[1], object.tagId);
}

GrenadeTag _grenadeTagDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = GrenadeTag(
    grenadeId: reader.readLong(offsets[0]),
    tagId: reader.readLong(offsets[1]),
  );
  object.id = id;
  return object;
}

P _grenadeTagDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _grenadeTagGetId(GrenadeTag object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _grenadeTagGetLinks(GrenadeTag object) {
  return [];
}

void _grenadeTagAttach(IsarCollection<dynamic> col, Id id, GrenadeTag object) {
  object.id = id;
}

extension GrenadeTagQueryWhereSort
    on QueryBuilder<GrenadeTag, GrenadeTag, QWhere> {
  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhere> anyGrenadeId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'grenadeId'),
      );
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhere> anyTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'tagId'),
      );
    });
  }
}

extension GrenadeTagQueryWhere
    on QueryBuilder<GrenadeTag, GrenadeTag, QWhereClause> {
  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> idBetween(
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

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> grenadeIdEqualTo(
      int grenadeId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'grenadeId',
        value: [grenadeId],
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> grenadeIdNotEqualTo(
      int grenadeId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'grenadeId',
              lower: [],
              upper: [grenadeId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'grenadeId',
              lower: [grenadeId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'grenadeId',
              lower: [grenadeId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'grenadeId',
              lower: [],
              upper: [grenadeId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> grenadeIdGreaterThan(
    int grenadeId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'grenadeId',
        lower: [grenadeId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> grenadeIdLessThan(
    int grenadeId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'grenadeId',
        lower: [],
        upper: [grenadeId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> grenadeIdBetween(
    int lowerGrenadeId,
    int upperGrenadeId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'grenadeId',
        lower: [lowerGrenadeId],
        includeLower: includeLower,
        upper: [upperGrenadeId],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> tagIdEqualTo(
      int tagId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'tagId',
        value: [tagId],
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> tagIdNotEqualTo(
      int tagId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'tagId',
              lower: [],
              upper: [tagId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'tagId',
              lower: [tagId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'tagId',
              lower: [tagId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'tagId',
              lower: [],
              upper: [tagId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> tagIdGreaterThan(
    int tagId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'tagId',
        lower: [tagId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> tagIdLessThan(
    int tagId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'tagId',
        lower: [],
        upper: [tagId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterWhereClause> tagIdBetween(
    int lowerTagId,
    int upperTagId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'tagId',
        lower: [lowerTagId],
        includeLower: includeLower,
        upper: [upperTagId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension GrenadeTagQueryFilter
    on QueryBuilder<GrenadeTag, GrenadeTag, QFilterCondition> {
  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> grenadeIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'grenadeId',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition>
      grenadeIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'grenadeId',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> grenadeIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'grenadeId',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> grenadeIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'grenadeId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> idBetween(
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

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> tagIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tagId',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> tagIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tagId',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> tagIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tagId',
        value: value,
      ));
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterFilterCondition> tagIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tagId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension GrenadeTagQueryObject
    on QueryBuilder<GrenadeTag, GrenadeTag, QFilterCondition> {}

extension GrenadeTagQueryLinks
    on QueryBuilder<GrenadeTag, GrenadeTag, QFilterCondition> {}

extension GrenadeTagQuerySortBy
    on QueryBuilder<GrenadeTag, GrenadeTag, QSortBy> {
  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> sortByGrenadeId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grenadeId', Sort.asc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> sortByGrenadeIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grenadeId', Sort.desc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> sortByTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.asc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> sortByTagIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.desc);
    });
  }
}

extension GrenadeTagQuerySortThenBy
    on QueryBuilder<GrenadeTag, GrenadeTag, QSortThenBy> {
  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> thenByGrenadeId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grenadeId', Sort.asc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> thenByGrenadeIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grenadeId', Sort.desc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> thenByTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.asc);
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QAfterSortBy> thenByTagIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagId', Sort.desc);
    });
  }
}

extension GrenadeTagQueryWhereDistinct
    on QueryBuilder<GrenadeTag, GrenadeTag, QDistinct> {
  QueryBuilder<GrenadeTag, GrenadeTag, QDistinct> distinctByGrenadeId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'grenadeId');
    });
  }

  QueryBuilder<GrenadeTag, GrenadeTag, QDistinct> distinctByTagId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tagId');
    });
  }
}

extension GrenadeTagQueryProperty
    on QueryBuilder<GrenadeTag, GrenadeTag, QQueryProperty> {
  QueryBuilder<GrenadeTag, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<GrenadeTag, int, QQueryOperations> grenadeIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'grenadeId');
    });
  }

  QueryBuilder<GrenadeTag, int, QQueryOperations> tagIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tagId');
    });
  }
}
