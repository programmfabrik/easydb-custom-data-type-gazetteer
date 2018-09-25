class CustomDataTypeGazetteer extends CustomDataType

	@SEARCH_API_URL = "https://gazetteer.dainst.org/search.json?limit=20&"
	@ID_API_URL = "https://gazetteer.dainst.org/doc/"
	@PLACE_URL = "https://gazetteer.dainst.org/place/"
	@JSON_EXTENSION = ".json"

	getCustomDataTypeName: ->
		"custom:base.custom-data-type-gazetteer.gazetteer"

	getCustomDataTypeNameLocalized: ->
		$$("custom.data.type.gazetteer.name")

	getCustomDataOptionsInDatamodelInfo: (custom_settings) ->
		return []

	supportsStandard: ->
		true

	renderSearchInput: (data, opts={}) ->
		return new SearchToken(
			column: @
			data: data
			fields: opts.fields
		).getInput().DOM

	getFieldNamesForSearch: ->
		@__getFieldNames()

	getFieldNamesForSuggest: ->
		@__getFieldNames()

	renderEditorInput: (data) ->
		initData = @__initData(data)
		form = @__initForm(initData)

		setContent = =>
			form.start()

		@__fillMissingData(initData).done(setContent)

		form

	renderDetailOutput: (data, _, opts) ->
		initData = @__initData(data)

		content = CUI.dom.div()
		waitBlock = new CUI.WaitBlock(element: content)

		setContent = =>
			outputFieldElement = @__getOutputFieldElement(initData)
			CUI.dom.replace(content, outputFieldElement)
			waitBlock.destroy()

			if CUI.Map.isValidPosition(initData.position)
				plugins = opts.detail.getPlugins()
				for plugin in plugins
					if plugin instanceof MapDetailPlugin
						mapPlugin = plugin
						break

				if mapPlugin
					mapPlugin.addMarker(position: initData.position)

		waitBlock.show()
		@__fillMissingData(initData).done(setContent)

		return content

	renderFieldAsGroup: (_, __, opts) ->
		return opts.mode == 'editor' or opts.mode == 'editor-template'

	getSaveData: (data, save_data) ->
		data = data[@name()]
		if CUI.util.isEmpty(data)
			return save_data[@name()] = null

		if CUI.util.isEmpty(data.gazId)
			return save_data[@name()] = null

		if data.notFound
			return throw new InvalidSaveDataException()

		return save_data[@name()] =
			displayName: data.displayName
			gazId: data.gazId
			position: data.position
			_fulltext:
				text: data.displayName
				string: data.gazId
			_standard:
				text: data.displayName

	getQueryFieldBadge: (data) =>
		if data["#{@name()}:unset"]
			value = $$("text.column.badge.without")
		else
			value = data[@name()]

		name: @nameLocalized()
		value: value

	getSearchFilter: (data, key=@name()) ->
		if data[key+":unset"]
			filter =
				type: "in"
				fields: [ @fullName()+".displayName" ]
				in: [ null ]
			filter._unnest = true
			filter._unset_filter = true
			return filter

		filter = super(data, key)
		if filter
			return filter

		if CUI.util.isEmpty(data[key])
			return

		val = data[key]
		[str, phrase] = Search.getPhrase(val)

		switch data[key+":type"]
			when "token", "fulltext", undefined
				filter =
					type: "match"
					mode: data[key+":mode"]
					fields: @getFieldNamesForSearch()
					string: str
					phrase: phrase

			when "field"
				filter =
					type: "in"
					fields: @getFieldNamesForSearch()
					in: [ str ]
		filter

	__getFieldNames: ->
		return [
			@fullName()+".gazId"
			@fullName()+".displayName"
		]

	__initForm: (formData) ->
		resultsContainer = "results"
		loadingContainer = "loading"
		loadingLabel = new LocaLabel(loca_key: "autocompletion.loading")

		searchField = new CUI.Input
			name: "q"
			form:
				label: $$("custom.data.type.gazetteer.search.label")

		searchById = =>
			triggerUpdate = ->
				idField.checkInput()

				CUI.Events.trigger
					node: form
					type: "editor-changed"

				outputField.reload()
				waitBlock.hide()

			if formData.gazId.length == 0
				triggerUpdate()
				return

			waitBlock.show()
			@__searchById(formData.gazId).done((object) =>
				cleanFormSetData(object)
			).fail( =>
				formData.notFound = true
			).always(triggerUpdate)

		idField = new CUI.Input
			name: "gazId"
			form:
				label: $$("custom.data.type.gazetteer.id.label")
			checkInput: => not CUI.util.isEmpty(formData.displayName)
			onDataChanged: =>
				delete formData.displayName
				delete formData.notFound

				CUI.scheduleCallback
					call: searchById
					ms: 300

		outputField = new CUI.DataFieldProxy
			name: "displayName"
			form:
				label: $$("custom.data.type.gazetteer.preview.label")
			element: => @__getOutputFieldElement(formData)

		waitBlock = new CUI.WaitBlock(element: outputField)

		autocompletionPopup = new AutocompletionPopup
			element: searchField
			onHide: =>
				autocompletionPopup.hide()
		autocompletionPopup.addContainer(resultsContainer)
		autocompletionPopup.addContainer(loadingContainer)

		cleanFormSetData = (object) =>
			formData.q = ""
			if not object
				delete formData.displayName
				delete formData.gazId
				delete formData.position
			else
				@__setObjectData(formData, object)

		search = =>
			autocompletionPopup.emptyContainer(resultsContainer)
			if formData.q.length < 2 # Trigger search with more than 2 characters.
				return

			autocompletionPopup.getContainer(loadingContainer).replace(loadingLabel)

			searchXHR = new CUI.XHR
				method: "GET"
				url: CustomDataTypeGazetteer.SEARCH_API_URL + CUI.encodeUrlData(formData)

			searchXHR.start().done((data) =>
				autocompletionPopup.emptyContainer(loadingContainer)
				if data.result?.length == 0
					return

				for object in data.result
					do(object) =>
						item = autocompletionPopup.appendItem(resultsContainer,
							new LocaLabel
								loca_key: "custom.data.type.gazetteer.search.result.md"
								loca_key_attrs: object
								markdown: true
						)
						CUI.Events.listen
							type: "click"
							node: item
							call: (ev) =>
								ev.stopPropagation()

								cleanFormSetData(object)

								searchField.reload()
								idField.reload()
								outputField.reload()

								autocompletionPopup.hide()
								CUI.Events.trigger
									node: form
									type: "editor-changed"

								return
				autocompletionPopup.show()
			)

		form = new CUI.Form
			maximize_horizontal: true
			fields: [
				searchField
			,
				idField
			,
				outputField
			]
			data: formData
			onDataChanged: =>
				CUI.scheduleCallback
					ms: 200
					call: search

		form

	# Set the necessary attributes from gazetteer *data* to *object*
	__setObjectData: (object, data) ->
		delete object.notFound
		object.displayName = data.prefName.title
		object.gazId = data.gazId

		if data.prefLocation?.coordinates
			position =
				lng: data.prefLocation?.coordinates[0]
				lat: data.prefLocation?.coordinates[1]

			if CUI.Map.isValidPosition(position)
				object.position = position

	__searchById: (id) ->
		xhr = new CUI.XHR
			method: "GET"
			url: CustomDataTypeGazetteer.ID_API_URL + id + CustomDataTypeGazetteer.JSON_EXTENSION
		return xhr.start()

	__initData: (data) ->
		if not data[@name()]
			initData = {}
			data[@name()] = initData
		else
			initData = data[@name()]
		initData

	__getOutputFieldElement: (formData) ->
		if formData.notFound
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.id-not-found"), class: "ez-label-invalid")
		if formData.gazId
			return @__getButtonLink(formData)
		else
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.empty-label"))

	__getButtonLink: (initData) ->
		link = CustomDataTypeGazetteer.PLACE_URL + initData.gazId

		if initData.displayName
			text = $$("custom.data.type.gazetteer.preview.value", initData)
		else
			text = link

		return new CUI.ButtonHref
			appearance: "link"
			text: text
			href: link
			target: "_blank"

	# This is the case that the ID is in the data but it was not found before.
	__fillMissingData: (data) ->
		if data.gazId and not data.displayName
			deferred = new CUI.Deferred()
			@__searchById(data.gazId).done((dataFound) =>
				@__setObjectData(data, dataFound)
			).fail( =>
				data.notFound = true
			).always(deferred.resolve)
			return deferred.promise()
		else
			return CUI.resolvedPromise()

	isPluginSupported: (plugin) ->
		if plugin instanceof MapDetailPlugin
			return true
		return false

CustomDataType.register(CustomDataTypeGazetteer)