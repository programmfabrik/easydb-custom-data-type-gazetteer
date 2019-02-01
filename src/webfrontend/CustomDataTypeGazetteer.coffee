class CustomDataTypeGazetteer extends CustomDataType

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
		[searchInput, displayOutput] = @__initForm(initData)

		setContent = =>
			searchInput.start()
			displayOutput.start()

		@__fillMissingData(initData).done(setContent)

		new CUI.VerticalList(content: [searchInput, displayOutput])

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
		searchData = q: ""
		resultsContainer = "results"
		loadingContainer = "loading"
		noResultsContainer = "no_results"
		loadingLabel = new LocaLabel(loca_key: "autocompletion.loading", padded: true)
		noResultsLabel = new LocaLabel(loca_key: "custom.data.type.gazetteer.search.no-results", padded: true)

		searchField = new CUI.Input
			name: "q"
			hidden: true
			placeholder: $$("custom.data.type.gazetteer.search.placeholder")
			maximize_horizontal: true
			data: searchData
			onDataChanged: =>
				CUI.scheduleCallback
					ms: 200
					call: search

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
					node: searchField
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
			searchData.q = ""
			ez5.GazetteerUtil.setObjectData(formData, object)

		searchXHR = null
		search = =>
			searchXHR?.abort()
			autocompletionPopup.emptyContainer(resultsContainer)
			autocompletionPopup.emptyContainer(loadingContainer)
			autocompletionPopup.emptyContainer(noResultsContainer)
			if searchData.q.length == 0 # Trigger search when it is not empty.
				return

			autocompletionPopup.getContainer(loadingContainer).replace(loadingLabel)
			autocompletionPopup.show()

			searchXHR = new CUI.XHR
				method: "GET"
				url: ez5.GazetteerUtil.SEARCH_API_URL + CUI.encodeUrlData(formData)

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
									node: searchField
									type: "editor-changed"

								return
			)

		if CUI.util.isEmpty(formData)
			searchField.show()
		else
			showOutputField()

		[searchField, outputField]

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
		ez5.GazetteerUtil.setObjectData(object, data)
		@__renderCard(object, false, null, true)

	__renderCard: (data, editor = false, onDelete, small = false) ->
		link = ez5.GazetteerUtil.PLACE_URL + data.gazId

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
		]

		if data.types
			types = []
			for type in data.types
				types.push $$("custom.data.type.gazetteer.types.#{type}.text")
			content.push new CUI.Label(text: types.join(", "), appearance: "secondary")

		list = new CUI.VerticalList(content: content)

		if small
			return list
		else
			plugin = ez5.pluginManager.getPlugin("custom-data-type-gazetteer")
			previewImage = new Image()
			previewImage.src = plugin.getBaseURL() + plugin.getWebfrontend().logo

			return new CUI.HorizontalLayout(
				class: "ez5-field-object ez5-custom-data-type-gazetteer-card"
				left:
					content: previewImage
				center:
					content: list
				right:
					content: menuButton
			)

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
			ez5.GazetteerUtil.searchById(data.gazId).done((dataFound) =>
				ez5.GazetteerUtil.setObjectData(data, dataFound)
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