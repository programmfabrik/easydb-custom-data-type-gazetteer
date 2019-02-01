class ez5.GazetteerUtil

	@SEARCH_API_URL = "https://gazetteer.dainst.org/search.json?limit=20&"
	@ID_API_URL = "https://gazetteer.dainst.org/doc/"
	@PLACE_URL = "https://gazetteer.dainst.org/place/"
	@JSON_EXTENSION = ".json"

	@searchById: (id) ->
		xhr = new CUI.XHR
			method: "GET"
			url: ez5.GazetteerUtil.ID_API_URL + id + ez5.GazetteerUtil.JSON_EXTENSION
		return xhr.start()

	# Set the necessary attributes from gazetteer *data* to *object*
	@setObjectData: (object, data) ->
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