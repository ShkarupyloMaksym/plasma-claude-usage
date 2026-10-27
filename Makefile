# Plasma 6 widget "Claude Usage".
ID      := io.github.shkarupylomaksym.claudeusage
VERSION := $(shell python3 -c "import json;print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
OUT     := dist/claude-usage-$(VERSION).plasmoid

.PHONY: package install upgrade link uninstall test check view lint clean

package: $(OUT)            ## build the .plasmoid file for the KDE Store
$(OUT): $(shell find package -type f)
	@mkdir -p dist
	@rm -f $@
	cd package && zip -qr ../$@ . -x '*/__pycache__/*' '*.pyc'
	@echo "built $@"

install: package           ## install a copy for this user
	kpackagetool6 -t Plasma/Applet -i $(OUT)

upgrade: package           ## update an installed copy
	kpackagetool6 -t Plasma/Applet -u $(OUT)

link:                      ## development: Plasma uses this folder directly
	@mkdir -p ~/.local/share/plasma/plasmoids
	ln -sfn "$(CURDIR)/package" ~/.local/share/plasma/plasmoids/$(ID)

uninstall:
	kpackagetool6 -t Plasma/Applet -r $(ID) || rm -f ~/.local/share/plasma/plasmoids/$(ID)

test:                      ## the data script on its own
	python3 package/contents/code/claude_usage.py

# plasmoidviewer shows QML errors inside the widget, not on stderr, so check behaviour instead: a
# widget that loaded runs its data script, which writes the snapshot file. Each run gets its own
# empty XDG_STATE_HOME, so nothing else writing the shared file (e.g. claude-admin) can fake a pass.
check:                     ## load the widget headless (horizontal and vertical) and confirm it runs
	@for ff in horizontal vertical; do \
	  st=$$(mktemp -d); \
	  XDG_STATE_HOME=$$st QT_QPA_PLATFORM=offscreen timeout 9 plasmoidviewer -a ./package -f $$ff >/dev/null 2>&1; \
	  if [ -s $$st/claude-usage/usage.json ]; then echo "$$ff: loaded and ran"; rm -rf $$st; \
	  else echo "$$ff: FAILED to load (run 'make view' to see the error)"; rm -rf $$st; exit 1; fi; \
	done

view:                      ## open the widget in a window
	plasmoidviewer -a ./package -f horizontal

lint:
	@# qmllint exits non-zero on warnings about Plasma's own imports; show errors only.
	@qmllint -I /usr/lib/qt6/qml package/contents/ui/*.qml package/contents/config/*.qml 2>&1 | grep -i "error" || echo "qml: no errors"
	python3 -m py_compile package/contents/code/claude_usage.py

clean:
	rm -rf dist
