H2O.Proxy = (_) ->
  
  http = (path, opts, go) ->
    _.status 'server', 'request', path

    req = if opts then $.post path, opts else $.getJSON path

    req.done (data, status, xhr) ->
      _.status 'server', 'response', path

      try
        go null, data
      catch error
        go new Flow.Error (if opts then "Error processing POST #{path}" else "Error processing GET #{path}"), error

    req.fail (xhr, status, error) ->
      _.status 'server', 'error', path

      message = if xhr.responseJSON?.errmsg
        xhr.responseJSON.errmsg
      else if error?.message
        error.message
      else if status is 0
        'Could not connect to H2O'
      else
        'Unknown error'

      go new Flow.Error message, new Flow.Error if opts then "Error calling POST #{path} with opts #{JSON.stringify opts}" else "Error calling GET #{path}"

  doGet = (path, go) -> http path, null, go
  doPost = http

  mapWithKey = (obj, f) ->
    result = []
    for key, value of obj
      result.push f value, key
    result

  composePath = (path, opts) ->
    if opts
      params = mapWithKey opts, (v, k) -> "#{k}=#{v}"
      path + '?' + join params, '&'
    else
      path

  requestWithOpts = (path, opts, go) ->
    doGet (composePath path, opts), go

  encodeArrayForPost = (array) -> "[#{join (map array, (element) -> "\"#{element}\""), ','}]"

  encodeObject = (source) ->
    target = {}
    for k, v of source
      target[k] = encodeURIComponent v
    target

  requestInspect = (key, go) ->
    opts = key: encodeURIComponent key
    requestWithOpts '/1/Inspect.json', opts, go

  requestCreateFrame = (opts, go) ->
    #requestWithOpts '/2/CreateFrame.json', (encodeObject opts), go
    doPost '/2/CreateFrame.json', opts, go

  requestFrames = (go) ->
    doGet '/3/Frames.json', (error, result) ->
      if error
        go error
      else
        go null, result.frames

  requestFrame = (key, go) ->
    doGet "/3/Frames.json/#{encodeURIComponent key}", (error, result) ->
      if error
        go error
      else
        go null, head result.frames

  requestColumnSummary = (key, column, go) ->
    doGet "/3/Frames.json/#{encodeURIComponent key}/columns/#{encodeURIComponent column}/summary", (error, result) ->
      if error
        go error
      else
        go null, head result.frames

  requestJobs = (go) ->
    doGet '/2/Jobs.json', (error, result) ->
      if error
        go new Flow.Error 'Error fetching jobs', error
      else
        go null, result.jobs 

  requestJob = (key, go) ->
    #opts = key: encodeURIComponent key
    #requestWithOpts '/Job.json', opts, go
    doGet "/2/Jobs.json/#{encodeURIComponent key}", (error, result) ->
      if error
        go new Flow.Error "Error fetching job '#{key}'", error
      else
        go null, head result.jobs

  requestFileGlob = (path, limit, go) ->
    opts =
      src: encodeURIComponent path
      limit: limit
    requestWithOpts '/2/Typeahead.json/files', opts, go

  requestImportFiles = (paths, go) ->
    tasks = map paths, (path) ->
      (go) ->
        requestImportFile path, go
    (Flow.Async.iterate tasks) go

  requestImportFile = (path, go) ->
    opts = path: encodeURIComponent path
    requestWithOpts '/2/ImportFiles.json', opts, go

  requestParseSetup = (sources, go) ->
    opts =
      srcs: encodeArrayForPost sources
    doPost '/2/ParseSetup.json', opts, go

  requestParseFiles = (sourceKeys, destinationKey, parserType, separator, columnCount, useSingleQuotes, columnNames, deleteOnDone, checkHeader, go) ->
    opts =
      hex: destinationKey
      srcs: encodeArrayForPost sourceKeys
      pType: parserType
      sep: separator
      ncols: columnCount
      singleQuotes: useSingleQuotes
      columnNames: encodeArrayForPost columnNames
      checkHeader: checkHeader
      delete_on_done: deleteOnDone
    doPost '/2/Parse.json', opts, go

  patchUpModels = (models) ->
    for model in models
      for parameter in model.parameters
        switch parameter.type
          when 'Key<Frame>', 'Key<Model>', 'VecSpecifier'
            if isString parameter.actual_value
              try
                parameter.actual_value = JSON.parse parameter.actual_value
              catch parseError
    models

  requestModels = (go, opts) ->
    requestWithOpts '/3/Models.json', opts, (error, result) ->
      if error
        go error, result
      else
        go error, patchUpModels result.models

  requestModel = (key, go) ->
    doGet "/3/Models.json/#{encodeURIComponent key}", (error, result) ->
      if error
        go error, result
      else
        go error, head patchUpModels result.models

  requestModelBuilders = (go) ->
    doGet "/3/ModelBuilders.json", go

  requestModelBuilder = (algo, go) ->
    doGet "/3/ModelBuilders.json/#{algo}", go

  requestModelInputValidation = (algo, parameters, go) ->
    doPost "/3/ModelBuilders.json/#{algo}/parameters", parameters, go

  requestModelBuild = (algo, parameters, go) ->
    doPost "/3/ModelBuilders.json/#{algo}", parameters, go

  requestPredict = (modelKey, frameKey, go) ->
    doPost "/3/Predictions.json/models/#{encodeURIComponent modelKey}/frames/#{encodeURIComponent frameKey}", {}, (error, result) ->
      if error
        go error
      else
        go null, head result.model_metrics

  requestPrediction = (modelKey, frameKey, go) ->
    doPost "/3/Predictions.json/models/#{encodeURIComponent modelKey}/frames/#{encodeURIComponent frameKey}", {}, (error, result) ->
      if error
        go error
      else
        go null, head result.model_metrics

  requestPredictions = (modelKey, frameKey, _go) ->
    go = (error, result) ->
      if error
        _go error
      else
        #
        # TODO workaround for a filtering bug in the API
        # 
        predictions = for prediction in result.model_metrics
          if modelKey and prediction.model.name isnt modelKey
            null
          else if frameKey and prediction.frame.name isnt frameKey
            null
          else
            prediction
        _go null, (prediction for prediction in predictions when prediction)

    if modelKey and frameKey
      doPost "/3/Predictions.json/models/#{encodeURIComponent modelKey}/frames/#{encodeURIComponent frameKey}", {}, go
    else if modelKey
      doGet "/3/ModelMetrics.json/models/#{encodeURIComponent modelKey}", go
    else if frameKey
      doGet "/3/ModelMetrics.json/frames/#{encodeURIComponent frameKey}", go
    else
      doGet "/3/ModelMetrics.json", go

  requestObjects = (type, go) ->
    go null, Flow.LocalStorage.list type

  requestObject = (type, id, go) ->
    go null, Flow.LocalStorage.read type, id

  requestDeleteObject = (type, id, go) ->
    go null, Flow.LocalStorage.purge type, id

  requestPutObject = (type, id, obj, go) ->
    go null, Flow.LocalStorage.write type, id, obj

  requestCloud = (go) ->
    doGet '/1/Cloud.json', go

  requestTimeline = (go) ->
    doGet '/2/Timeline.json', go

  requestProfile = (depth, go) ->
    doGet "/2/Profiler.json?depth=#{depth}", go

  requestStackTrace = (go) ->
    doGet '/2/JStack.json', go

  requestRemoveAll = (go) ->
    doGet '/3/RemoveAll.json', go

  requestLogFile = (nodeIndex, go) ->
    doGet "/3/Logs.json/nodes/#{nodeIndex}/files/default", go

  requestAbout = (go) ->
    doGet '/3/About.json', go

  link _.requestGet, doGet
  link _.requestPost, doPost
  link _.requestInspect, requestInspect
  link _.requestCreateFrame, requestCreateFrame
  link _.requestFrames, requestFrames
  link _.requestFrame, requestFrame
  link _.requestColumnSummary, requestColumnSummary
  link _.requestJobs, requestJobs
  link _.requestJob, requestJob
  link _.requestFileGlob, requestFileGlob
  link _.requestImportFiles, requestImportFiles
  link _.requestImportFile, requestImportFile
  link _.requestParseSetup, requestParseSetup
  link _.requestParseFiles, requestParseFiles
  link _.requestModels, requestModels
  link _.requestModel, requestModel
  link _.requestModelBuilder, requestModelBuilder
  link _.requestModelBuilders, requestModelBuilders
  link _.requestModelBuild, requestModelBuild
  link _.requestModelInputValidation, requestModelInputValidation
  link _.requestPredict, requestPredict
  link _.requestPrediction, requestPrediction
  link _.requestPredictions, requestPredictions
  link _.requestObjects, requestObjects
  link _.requestObject, requestObject
  link _.requestDeleteObject, requestDeleteObject
  link _.requestPutObject, requestPutObject
  link _.requestCloud, requestCloud
  link _.requestTimeline, requestTimeline
  link _.requestProfile, requestProfile
  link _.requestStackTrace, requestStackTrace
  link _.requestRemoveAll, requestRemoveAll
  link _.requestLogFile, requestLogFile
  link _.requestAbout, requestAbout


