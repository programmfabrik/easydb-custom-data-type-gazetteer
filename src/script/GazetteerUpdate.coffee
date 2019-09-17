class GazetteerUpdate

	__start_update: ({server_config, plugin_config}) ->
		# TODO: do some checks, maybe check if the library server is reachable
		ez5.respondSuccess({
			# NOTE:
			# 'state' object can contain any data the update script might need between updates.
			# the easydb server will save this and send it with any 'update' request
			state: {
				"start_update": new Date().toUTCString()
			}
		})

	__updateData: ({objects, plugin_config}) ->
		objectsMap = {}
		searchIds = []
		for object in objects
			if not (object.identifier and object.data)
				continue

			gazId = object.data.gazId
			if CUI.util.isEmpty(gazId)
				continue

			if not objectsMap[gazId]
				objectsMap[gazId] = [] # It is possible to  have more than one object with the same ID in different objects.
			objectsMap[gazId].push(object)

			searchIds.push("_id:#{gazId}")

		if searchIds.length == 0
			return ez5.respondSuccess({payload: []})

		timeout = plugin_config.update?.timeout or 0
		timeout *= 1000 # The configuration is in seconds, so it is multiplied by 1000 to get milliseconds.

		searchQuery = searchIds.join(" OR ")
		searchQuery = CUI.encodeURIComponentNicely(searchQuery)
		ez5.GazetteerUtil.searchByQuery(searchQuery, timeout: timeout).done((data) =>
			objectsToUpdate = []
			gazObjects = data.result
			for gazObject in gazObjects
				if not objectsMap[gazObject.gazId]
					continue

				gazObject = ez5.GazetteerUtil.setObjectData({}, gazObject)

				for _object in objectsMap[gazObject.gazId]
					if not @__hasChanges(_object.data, gazObject)
						continue
					_object.data = ez5.GazetteerUtil.getSaveDataObject(gazObject) # Update the object that has changes.
					objectsToUpdate.push(_object)

			ez5.respondSuccess({payload: objectsToUpdate})
		).fail((e) =>
			ez5.respondError("custom.data.type.gazeteer.update.error.generic", {searchQuery: searchQuery, error: e + ""})
		)

	__hasChanges: (objectOne, objectTwo) ->
		for key in ["displayName", "gazId", "otherNames", "types", "position", "iconName"]
			if not CUI.util.isEqual(objectOne[key], objectTwo[key])
				return true
		return false

	main: (data) ->
		if not data
			ez5.respondError("custom.data.type.gazeteer.update.error.payload-missing")
			return

		for key in ["action", "server_config", "plugin_config"]
			if (!data[key])
				ez5.respondError("custom.data.type.gazeteer.update.error.payload-key-missing", {key: key})
				return

		if (data.action == "start_update")
			@__start_update(data)
			return

		else if (data.action == "update")
			if (!data.objects)
				ez5.respondError("custom.data.type.gazeteer.update.error.objects-missing")
				return

			if (!(data.objects instanceof Array))
				ez5.respondError("custom.data.type.gazeteer.update.error.objects-not-array")
				return

			# NOTE: state for all batches
			# this contains any arbitrary data the update script might need between batches
			# it should be sent to the server during 'start_update' and is included in each batch
			if (!data.state)
				ez5.respondError("custom.data.type.gazeteer.update.error.state-missing")
				return

			# NOTE: information for this batch
			# this contains information about the current batch, espacially:
			#   - offset: start offset of this batch in the list of all collected values for this custom type
			#   - total: total number of all collected custom values for this custom type
			# it is included in each batch
			if (!data.batch_info)
				ez5.respondError("custom.data.type.gazeteer.update.error.batch_info-missing")
				return

			# TODO: check validity of config, plugin (timeout), objects...
			@__updateData(data)
			return
		else
			ez5.respondError("custom.data.type.gazeteer.update.error.invalid-action", {action: data.action})


module.exports = new GazetteerUpdate()