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
			outputFieldElement = @__renderOutput(initData)
			CUI.dom.replace(content, outputFieldElement)
			waitBlock.destroy()

			if CUI.Map.isValidPosition(initData.position) and opts.detail
				plugins = opts.detail.getPlugins()
				for plugin in plugins
					if plugin instanceof MapDetailPlugin
						mapPlugin = plugin
						break

				if mapPlugin
					mapPlugin.addMarker(position: initData.position, iconName: initData.iconName, iconColor: "#6786ad")

		waitBlock.show()
		@__fillMissingData(initData).done(setContent)

		CUI.Events.listen
			type: "map-detail-click-location"
			node: content
			call: (_, info) =>
				if info.data?.position == initData.position
					CUI.dom.scrollIntoView(content)

		return content

	renderFieldAsGroup: ->
		return false

	getSaveData: (data, save_data) ->
		data = data[@name()]
		if CUI.util.isEmpty(data)
			return save_data[@name()] = null

		if CUI.util.isEmpty(data.gazId)
			return save_data[@name()] = null

		if data.notFound
			return throw new InvalidSaveDataException()

		fulltext = data.displayName
		if data.otherNames?.length > 0
			fulltext = data.otherNames.map((otherName) -> otherName.title).concat(fulltext)

		return save_data[@name()] =
			displayName: data.displayName
			gazId: data.gazId
			position: data.position
			iconName: data.iconName
			otherNames: data.otherNames
			types: data.types
			_fulltext:
				text: fulltext
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
		noResultsContainer = "no_results"
		loadingLabel = new LocaLabel(loca_key: "autocompletion.loading", padded: true)
		noResultsLabel = new LocaLabel(loca_key: "custom.data.type.gazetteer.search.no-results", padded: true)

		searchField = new CUI.Input
			name: "q"
			hidden: true
			placeholder: $$("custom.data.type.gazetteer.search.placeholder")

		autocompletionPopup = new AutocompletionPopup
			element: searchField
			onHide: =>
				autocompletionPopup.hide()
		autocompletionPopup.addContainer(resultsContainer)
		autocompletionPopup.addContainer(loadingContainer)
		autocompletionPopup.addContainer(noResultsContainer)

		outputDiv = CUI.dom.div()
		outputField = new CUI.DataFieldProxy
			name: "displayName"
			hidden: true
			element: outputDiv

		showOutputField = =>
			card = @__renderCard(formData, true, =>
				searchField.show()
				outputField.hide()
				cleanData()

				CUI.Events.trigger
					node: form
					type: "editor-changed"
			)
			CUI.dom.replace(outputDiv, card)
			outputField.show()

		cleanData = =>
			delete formData.displayName
			delete formData.gazId
			delete formData.otherNames
			delete formData.types
			delete formData.position
			delete formData.iconName

		setData = (object) =>
			formData.q = ""
			@__setObjectData(formData, object)

		searchXHR = null
		search = =>
			searchXHR?.abort()
			autocompletionPopup.emptyContainer(resultsContainer)
			autocompletionPopup.emptyContainer(loadingContainer)
			autocompletionPopup.emptyContainer(noResultsContainer)
			if formData.q.length == 0 # Trigger search when it is not empty.
				return

			autocompletionPopup.getContainer(loadingContainer).replace(loadingLabel)
			autocompletionPopup.show()

			searchXHR = new CUI.XHR
				method: "GET"
				url: CustomDataTypeGazetteer.SEARCH_API_URL + CUI.encodeUrlData(formData)

			searchXHR.start().done((data) =>
				autocompletionPopup.emptyContainer(loadingContainer)
				if data.result?.length == 0
					autocompletionPopup.getContainer(noResultsContainer).replace(noResultsLabel)
					return

				for object in data.result
					do(object) =>
						item = autocompletionPopup.appendItem(resultsContainer,
							@__renderAutocompleteCard(object)
						)
						CUI.Events.listen
							type: "click"
							node: item
							call: (ev) =>
								ev.stopPropagation()

								if object
									setData(object)
								else
									cleanData()

								searchField.hide()
								showOutputField()

								autocompletionPopup.hide()
								CUI.Events.trigger
									node: form
									type: "editor-changed"

								return
			)

		if CUI.util.isEmpty(formData)
			searchField.show()
		else
			showOutputField()

		form = new CUI.Form
			maximize_horizontal: true
			fields: [
				searchField
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
		object.otherNames = data.names
		object.types = data.types or []

		if data.prefLocation?.coordinates
			position =
				lng: data.prefLocation?.coordinates[0]
				lat: data.prefLocation?.coordinates[1]

			if CUI.Map.isValidPosition(position)
				object.position = position
				object.iconName = if data.prefLocation then "fa-map" else "fa-map-marker"

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

	__renderOutput: (formData) ->
		if formData.notFound
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.id-not-found"), class: "ez-label-invalid")
		if formData.gazId
			return @__renderCard(formData)
		else
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.empty-label"))

	__renderAutocompleteCard: (data) ->
		object = {}
		@__setObjectData(object, data)
		@__renderCard(object, false, null, true)

	__renderCard: (data, editor = false, onDelete, small = false) ->
		link = CustomDataTypeGazetteer.PLACE_URL + data.gazId

		menuItems = [
			new LocaButtonHref
				loca_key: "custom.data.type.gazetteer.link.button"
				href: link
				target: "_blank"
		]

		if not small
			if CUI.Map.isValidPosition(data.position)
				menuItems.push(
					new LocaButton
						loca_key: "custom.data.type.gazetteer.preview.button"
						onClick: =>
							previewPopover = new CUI.Popover
								element: menuButton
								placement: "sw"
								pane: @__buildPreviewMap(data.position, data.iconName)
								onHide: =>
									previewPopover.destroy()
							previewPopover.show()
				)

			if editor
				menuItems.push(
					new LocaButton
						loca_key: "custom.data.type.gazetteer.delete.button"
						onClick: =>
							onDelete?()
				)

			menuButton = new LocaButton
				loca_key: "custom.data.type.gazetteer.menu.button"
				icon: "ellipsis_v"
				icon_right: false
				appearance: "flat"
				menu:
					items: menuItems

		content = [
			new CUI.Label(text: data.displayName, appearance: "title", multiline: true)
		,
			new CUI.Label(text: data.gazId, appearance: "secondary", multiline: true)
		]

		if data.types
			for type in data.types
				content.push(
					new CUI.Label(text: $$("custom.data.type.gazetteer.types.#{type}.text"), appearance: "muted", multiline: true)
				)

		if data.otherNames?.length > 0
			otherNamesText = data.otherNames.map((otherName) => otherName.title).join(", ")
			content.push(
				new CUI.Label(text: otherNamesText, appearance: "muted", multiline: true)
			)

		layoutOpts =
			class: "ez5-field-object ez5-custom-data-type-gazetteer-card"
			center:
				content: new CUI.VerticalList(content: content)

		if not small
			plugin = ez5.pluginManager.getPlugin("custom-data-type-gazetteer")
			previewImage = new Image()
			previewImage.src = plugin.getBaseURL() + plugin.getWebfrontend().logo

			# layoutOpts.left = content: previewImage
			layoutOpts.right = content: menuButton

		return new CUI.HorizontalLayout(layoutOpts)

	__buildPreviewMap: (position, iconName) ->
		return new CUI.MapInput.defaults.mapClass(
			selectedMarkerPosition: position
			selectedMarkerOptions:
				iconName: iconName
				iconColor: "#6786ad"
			centerPosition: position
			clickable: false
			zoom: 10
		)

	# This is the case that the ID is in the data but it was not found before.
	__fillMissingData: (data) ->
		if data.gazId and (not data.displayName or not data.types)
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