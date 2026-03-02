ADDON   := PIHelper
VERSION := $(shell grep '## Version' $(ADDON).toc | sed 's/.*: //')
OUTDIR  := dist
ZIPNAME := $(ADDON)-$(VERSION).zip

WOW_ADDONS := $(HOME)/.steam/steam/steamapps/compatdata/2832488321/pfx/drive_c/Program\ Files\ \(x86\)/World\ of\ Warcraft/_retail_/Interface/AddOns

.PHONY: release deploy clean

release: clean
	@echo "Building $(ZIPNAME)..."
	@mkdir -p $(OUTDIR)/$(ADDON)
	@cp *.lua *.toc $(OUTDIR)/$(ADDON)/
	@cd $(OUTDIR) && zip -r $(ZIPNAME) $(ADDON)/
	@rm -rf $(OUTDIR)/$(ADDON)
	@echo "Created $(OUTDIR)/$(ZIPNAME)"

deploy:
	@echo "Deploying to WoW AddOns..."
	@DEST="$(WOW_ADDONS)/$(ADDON)"; \
	mkdir -p "$$DEST"; \
	cp *.lua *.toc "$$DEST/"; \
	echo "Deployed to $$DEST"

clean:
	@rm -rf $(OUTDIR)
