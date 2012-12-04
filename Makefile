# Makefile debugging hack: uncomment the two lines below and make will tell you
# more about what is happening.  The output generated is of the form
# "FILE:LINE [TARGET (DEPENDENCIES) (NEWER)]" where DEPENDENCIES are all the
# things TARGET depends on and NEWER are all the files that are newer than
# TARGET.  DEPENDENCIES will be colored green and NEWER will be blue.
#
#OLD_SHELL := $(SHELL)
#SHELL = $(warning [$@ [32m($^) [34m($?)[m ])$(OLD_SHELL)

JSFILES=$(shell bzr ls -RV -k file | \
	grep -E -e '.+\.js(on)?$$' | \
	grep -Ev -e '^manifest\.json$$' \
		-e '^test/assets/' \
		-e '^app/assets/javascripts/reconnecting-websocket.js$$' \
		-e '^server.js$$')

NODE_TARGETS=node_modules/chai node_modules/cryptojs node_modules/d3 \
	node_modules/expect.js node_modules/express node_modules/graceful-fs \
	node_modules/grunt node_modules/jshint node_modules/less \
	node_modules/minimatch node_modules/mocha node_modules/node-markdown \
	node_modules/node-minify node_modules/node-spritesheet \
	node_modules/rimraf node_modules/should node_modules/yui \
	node_modules/yuidocjs
EXPECTED_NODE_TARGETS=$(shell echo "$(NODE_TARGETS)" | tr ' ' '\n' | sort | tr '\n' ' ')

TEMPLATE_TARGETS=$(shell bzr ls -k file app/templates)
SPRITE_SOURCE_FILES=$(shell bzr ls -R -k file app/assets/images)
BUILD_ASSETS_DIR=build/juju-ui/assets
SPRITE_GENERATED_FILES=$(BUILD_ASSETS_DIR)/sprite.css \
	$(BUILD_ASSETS_DIR)/sprite.png
PRODUCTION_FILES=$(BUILD_ASSETS_DIR)/modules.js \
	$(BUILD_ASSETS_DIR)/config.js \
	$(BUILD_ASSETS_DIR)/app.js \
	$(BUILD_ASSETS_DIR)/all-yui.js \
	$(BUILD_ASSETS_DIR)/combined-css/all-static.css
DATE=$(shell date -u)
APPCACHE=$(BUILD_ASSETS_DIR)/manifest.appcache

show:
	echo $(JSFILES)
all: build

build/juju-ui/templates.js: $(TEMPLATE_TARGETS) bin/generateTemplates.js
	mkdir -p "$(BUILD_ASSETS_DIR)"
	bin/generateTemplates.js

yuidoc/index.html: node_modules/yuidocjs $(JSFILES)
	node_modules/.bin/yuidoc -o yuidoc -x assets app

yuidoc: yuidoc/index.html

$(SPRITE_GENERATED_FILES): node_modules/grunt node_modules/node-spritesheet \
		$(SPRITE_SOURCE_FILES)
	node_modules/grunt/bin/grunt spritegen

$(NODE_TARGETS): package.json
	npm install
	# Keep all targets up to date, not just new/changed ones.
	for dirname in $(NODE_TARGETS); do touch $$dirname ; done
	@# Check to see if we made what we expected to make, and warn if we did
	@# not. Note that we calculate FOUND_TARGETS here, in this way and not
	@# in the standard Makefile way, because we need to see what
	@# node_modules were created by this target.  Makefile variables and
	@# substitutions, even when using $(eval...) within a target, happen
	@# initially, before the target is run.  Therefore, if this were a
	@# simple Makefile variable, it  would be empty after a first run, and
	@# you would always see the warning message in that case.  We have to
	@# connect it to the "if" command with "; \" because Makefile targets
	@# are evaluated per line, with bash variables discarded between them.
	@# We compare the result with EXPECTED_NODE_TARGETS and not simply the
	@# NODE_TARGETS because this gives us normalization, particularly of the
	@# trailing whitespace, that we do not otherwise have.
	@FOUND_TARGETS=$$(find node_modules -maxdepth 1 -mindepth 1 -type d \
	-printf 'node_modules/%f ' | tr ' ' '\n' | grep -Ev '\.bin$$' \
	| sort | tr '\n' ' '); \
	if [ "$$FOUND_TARGETS" != "$(EXPECTED_NODE_TARGETS)" ]; then \
	echo; \
	echo "******************************************************************"; \
	echo "******************************************************************"; \
	echo "******************************************************************"; \
	echo "******************************************************************"; \
	echo "IMPORTANT: THE NODE_TARGETS VARIABLE IN THE MAKEFILE SHOULD CHANGE"; \
	echo "******************************************************************"; \
	echo "******************************************************************"; \
	echo "******************************************************************"; \
	echo "******************************************************************"; \
	echo; \
	echo "Change it to the following."; \
	echo; \
	echo $$FOUND_TARGETS; \
	fi

