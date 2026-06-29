#
# Copyright (C) 2024 远程开机项目
#
# This is free software, licensed under the GPLv2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wol-remote
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=WOL Remote - Remote wake-on-LAN via server API polling
LUCI_DESCRIPTION:=Periodically polls a remote server for pending wake requests and sends WoL magic packets on the LAN.
LUCI_DEPENDS:=+etherwake +curl +luci-base
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt build system integration
