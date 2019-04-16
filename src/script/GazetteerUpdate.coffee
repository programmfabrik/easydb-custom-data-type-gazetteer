class GazetteerUpdate

	__startup: ({server_config, plugin_config}) ->
		# TODO: do some checks, maybe check if the library server is reachable
		returnSuccess("OK")

	__updateData: ({objects, plugin_config}) ->
		objectsMap = {}
		searchIds = []
		for object in objects
			if not (object.identifier and object.data)
				continue

			gazId = object.data.gazId
			if not gazId
				continue

			if not objectsMap[gazId]
				objectsMap[gazId] = [] # It is possible to  have more than one object with the same ID in different objects.
			objectsMap[gazId].push(object)

			searchIds.push("_id:#{gazId}")

		timeout = plugin_config.update?.timeout or 0
		timeout *= 1000 # The configuration is in seconds, so it is multiplied by 1000 to get milliseconds.

		searchQuery = searchIds.join(" OR ")
		searchQuery = CUI.encodeURIComponentNicely(searchQuery)
		ez5.GazetteerUtil.searchByQuery(searchQuery, timeout: timeout).done((data) =>
			objectsToUpdate = []
			gazObjects = data.result
			for gazObject in gazObjects
				gazObject = ez5.GazetteerUtil.setObjectData({}, gazObject)

				for _object in objectsMap[gazObject.gazId]
					if not @__hasChanges(_object.data, gazObject)
						continue
					_object = ez5.GazetteerUtil.getSaveDataObject(gazObject) # Update the object that has changes.
					objectsToUpdate.push(_object)

			returnSuccess(objectsToUpdate)
		).fail((e) =>
			returnError("Error in search of gazetteer objects. Query: #{searchQuery}. Error: " + e)
		)

	__hasChanges: (objectOne, objectTwo) ->
		for key in ["displayName", "gazId", "otherNames", "types", "position", "iconName"]
			if not CUI.util.isEqual(objectOne[key], objectTwo[key])
				return true
		return false

	call: (data) ->
		if not data
			returnError("Payload is missing")
			return

		for key in ["action", "server_config", "plugin_config"]
			if (!data[key])
				returnError("key #{key} missing")
				return

		if (data.action == "startup")
			@__startup(data)
			return

		else if (data.action == "update")
			if (!data.objects)
				returnError("for update: key 'objects' missing")
				return

			if (!(data.objects instanceof Array))
				returnError("for update: invalid key 'objects': must be array")
				return

			# TODO: check validity of config, plugin (timeout), objects...
			@__updateData(data)
			return
		else
			returnError("invalid action " + data.action)


module.exports = new GazetteerUpdate()