app/assets/javascripts/yui: node_modules/yui
	ln -sf "$(PWD)/node_modules/yui" app/assets/javascripts/

node_modules/d3/d3.v2.js node_modules/d3/d3.v2.min.js: node_modules/d3

app/assets/javascripts/d3.v2.js: node_modules/d3/d3.v2.js
	ln -sf "$(PWD)/node_modules/d3/d3.v2.js" app/assets/javascripts/d3.v2.js

app/assets/javascripts/d3.v2.min.js: node_modules/d3/d3.v2.min.js
	ln -sf "$(PWD)/node_modules/d3/d3.v2.min.js" \
	    app/assets/javascripts/d3.v2.min.js

javascript-libraries: app/assets/javascripts/yui \
	app/assets/javascripts/d3.v2.js app/assets/javascripts/d3.v2.min.js

gjslint: virtualenv/bin/gjslint
	virtualenv/bin/gjslint --strict --nojsdoc --jslint_error=all \
	    --custom_jsdoc_tags module,main,class,method,event,property,attribute,submodule,namespace,extends,config,constructor,static,final,readOnly,writeOnce,optional,required,param,return,for,type,private,protected,requires,default,uses,example,chainable,deprecated,since,async,beta,bubbles,extension,extensionfor,extension_for \
	    $(JSFILES)

jshint: node_modules/jshint
	node_modules/jshint/bin/hint $(JSFILES)

yuidoc-lint: $(JSFILES)
	bin/lint-yuidoc

lint: gjslint jshint yuidoc-lint

virtualenv/bin/gjslint virtualenv/bin/fixjsstyle:
	virtualenv virtualenv
	virtualenv/bin/easy_install archives/closure_linter-latest.tar.gz

beautify: virtualenv/bin/fixjsstyle
	virtualenv/bin/fixjsstyle --strict --nojsdoc --jslint_error=all $(JSFILES)

spritegen: $(SPRITE_GENERATED_FILES)

$(PRODUCTION_FILES): node_modules/yui node_modules/d3/d3.v2.min.js $(JSFILES) \
		bin/merge-files lib/merge-files.js
	rm -f $(PRODUCTION_FILES)
	mkdir -p "$(BUILD_ASSETS_DIR)/combined-css"
	bin/merge-files
	cp app/modules.js $(BUILD_ASSETS_DIR)/modules.js
	cp app/config.js $(BUILD_ASSETS_DIR)/config.js
	cp node_modules/yui/assets/skins/sam/rail-x.png \
	    "$(BUILD_ASSETS_DIR)/combined-css/rail-x.png"
	# Copy each YUI module's assets into the build directory where they
	# will be served.
	mkdir -p "$(BUILD_ASSETS_DIR)/combined-css"
	(cd node_modules/yui/ && \
	 cp -r --parents */assets "$(PWD)/$(BUILD_ASSETS_DIR)")

production-files: $(PRODUCTION_FILES)

prep: beautify lint

test: build
	./test-server.sh

debug: build
	@echo "Customize config.js to modify server settings"
	node server.js

server: build
	@echo "Running the application from a SimpleHTTPServer"
	cd build && python -m SimpleHTTPServer 8888

build-clean:
	rm -rf build

clean: build-clean
	rm -rf node_modules virtualenv
	make -C docs clean

build/index.html: app/index.html
	cp -f app/index.html build/

build/favicon.ico: app/favicon.ico
	cp -f app/favicon.ico build/

$(BUILD_ASSETS_DIR)/images: $(SPRITE_SOURCE_FILES)
	cp -rf app/assets/images $(BUILD_ASSETS_DIR)/images
	touch $@

$(BUILD_ASSETS_DIR)/svgs: $(shell bzr ls -R -k file app/assets/svgs)
	cp -rf app/assets/svgs $(BUILD_ASSETS_DIR)/svgs

build-images: build/favicon.ico $(BUILD_ASSETS_DIR)/images \
	$(BUILD_ASSETS_DIR)/svgs

build: appcache $(NODE_TARGETS) javascript-libraries  \
	build/juju-ui/templates.js yuidoc spritegen \
	production-files build/index.html build-images

$(APPCACHE): manifest.appcache.in
	mkdir -p "build/juju-ui/assets"
	cp manifest.appcache.in $(APPCACHE)
	sed -re 's/^\# TIMESTAMP .+$$/\# TIMESTAMP $(DATE)/' -i $(APPCACHE)

appcache: $(APPCACHE)

# A target used only for forcibly updating the appcache.
appcache-touch:
	touch manifest.appcache.in

# This is the real target.  appcache-touch needs to be executed before
# appcache, and this provides the correct order.
appcache-force: appcache-touch appcache

.PHONY: test lint beautify server clean build-images prep jshint gjslint \
	appcache appcache-touch appcache-force yuidoc spritegen yuidoc-lint \
	production-files javascript-libraries

.DEFAULT_GOAL := all
