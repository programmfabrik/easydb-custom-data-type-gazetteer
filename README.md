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

This plugin uses the [automatic updater for custom data types](https://docs.easydb.de/en/technical/plugins/customdatatype/customdatatype_updater/) to update the data when the data provided by iDAI.gazetteer changes.

The update script runs at a specified interval of time that is configured using the YML file.
