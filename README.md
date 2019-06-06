# Custom data type gazetteer

This is a [custom data type](https://docs.easydb.de/en/technical/plugins/customdatatype/) for [easydb](https://docs.easydb.de/en/).

This custom data type consumes the [iDAI.gazetteer](https://gazetteer.dainst.org) API and provides an input that can be used to search by name or ID.

### Data structure
```json
{
        "displayName": "Buenos Aires",
        "iconName": "fa-map",
        "gazId": "2087760",
        "position": {
            "lat": -34.61315,
            "lng": -58.37723
        },
        "types": [
            "populated-place"
        ],
        "otherNames": [
                            {
                                "language": "ell",
                                "title": "Μπουένος Άιρες"
                            },
                            {
                                "language": "ara",
                                "title": "بوينس آيرس"
                            },
                            {
                                "language": "zho",
                                "title": "布宜诺斯艾利斯"
                            },
                            {
                                "language": "spa",
                                "title": "Buenos Aires"
                            },
                            {
                                "language": "rus",
                                "title": "Буэнос-Айрес"
                            },
                            {
                                "language": "spa",
                                "title": "Santa María del Buen Ayre"
                            },
                            {
                                "language": "spa",
                                "title": "Ciudad de La Santísima Trinidad y Puerto de Santa María del Buen Ayre"
                            },
                            {
                                "language": "spa",
                                "title": "Baires"
                            },
                            {
                                "language": "lat",
                                "title": "Bonaëropolis"
                            },
                            {
                                "language": "zho",
                                "title": "布宜諾斯艾利斯"
                            },
                            {
                                "language": "eng",
                                "title": "Buenos Aires"
                            },
                            {
                                "language": "ell",
                                "title": "Μπουένος ΄Aιρες"
                            },
                            {
                                "language": "spa",
                                "title": "Ciudad Autónoma de Buenos Aires"
                            },
                            {
                                "language": "ita",
                                "title": "Buenos Aires"
                            },
                            {
                                "language": "fra",
                                "title": "Buenos Aires"
                            },
                            {
                                "language": "por",
                                "title": "Buenos Aires"
                            },
                            {
                                "language": "deu",
                                "title": "Buenos Aires"
                            }
        ],
        "_fulltext": {
                    "text": [
                        "Μπουένος Άιρες",
                        "بوينس آيرس",
                        "布宜诺斯艾利斯",
                        "Buenos Aires",
                        "Буэнос-Айрес",
                        "Santa María del Buen Ayre",
                        "Ciudad de La Santísima Trinidad y Puerto de Santa María del Buen Ayre",
                        "Baires",
                        "Bonaëropolis",
                        "布宜諾斯艾利斯",
                        "Buenos Aires",
                        "Μπουένος ΄Aιρες",
                        "Ciudad Autónoma de Buenos Aires",
                        "Buenos Aires",
                        "Buenos Aires",
                        "Buenos Aires",
                        "Buenos Aires",
                        "Buenos Aires"
                    ],
                    "string": "2087760"
        },
        "_standard": {
            "text": "Buenos Aires"
        }
}
```

The keys [_fulltext and _standard](https://docs.easydb.de/en/technical/plugins/customdatatype/#general-keys) are used to search.

### Automatic update

This plugin uses the [automatic updater for custom data types](https://docs.easydb.de/en/technical/plugins/customdatatype/customdatatype_updater/) to update the data when the data provided by [iDAI.gazetteer](https://gazetteer.dainst.org) changes.

The update script runs at a specified interval of time that is configured using the YML file.

### Automatic updating and inserting of objects with Gazetteer fields

This plugin has the ability to automatically update and insert hierarchic objecttypes with Gazetteer fields.

When an object with a Gazetteer field, that is configured for this update in the base config (see below), the plugin reads the Gazetteer ID from a source field (or alternatively from the target field), the object and all its parents are requested from [iDAI.gazetteer](https://gazetteer.dainst.org).

The tree structure of the Gazetteer is mirrored. Missing parents are automatically created and inserted.

#### Base config

You can find the settings for this plugin at the "Gazetteer" tab of the base config.

* **Enabled**
    * Enable or disable the update for the selected objecttype
* **Object type**
    * Select a hierarchic objecttype from the dropdown menu
    * The objecttypes are prefiltered:
        * Only object types can be selected that have at least one Gazetteer type field
        * The object type must be hierarchical to map the hierarchical Gazetteer structure
        * No object types can be selected that have fields with constraints (apart from the target field), as the plugin cannot fulfill the constraints
* **Source field**
    * The field where the plugin reads the Gazetteer ID that is used for the search
    * Must be a text field
    * If it is not selected, the plugin will try to parse the ID from the target field, if it has been prefilled with custom data
* **Target field**
    * The field where the plugin writes the generated custom data
    * must be of type *Gazetteer*

#### Example

A hierarchic objecttype has been configured for the update:

* `gazetteer_data`
    * `gazetteer_id` (of type `text`)
    * `custom_data` (of custom type `gazetteer`)

`gazetteer_id` is configured as the source field, `custom_data` as the target field for the custom data that has been requested.

The following Gazetteer entries have already been inserted into the hierarchy:

* World ([ID `2042600`](https://gazetteer.dainst.org/place/2042600))
    * Europe ([ID `2044223`](https://gazetteer.dainst.org/place/2044223))
        * Germany ([ID `2044274`](https://gazetteer.dainst.org/place/2044274))
            * Berlin ([ID `2048564`](https://gazetteer.dainst.org/place/2048564))

----

**1)** A new `gazetteer_data` object with the Gazetteer [ID `2052755`](https://gazetteer.dainst.org/place/2052755) (for the city of Hamburg) in field `gazetteer_id` is inserted.

The plugin will search for the ID and find the custom data, as well as the parents. Since the parent *Germany* is already in the hierarchy, the new Object will be inserted directly at this position:

----

* World
    * Europe
        * Germany
            * Berlin
            * *Hamburg ([ID `2052755`](https://gazetteer.dainst.org/place/2052755))*

----

**2)** A new `gazetteer_data` object with the Gazetteer [ID `2347833`](https://gazetteer.dainst.org/place/2347833) (for the city of Hanoi in Vietnam) in field `gazetteer_id` is inserted.

After searching for the custom data and the parents, there is no direct parent for this Gazetteer entry yet. The plugin searches the deepest existing parent, in this case *World*. The missing parents *Asia* and *Vietnam* are created by the plugin and inserted into the tree:

----

* World
    * Europe
        * Germany
            * Berlin
            * Hamburg
    * **Asia ([ID `2042932`](https://gazetteer.dainst.org/place/2042932))**
        * **Vietnam ([ID `2281934`](https://gazetteer.dainst.org/place/2281934))**
            * *Hanoi ([ID `2347833`](https://gazetteer.dainst.org/place/2347833))*
----
