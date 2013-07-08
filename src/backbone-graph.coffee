# Lightweight Backbone library for model relations
# Supports One-to-One, One-to-Many and Many-to-Many relations

getValue = (key, context)->
  if !key
    return null
  if _.isFunction(key)
    return key.call(context)
  return key

modelOptions = (options)->
  return options && _.omit(options, "add", "remove", "url", "urlRoot", "collection")

addOptions = (options)->
  return options && _.extend(_.omit(options, "url", "urlRoot", "collection"), {remove: false, parse: false})

Backbone.Graph = class Graph

  constructor: ->
    @collections = []
    @models = new GraphCollection()
    @models.model = GraphModel
    @models.on("remove", (model)=>
      model._relChanging = true
      for rel in model.relations
        col = model.attributes[rel.key]
        if col instanceof Backbone.Collection
          col.reset()
          col.off(null, null, this)
      model._relChanging = false
    , this)
    @models.on("add", (model, col, options)=>
      @getCollection(model.constructor, true).add(model, options)
    , this)

  getCollection: (type, create)->
    if (type == GraphModel or type.prototype instanceof GraphModel)
      col = _.chain(@collections).filter((c)->
        return c.model == type
      ).first().value()
      if !col and create
        col = new Backbone.Collection()
        col.model = type
        @collections.push(col)
        col.on("remove", (model)=>
          @removeModel(model)
        , this)
      return col
    return null

  addModel: (model, options = {})->
    model._store = this
    @models.add(model, addOptions(options))

  removeModel: (model)->
    @models.remove(model)

