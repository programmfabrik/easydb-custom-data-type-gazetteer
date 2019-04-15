PLUGIN_NAME = custom-data-type-gazetteer

EASYDB_LIB = easydb-library

L10N_FILES = l10n/$(PLUGIN_NAME).csv
L10N_GOOGLE_KEY = 1Z3UPJ6XqLBp-P8SUf-ewq4osNJ3iZWKJB83tc6Wrfn0
L10N_GOOGLE_GID = 1812781202
L10N2JSON = python $(EASYDB_LIB)/tools/l10n2json.py

INSTALL_FILES = \
	$(WEB)/l10n/cultures.json \
	$(WEB)/l10n/de-DE.json \
	$(WEB)/l10n/en-US.json \
	$(WEB)/l10n/es-ES.json \
	$(WEB)/l10n/it-IT.json \
	$(WEB)/image/logo.png \
	$(CSS) \
	$(JS) \
	CustomDataTypeGazetteer.config.yml

COFFEE_FILES = src/webfrontend/CustomDataTypeGazetteer.coffee \
	src/webfrontend/CasterGazetteer.coffee \
	src/webfrontend/GazetteerUtil.coffee

all: build

SCSS_FILES = src/webfrontend/scss/custom-data-type-gazetteer.scss

COPY_LOGO = $(WEB)/image/logo.png
$(WEB)/image%:
	cp -f $< $@

# Order of files is important.
UPDATE_SCRIPT_COFFEE_FILES = \
	src/webfrontend/GazetteerUtil.coffee \
	src/script/GazetteerUpdate.coffee
UPDATE_SCRIPT_BUILD_FILE = build/scripts/gazetteer-update.js

${UPDATE_SCRIPT_BUILD_FILE}: $(subst .coffee,.coffee.js,${UPDATE_SCRIPT_COFFEE_FILES})
	mkdir -p $(dir $@)
	cat $^ > $@

include $(EASYDB_LIB)/tools/base-plugins.make
build: code $(L10N) $(COPY_LOGO) $(UPDATE_SCRIPT_BUILD_FILE)

code: $(JS) css

clean: clean-base

wipe: wipe-base
