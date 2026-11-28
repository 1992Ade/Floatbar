TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = ClearShot

ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ClearShot
BUNDLE_NAME      = ClearShotModule ClearShotRecordModule
LIBRARY_NAME     = libClearShotHook libClearAllHook

# ============================================================================
# 1) The wrapper app — ClearShot.app (displayed as TrollBox). Root-UID via
# TrollStore's platform-application so it can copy the Control Center bundle
# into /Library/ControlCenter/Bundles/, install LaunchDaemons, write mobile-
# configs, etc. Private frameworks (StoreKitUI for AppRepack, Preferences for
# shared cells on AppRepack's Settings-style UI) are linked here.
# ============================================================================
ClearShot_FILES = $(wildcard ClearShot/*.m)
ClearShot_FRAMEWORKS = UIKit CoreGraphics QuartzCore Photos CoreLocation IOKit SystemConfiguration CoreServices Security MapKit
ClearShot_PRIVATE_FRAMEWORKS = StoreKitUI Preferences StoreServices
ClearShot_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-arc-performSelector-leaks
ClearShot_CODESIGN_FLAGS = -Sentitlements.plist
ClearShot_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk

# ============================================================================
# 2) The Control Center module bundle — ClearShotModule.bundle. Runs inside
# SpringBoard, which already has every entitlement we need for CARenderServer.
# No custom entitlements on the bundle itself.
# ============================================================================
ClearShotModule_FILES = $(wildcard ClearShotModule/*.m)
ClearShotModule_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics ImageIO Photos
ClearShotModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
ClearShotModule_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
ClearShotModule_INSTALL_PATH = /Library/ControlCenter/Bundles

# Second CC module bundle — the Record twin. Same install path, same
# ControlCenterUIKit dependency, plus AVFoundation + CoreVideo + CoreMedia
# for the AVAssetWriter pipeline.
ClearShotRecordModule_FILES = $(wildcard ClearShotRecordModule/*.m)
ClearShotRecordModule_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics ImageIO Photos AVFoundation CoreVideo CoreMedia IOSurface
ClearShotRecordModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
ClearShotRecordModule_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
ClearShotRecordModule_INSTALL_PATH = /Library/ControlCenter/Bundles

include $(THEOS_MAKE_PATH)/bundle.mk

# ============================================================================
# 3) Hook dylibs injected into SpringBoard via the Tweaks engine (TFInjector).
#    Both ship INSIDE ClearShot.app so the user can install them one tap
#    from the relevant section (ClearShot → Native gesture bypass;
#    SpringBoard Tweaks → Clear All).
# ============================================================================
libClearShotHook_FILES = HookDylib/ClearShotHook.m
libClearShotHook_FRAMEWORKS = UIKit QuartzCore CoreGraphics Photos IOSurface
libClearShotHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
libClearShotHook_INSTALL_PATH = /Applications

libClearAllHook_FILES = HookDylib/ClearAllHook.m
libClearAllHook_FRAMEWORKS = UIKit Foundation
libClearAllHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
libClearAllHook_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/library.mk

# ============================================================================
# Packaging. Theos stages:
#   $(THEOS_STAGING_DIR)/Applications/ClearShot.app
#   $(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/ClearShotModule.bundle
#
# We want the final .tipa to carry ONLY Payload/ClearShot.app, with the
# CC bundle and Ad Blocking assets embedded inside the .app — so first-launch
# install code can copy them where they need to go.
# ============================================================================
APP_BUNDLE     = $(THEOS_STAGING_DIR)/Applications/ClearShot.app
CC_BUNDLE      = $(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/ClearShotModule.bundle
CC_REC_BUNDLE  = $(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/ClearShotRecordModule.bundle
HOOK_SHOT      = $(THEOS_STAGING_DIR)/Applications/libClearShotHook.dylib
HOOK_CLEAR     = $(THEOS_STAGING_DIR)/Applications/libClearAllHook.dylib

after-stage::
	@echo "========== after-stage =========="
	@echo "Staged tree:"
	@find $(THEOS_STAGING_DIR) -maxdepth 4 -type d
	@# --- 1) Make sure both CC bundles carry their Info.plist.
	@if [ -f ClearShotModule/Info.plist ]; then \
	  cp -f ClearShotModule/Info.plist $(CC_BUNDLE)/Info.plist; \
	  echo "Copied ClearShotModule/Info.plist into the bundle."; \
	fi
	@if [ -f ClearShotRecordModule/Info.plist ] && [ -d "$(CC_REC_BUNDLE)" ]; then \
	  cp -f ClearShotRecordModule/Info.plist $(CC_REC_BUNDLE)/Info.plist; \
	  echo "Copied ClearShotRecordModule/Info.plist into the bundle."; \
	fi
	@# --- 2) Embed both CC bundles inside the .app so the app can install
	@# them at runtime (needs TrollStore root perms to write /Library/...).
	@if [ -d "$(CC_BUNDLE)" ]; then \
	  cp -R "$(CC_BUNDLE)" "$(APP_BUNDLE)/"; \
	  echo "Embedded ClearShotModule.bundle inside ClearShot.app."; \
	else \
	  echo "ERROR: CC bundle not built at $(CC_BUNDLE)"; \
	  find $(THEOS_STAGING_DIR) -name 'ClearShotModule*'; \
	  exit 1; \
	fi
	@if [ -d "$(CC_REC_BUNDLE)" ]; then \
	  cp -R "$(CC_REC_BUNDLE)" "$(APP_BUNDLE)/"; \
	  echo "Embedded ClearShotRecordModule.bundle inside ClearShot.app."; \
	else \
	  echo "NOTE: Record CC bundle missing at $(CC_REC_BUNDLE) — Capture-only install"; \
	fi
	@# --- 3) App-level Info.plist and icons at the root of the .app bundle.
	@cp -f Info.plist $(APP_BUNDLE)/Info.plist
	@find Resources -maxdepth 1 -name 'icon-*.png' -exec cp -f {} $(APP_BUNDLE)/ \; 2>/dev/null || true
	@# Embed haoict's killall binary (from ResolutionSetterSwift 1.1 IPA) so
	@# ResSetter can respring via rootSpawn $(APP_BUNDLE)/killall SpringBoard.
	@# Our CSProcessUtils.forceRespring uses in-process kill+sysctl today
	@# which also works; this is a backup path for parity with upstream.
	@if [ -f Resources/killall ]; then \
	  cp -f Resources/killall $(APP_BUNDLE)/killall; \
	  chmod +x $(APP_BUNDLE)/killall; \
	  echo "Embedded killall helper for ResSetter."; \
	fi
	@# --- 3b) Embed the hook dylibs inside the .app so the UI can hand
	@# them to TFInjector at one tap (SpringBoard Tweaks → Clear All,
	@# ClearShot → Native gesture bypass). Both dylibs land at
	@# $(APP_BUNDLE)/<leafname> which matches the path the UI probes.
	@if [ -f "$(HOOK_SHOT)" ]; then \
	  cp -f "$(HOOK_SHOT)" "$(APP_BUNDLE)/"; \
	  echo "Embedded libClearShotHook.dylib inside ClearShot.app."; \
	else \
	  echo "NOTE: libClearShotHook.dylib missing — Native gesture bypass stays greyed out"; \
	fi
	@if [ -f "$(HOOK_CLEAR)" ]; then \
	  cp -f "$(HOOK_CLEAR)" "$(APP_BUNDLE)/"; \
	  echo "Embedded libClearAllHook.dylib inside ClearShot.app."; \
	else \
	  echo "NOTE: libClearAllHook.dylib missing — Clear All toggle stays greyed out"; \
	fi
	@# --- 4) Embed the Ad Blocking assets (4 PACs + 2 mobileconfig templates).
	@# These are read at runtime by ABMainViewController to build the user's
	@# chosen mobileconfig on-device.
	@mkdir -p $(APP_BUNDLE)/AdBlock/PAC
	@mkdir -p $(APP_BUNDLE)/AdBlock/Templates
	@cp -f MYbloXX/PAC/*.pac           $(APP_BUNDLE)/AdBlock/PAC/   2>/dev/null || echo "WARN: MYbloXX/PAC/ missing"
	@cp -f MYbloXX/Templates/*.plist   $(APP_BUNDLE)/AdBlock/Templates/ 2>/dev/null || echo "WARN: MYbloXX/Templates/ missing"
	@echo "== Final .app bundle contents =="
	@ls -la $(APP_BUNDLE)
	@echo "== CC bundle inside .app =="
	@ls -la $(APP_BUNDLE)/ClearShotModule.bundle
	@echo "== AdBlock assets =="
	@ls -la $(APP_BUNDLE)/AdBlock/PAC/ $(APP_BUNDLE)/AdBlock/Templates/ 2>/dev/null
	@# --- 5) Convert to Payload/ layout for the .tipa. Theos stages the
	@# dylibs standalone at Applications/libClearShotHook.dylib + the Clear
	@# All twin — we only want them INSIDE the .app (step 3b above), not as
	@# siblings. rm -rf Applications after we moved the .app safely.
	@mkdir -p $(THEOS_STAGING_DIR)/Payload
	@mv $(APP_BUNDLE) $(THEOS_STAGING_DIR)/Payload/
	@rm -rf $(THEOS_STAGING_DIR)/Applications
	@rm -rf $(THEOS_STAGING_DIR)/Library
	@echo "========== end after-stage =========="
