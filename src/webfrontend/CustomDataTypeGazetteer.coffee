class CustomDataTypeGazetteer extends CustomDataType

	@SEARCH_API_URL = "https://gazetteer.dainst.org/search.json?limit=20&"
	@ID_API_URL = "https://gazetteer.dainst.org/doc/"
	@PLACE_URL = "https://gazetteer.dainst.org/place/"

	getCustomDataTypeName: ->
		"custom:base.custom-data-type-gazetteer.gazetteer"

	getCustomDataTypeNameLocalized: ->
		$$("custom.data.type.gazetteer.name")

	getCustomDataOptionsInDatamodelInfo: (custom_settings) ->
		return []

	renderEditorInput: (data) ->
		initData = @__initData(data)
		form = @__initForm(initData)
		form

	renderDetailOutput: (data, _, opts) ->
		initData = @__initData(data)

		linkButton = @__getButtonLink(initData)

		if CUI.Map.isValidPosition(initData.position)
			plugins = opts.detail.getPlugins()
			for plugin in plugins
				if plugin instanceof MapDetailPlugin
					mapPlugin = plugin
					break

			if mapPlugin
				mapPlugin.addMarker(position: initData.position)

		return linkButton

	renderFieldAsGroup: (_, __, opts) ->
		return opts.mode == 'editor' or opts.mode == 'editor-template'

	getSaveData: (data, save_data) ->
		data = data[@name()]
		if CUI.util.isEmpty(data)
			return save_data[@name()] = null

		if CUI.util.isEmpty(data.gazId) or CUI.util.isEmpty(data.displayName)
			return throw new InvalidSaveDataException()

		return save_data[@name()] =
			displayName: data.displayName
			gazId: data.gazId
			position: data.position

	__initForm: (formData) ->
		resultsContainer = "results"
		loadingContainer = "loading"
		loadingLabel = new LocaLabel(loca_key: "autocompletion.loading")

		searchField = new CUI.Input
			name: "q"
			form:
				label: $$("custom.data.type.gazetteer.search.label")

		searchById = =>
			if not formData.gazId
				return

			xhr = new CUI.XHR
				method: "GET"
				url: CustomDataTypeGazetteer.ID_API_URL + formData.gazId
				headers:
					"Accept": "application/json, text/plain, */*" # This is necessary by the API of Gazetteer.

			waitBlock.show()
			xhr.start().done((object) =>
				setObjectData(object)
			).fail( =>
				# If not found or error, the display name is false, to show a different message and invalid input.
				formData.displayName = false
			).always( =>
				idField.checkInput()

				CUI.Events.trigger
					node: form
					type: "editor-changed"

				outputField.reload()
				waitBlock.hide()
			)

		idField = new CUI.Input
			name: "gazId"
			form:
				label: $$("custom.data.type.gazetteer.id.label")
			checkInput: => not CUI.util.isEmpty(formData.displayName)
			onDataChanged: =>
				delete formData.displayName
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

		setObjectData = (object) =>
			if not object
				formData.q = ""
				delete formData.displayName
				delete formData.gazId
				delete formData.position
			else
				formData.q = ""
				formData.displayName = object.prefName.title
				formData.gazId = object.gazId

				if object.prefLocation?.coordinates
					position =
						lng: object.prefLocation?.coordinates[0]
						lat: object.prefLocation?.coordinates[1]

					if CUI.Map.isValidPosition(position)
						formData.position = position

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
						item = autocompletionPopup.appendItem(resultsContainer, new CUI.Label(text: object.gazId + " - " + object.prefName.title))
						CUI.Events.listen
							type: "click"
							node: item
							call: (ev) =>
								ev.stopPropagation()

								setObjectData(object)

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

		form.start()
		form

	__initData: (data) ->
		if not data[@name()]
			initData = {}
			data[@name()] = initData
		else
			initData = data[@name()]
		initData

	__getOutputFieldElement: (formData) ->
		if formData.displayName and formData.gazId
			return @__getButtonLink(formData)
		else if CUI.util.isFalse(formData.displayName)
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.id-not-found"), class: "ez-label-invalid")
		else
			return new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.empty-label"))


	__getButtonLink: (initData) ->
		link = CustomDataTypeGazetteer.PLACE_URL + initData.gazId

		if initData.displayName
			text = $$("custom.data.type.gazetteer.preview.value",
				displayName: initData.displayName
				id: initData.gazId
			)
		else
			text = link

		return new CUI.ButtonHref
			appearance: "link"
			text: text
			href: link
			target: "_blank"

	isPluginSupported: (plugin) ->
		if plugin instanceof MapDetailPlugin
			return true
		return false

CustomDataType.register(CustomDataTypeGazetteer)