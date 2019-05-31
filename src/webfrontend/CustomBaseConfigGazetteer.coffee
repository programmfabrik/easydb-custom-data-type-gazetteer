class CustomBaseConfigGazetteer extends BaseConfigPlugin
	getFieldDefFromParm: (baseConfig, fieldName, def) ->
		switch def.plugin_type
			when "objecttype"
				field = new ez5.ObjecttypeSelector
					form: label: $$("custom.data.type.gazetteer.config.objecttype.label")
					name: fieldName
					show_name: true
					store_value: "fullname"
					filter: (objecttype) ->
						if CUI.util.isString(objecttype.table.id()) # Object types of connector instances.
							return false

						# The object type is only shown if at least one field is gazetteer.
						mask = Mask.getMaskByMaskName("_all_fields", objecttype.table.id())
						objecttype.addMask(mask)
						hasGazetteerField = objecttype.getFields().some((field) -> field instanceof CustomDataTypeGazetteer)
						if not hasGazetteerField
							return

						isRequired = objecttype.getFields().some((field) ->
							return field.isUnique() or field.isRequired()
						)
						return not isRequired
			when "field_from"
				field = new ez5.FieldSelector
					form: label: $$("custom.data.type.gazetteer.config.field_from.label")
					name: fieldName
					objecttype_data_key: "objecttype"
					store_value: "fullname"
					show_name: true
					filter: (field) ->
						not field.isSystemField() and not field.isTopLevelField() and
							not field.insideNested() and field not instanceof NestedTable
			when "field_to"
				field = new ez5.FieldSelector
					form: label: $$("custom.data.type.gazetteer.config.field_to.label")
					name: fieldName
					objecttype_data_key: "objecttype"
					store_value: "fullname"
					show_name: true
					filter: (fieldTo) =>
						return fieldTo instanceof CustomDataTypeGazetteer

		return field

ez5.session_ready =>
	BaseConfig.registerPlugin(new CustomBaseConfigGazetteer())