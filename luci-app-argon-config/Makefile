include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-argon-config
PKG_VERSION:=2.1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0

PKG_MAINTAINER:=jerrykuku <jerrykuku@qq.com>

LUCI_TITLE:=LuCI app for Argon theme configuration
LUCI_PKGARCH:=all
LUCI_BASENAME:=argon-config-app
LUCI_DEPENDS:=+luci-base +luci-theme-argon +rpcd-mod-file +cgi-io +jshn

# Keep APK translation versions valid even outside a Git checkout.
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

define Package/$(PKG_NAME)/preinst
#!/bin/sh
root="$${IPKG_INSTROOT}"
if [ -f "$$root/etc/config/argon" ]; then
	umask 077
	mkdir -p "$$root/etc/argon-config-app-migration" || exit 1
	cp -p "$$root/etc/config/argon" "$$root/etc/argon-config-app-migration/argon" || exit 1
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
