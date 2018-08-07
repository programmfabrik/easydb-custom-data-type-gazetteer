class CustomDataTypeGazetteer extends CustomDataType

	@API_URL = "https://gazetteer.dainst.org/search.json?limit=20&"
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

		return save_data[@name()] =
			displayName: data.displayName
			gazId: data.gazId
			position: data.position

	__initForm: (formData) ->
		resultsContainer = "results"
		loadingContainer = "loading"
		loadingLabel = new LocaLabel(loca_key: "autocompletion.loading")

		displayNameEmptyLabel = new CUI.EmptyLabel(text: $$("custom.data.type.gazetteer.preview.empty-label"))

		searchField = new CUI.Input
			name: "q"
			form:
				label: $$("custom.data.type.gazetteer.search.label")
		outputField = new CUI.DataFieldProxy
			name: "displayName"
			form:
				label: $$("custom.data.type.gazetteer.preview.label")
			element: =>
				if formData.displayName
					return @__getButtonLink(formData)
				else
					return displayNameEmptyLabel

		autocompletionPopup = new AutocompletionPopup
			element: searchField
			onHide: =>
				autocompletionPopup.hide()
		autocompletionPopup.addContainer(resultsContainer)
		autocompletionPopup.addContainer(loadingContainer)

		search = =>
			autocompletionPopup.emptyContainer(resultsContainer)
			if formData.q.length < 2 # Trigger search with more than 2 characters.
				return

			autocompletionPopup.getContainer(loadingContainer).replace(loadingLabel)

			searchXHR = new CUI.XHR
				method: "GET"
				url: CustomDataTypeGazetteer.API_URL + CUI.encodeUrlData(formData)

			searchXHR.start().done((data) =>
				autocompletionPopup.emptyContainer(loadingContainer)
				if data.result?.length == 0
					return

				for object in data.result
					do(object) =>
						if not object.prefLocation?.coordinates # Some results do not include the coordinates.
							return

						position =
							lng: object.prefLocation?.coordinates[0]
							lat: object.prefLocation?.coordinates[1]

						item = autocompletionPopup.appendItem(resultsContainer, new CUI.Label(text: object.prefName.title))
						CUI.Events.listen
							type: "click"
							node: item
							call: (ev) =>
								ev.stopPropagation()

								formData.q = ""
								formData.displayName = object.prefName.title
								formData.gazId = object.gazId
								if CUI.Map.isValidPosition(position)
									formData.position = position

								outputField.reload()
								searchField.reload()
								autocompletionPopup.hide()

								CUI.Events.trigger
									node: form
									type: "editor-changed"

								return
				autocompletionPopup.show()
			)

		form = new CUI.Form
			maximize_horizontal: true
			fields: [searchField, outputField]
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

	__getButtonLink: (initData) ->
		link = CustomDataTypeGazetteer.PLACE_URL + initData.gazId
		text = initData.displayName or link

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