Backbone.GraphModel = class GraphModel extends Backbone.Model

  _getRelationType: (relation)->
    if !relation.type
      return null
    if relation.type.ctor
      return relation.type.ctor
    if relation.type.provider
      return relation.type.provider.call(this)
    return null

  _onModelEvent: (attr, parent)->
    return (event, model)->
      if event.indexOf("change:") == 0
        attrs = event.substring(7)
        event = "change:" + attr + "." + attrs
        args = [event].concat(_.toArray(arguments).slice(1))
        parent.trigger.apply(parent, args)

  _changeRel: (model, attr, value, options)->
    rel = @_findRelation(model, attr)
    prevReverseKey = getValue(rel.reverseKey, new Backbone.Model(model.previousAttributes()))
    prevModel = model.previous(attr)

    # Cleanup the old relation
    if prevModel instanceof GraphModel and prevReverseKey
      if prevModel._relChanging or prevModel._changing
        return
      # rel = @_findReverseRelation(prevModel, attr)
      if prevModel.get(prevReverseKey) instanceof Backbone.Collection
        prevModel.get(prevReverseKey).remove(model, options)
      else
        prevModel.set(prevReverseKey, null, options)
      prevModel.off("all", null, this)

    # Handle the new relation
    relModel = value
    if !relModel
      return
    if (relModel instanceof GraphModel)
      if (relModel._relChanging or relModel._changing)
        return
    else
      if _.isString(relModel)
        id = relModel
        relModel = {}
        relModel[Backbone.Model.prototype.idAttribute] = id
      else
        id = relModel?[Backbone.Model.prototype.idAttribute]
      modelInStore = Backbone.graphStore.models.get(id)
      if modelInStore
        if options.merge
          modelInStore.set(relModel, options)
        relModel = modelInStore
      else
        if rel.autoCreate
          relType = @_getRelationType(rel)
          if !relType
            return
          attrs = relModel
          relModel = new relType(attrs, modelOptions(options))
        else
          return
    @attributes[attr] = relModel
    currentReverseKey = getValue(rel.reverseKey, model)
    if currentReverseKey
      if relModel.get(currentReverseKey) instanceof Backbone.Collection
        relModel.get(currentReverseKey).add(model, addOptions(options))
      else
        relModel.set(currentReverseKey, model, modelOptions(options))
    relModel.on("all", @_onModelEvent(attr, this), this)

  _addToColRel: (relModel, col, options)->
    rel = @_findRelation(relModel, getValue(col.reverseKey, this))
    if rel
      if relModel.get(rel.key) instanceof Backbone.Collection
        relModel.get(rel.key).add(this, addOptions(options))
      else
        relModel.set(rel.key, this, modelOptions(options))

  _removeFromColRel: (relModel, col, options)->
    rel = @_findRelation(relModel, getValue(col.reverseKey, this))
    if rel
      if relModel.get(rel.key) instanceof Backbone.Collection
        relModel.get(rel.key).remove(this, options)
      else
        relModel.set(rel.key, null, modelOptions(options))

  _findRelation: (model, key)->
    if _.isArray(model.relations)
      return _(model.relations || []).find((r)-> r.key == key)
    else
      return model.relations[key]

  _setupCollectionAttributes: ->
    _.each(@relations || [], (rel)=>
      relType = @_getRelationType(rel)
      if (relType?.prototype instanceof Backbone.Collection)
        if !(@attributes[rel.key] instanceof Backbone.Collection)
          attrs = @attributes[rel.key]
          if !(attrs and _.size(attrs) > 0)
            attrs = null
          col = new relType(attrs)
          col.key = rel.key
          col.reverseKey = rel.reverseKey
          col.container = this
          col.on("rel_add add", @_addToColRel, this)
          col.on("rel_remove remove", @_removeFromColRel, this)
          @attributes[rel.key] = col
      else
        do (rel)=>
          @on("rel_change:#{rel.key} change:#{rel.key}", (model, value, opts)=>
            @_changeRel(model, rel.key, value, opts)
          , this)
    )
    @_relAttrsSetup = true

  constructor: (attributes, options = {})->
    if !@relations
      @relations = []
    super(attributes, options)

  initialize: (attributes, options)->
    super
    if !@_relAttrsSetup
      @_setupCollectionAttributes()
    if !@_store
      Backbone.graphStore.addModel(this, options)
    @trigger('"initialize', this)

  toJSON: (options)->
    json = {}
    for own attr of @attributes
      rel = @_findRelation(this, attr)
      if rel
        if @attributes[attr]?.id && rel.serialize
          json[attr] = @attributes[attr]?.id
      else
        json[attr] = @attributes[attr]
    return json

  prepareSetParams: (key, value, options)->
    if _.isObject(key) || key == null
      attrs = key
      options = value
    else
      attrs = {}
      attrs[key] = value
    return [attrs, options]

  set: (key, value, options)->
    if !@_relAttrsSetup
      @_setupCollectionAttributes()
    [attrs, options] = @prepareSetParams(key, value, options)
    if !attrs
      return this
    if attrs == @attributes
      return this
    for rel in @relations
      if rel.key of attrs
        # Collection relations can't be changed. Use collection operations for that
        if @_getRelationType(rel)?.prototype instanceof Backbone.Collection
          delete attrs[rel.key]
        # If it's about the same model then omit it from set and merge if needed
        current = @attributes[rel.key]
        toSet = attrs[rel.key]
        if current && toSet
          # Checking if the objects are the same
          # - if ignoreId is set then the models are always the same
          # - if they have the same id then they are the same
          if rel.ignoreId || (current.id && current.id == (value?[Backbone.Model.prototype.idAttribute] || value))
            attrs[rel.key] = current
            if options.merge && _.isObject(value)
              current.set(value, modelOptions(options))
    return super(attrs, options)

Backbone.GraphCollection = class GraphCollection extends Backbone.Collection

  reset: (models, options)->
    if options?.silent
      return super
    @container?._relChanging = true
    for modelIn in @models
      @trigger("rel_remove", modelIn, this, options)
    result = super
    for model in @models
      @trigger("rel_add", model, this, options)
    @container?._relChanging = false
    return result

  _prepareModel: (attrs, options)->
    if (attrs instanceof GraphModel)
      return super
    if (id = attrs[Backbone.Model.prototype.idAttribute]) && (model = Backbone.graphStore.models.get(id))
      if options.merge
        if options.parse
          attrs = model.parse(attrs)
        model.set(attrs, options)
      return model
    return super

Backbone.graphStore = new Graph()
